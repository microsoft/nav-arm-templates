﻿if (!(Test-Path function:AddToStatus)) {
    function AddToStatus([string]$line, [string]$color = "Gray") {
        ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt" -Force -ErrorAction SilentlyContinue
        Write-Host -ForegroundColor $color $line 
    }
}

if (Test-Path -Path "C:\demo\*\BcContainerHelper.psm1") {
    $module = Get-Item -Path "C:\demo\*\BcContainerHelper.psm1"
    Import-module $module.FullName -DisableNameChecking
} else {
    Import-Module -name bccontainerhelper -DisableNameChecking
}

$settingsScript = Join-Path $PSScriptRoot "settings.ps1"

. "$settingsScript"

if ($artifactUrl) {

    if ($artifactUrl -notlike "https://*") {
        $segments = "$artifactUrl/////".Split('/')
        $artifactUrl = Get-BCArtifactUrl -storageAccount $segments[0] -type $segments[1] -version $segments[2] -country $segments[3] -select $segments[4] -sasToken $segments[5] | Select-Object -First 1
    }

    $artifactPaths = Download-Artifacts -artifactUrl $artifactUrl -includePlatform
    $appArtifactPath = $artifactPaths[0]
    $platformArtifactPath = $artifactPaths[1]

    $appManifestPath = Join-Path $appArtifactPath "manifest.json"
    $appManifest = Get-Content $appManifestPath | ConvertFrom-Json

    $nav = ""
    if ($appManifest.PSObject.Properties.name -eq "Nav") {
        $nav = $appManifest.Nav
    }
    
    $cu = ""
    if ($appManifest.PSObject.Properties.name -eq "Cu") {
        $cu =$appManifest.Cu
    }

    $navVersion = $appmanifest.Version
    $country = $appManifest.Country.ToLowerInvariant()
    $locale = Get-LocaleFromCountry $country    

    $Params = @{ 
        "artifactUrl" = $artifactUrl
    }
}
elseif ($navDockerImage) {
    $imageName = Get-BestNavContainerImageName -imageName ($navDockerImage.Split(',')[0])
    docker ps --filter name=$containerName -a -q | % {
        AddToStatus "Removing container $containerName"
        docker rm $_ -f | Out-Null
    }
    
    $exist = $false
    docker images -q --no-trunc | ForEach-Object {
        $inspect = docker inspect $_ | ConvertFrom-Json
        if ($inspect | % { $_.RepoTags | Where-Object { "$_" -eq "$imageName" -or "$_" -eq "${imageName}:latest"} } ) { $exist = $true }
    }
    if (!$exist) {
        AddToStatus "Pulling $imageName (this might take ~30 minutes)"
        docker pull $imageName
    }
    
    $inspect = docker inspect $imageName | ConvertFrom-Json
    $country = $inspect.Config.Labels.country
    $navVersion = $inspect.Config.Labels.version
    $nav = $inspect.Config.Labels.nav
    $cu = $inspect.Config.Labels.cu
    $locale = Get-LocaleFromCountry $country

    $Params = @{ "imageName" = $imageName }
}
else {
    # no artifact, no container - exit
    exit
}

if ($AcceptInsiderEula -eq "Yes") {
    $params += @{ "accept_insiderEula" = $true }
}

if ($Office365Password -eq "" -or (!$Office365UserName.contains('@'))) {
    $auth = "NavUserPassword"
    if (Test-Path "c:\myfolder\SetupConfiguration.ps1") {
        Remove-Item -Path "c:\myfolder\SetupConfiguration.ps1" -Force
    }
}
else {
    $auth = "AAD"

    $secureOffice365Password = ConvertTo-SecureString -String $Office365Password -Key $passwordKey
    $Office365Credential = New-Object System.Management.Automation.PSCredential($Office365UserName, $secureOffice365Password)
    $aadDomain = $Office365UserName.split('@')[1]
    $appIdUri = "https://$($publicDnsName.Split('.')[0]).$($publicDnsName.Split('.')[1]).$aadDomain/BC"

    if (Test-Path "c:\myfolder\SetupConfiguration.ps1") {
        AddToStatus "Reusing existing Aad Apps for Office 365 integration"

        $params += @{
            "AadTenant" = $aadTenantId
            "AadAppId" =  $SsoAdAppId
            "AadAppIdUri" = $appIdUri
        }
    }
    else {
        AddToStatus "Creating Aad Apps for Office 365 integration"
        if (([System.Version]$navVersion).Major -ge 15) {
            if ($AddTraefik -eq "Yes") {
                $publicWebBaseUrl = "https://$publicDnsName/$("$containerName".ToUpperInvariant())/"
            }
            else {
                $publicWebBaseUrl = "https://$publicDnsName/BC/"
            }
        }
        else {
            $publicWebBaseUrl = "https://$publicDnsName/NAV/"
        }

@"
`$appIdUri = '$appIdUri'
. 'c:\run\SetupConfiguration.ps1'
"@ | Set-Content "c:\myfolder\SetupConfiguration.ps1"

        try {
            $authContext = New-BcAuthContext -tenantID $aadDomain -credential $Office365Credential -scopes "https://graph.microsoft.com/.default"
            if (-not $authContext) {
                $authContext = New-BcAuthContext -includeDeviceLogin -scopes "https://graph.microsoft.com/.default" -deviceLoginTimeout ([TimeSpan]::FromSeconds(0))
                AddToStatus $authContext.message
                $authContext = New-BcAuthContext -deviceCode $authContext.deviceCode -deviceLoginTimeout ([TimeSpan]::FromMinutes(30))
                if (-not $authContext) {
                    throw "Failed to authenticate with Office 365"
                }
            }
            $AdProperties = New-AadAppsForBC `
                -bcAuthContext $authContext `
                -appIdUri $appIdUri `
                -publicWebBaseUrl $publicWebBaseUrl `
                -IncludeExcelAadApp `
                -IncludeApiAccess `
                -IncludeOtherServicesAadApp `
                -preAuthorizePowerShell

            $aadTenantId = $authContext.tenantID
            $SsoAdAppId = $AdProperties.SsoAdAppId
            $SsoAdAppKeyValue = $AdProperties.SsoAdAppKeyValue
            $ExcelAdAppId = $AdProperties.ExcelAdAppId
            $ExcelAdAppKeyValue = $AdProperties.ExcelAdAppKeyValue
            $OtherServicesAdAppId = $AdProperties.OtherServicesAdAppId
            $OtherServicesAdAppKeyValue = $AdProperties.OtherServicesAdAppKeyValue
            $ApiAdAppId = $AdProperties.ApiAdAppId
            $ApiAdAppKeyValue = $AdProperties.ApiAdAppKeyValue

@"
Set-NAVServerConfiguration -ServerInstance `$serverInstance -KeyName 'ExcelAddInAzureActiveDirectoryClientId' -KeyValue '$ExcelAdAppId' -WarningAction Ignore
"@ | Add-Content "c:\myfolder\SetupConfiguration.ps1"

            $settings = Get-Content -path $settingsScript | Where-Object { 
                $_ -notlike '$SsoAdAppId = *' -and 
                $_ -notlike '$SsoAdAppKeyValue = *' -and 
                $_ -notlike '$ExcelAdAppId = *' -and 
                $_ -notlike '$ExcelAdAppKeyValue = *' -and 
                $_ -notlike '$ApiAdAppId = *' -and 
                $_ -notlike '$ApiAdAppKeyValue = *' -and 
                $_ -notlike '$OtherServicesAdAppId = *' -and 
                $_ -notlike '$OtherServicesAdAppKeyValue = *' -and 
                $_ -notlike '$aadTenantId = *' }

            $settings += "`$aadTenantId = '$aadTenantId'"
            $settings += "`$SsoAdAppId = '$SsoAdAppId'"
            $settings += "`$SsoAdAppKeyValue = '$SsoAdAppKeyValue'"
            $settings += "`$ExcelAdAppId = '$ExcelAdAppId'"
            $settings += "`$ExcelAdAppKeyValue = '$ExcelAdAppKeyValue'"
            $settings += "`$OtherServicesAdAppId = '$OtherServicesAdAppId'"
            $settings += "`$OtherServicesAdAppKeyValue = '$OtherServicesAdAppKeyValue'"
            $settings += "`$ApiAdAppId = '$ApiAdAppId'"
            $settings += "`$ApiAdAppKeyValue = '$ApiAdAppKeyValue'"

            Set-Content -Path $settingsScript -Value $settings

            $params += @{
                "AadTenant" = $aadTenantId
                "AadAppId" =  $SsoAdAppId
                "AadAppIdUri" = $appIdUri
            }
    
        } catch {
            AddToStatus -color Red $_.Exception.Message
            AddToStatus -color Red "Reverting to NavUserPassword authentication"
            $auth = "NavUserPassword"            
        }
    }
}

if ($nav -eq "2016" -or $nav -eq "2017" -or $nav -eq "2018") {
    $title = "Dynamics NAV $nav Demonstration Environment"
} elseif ($nav -eq "main") {
    $title = "Dynamics 365 Business Central Preview Environment"
} else {
    $title = "Dynamics 365 Business Central Sandbox Environment"
}

if ($artifactUrl) {
    AddToStatus "Using artifactUrl $($artifactUrl.Split('?')[0])"
}
else {
    AddToStatus "Using image $imageName"
}
AddToStatus "Country $country"
AddToStatus "Version $navVersion"
AddToStatus "Locale $locale"

$securePassword = ConvertTo-SecureString -String $adminPassword -Key $passwordKey
$credential = New-Object System.Management.Automation.PSCredential($navAdminUsername, $securePassword)
$azureSqlCredential = New-Object System.Management.Automation.PSCredential($azureSqlAdminUsername, $securePassword)
$params += @{
    "licensefile" = "$licensefileuri"
    "publicDnsName" = $publicDnsName
    "imageName" = "mybc:$navVersion-$country".ToLowerInvariant()
}
        
if ($AddTraefik -eq "Yes") {
    $params += @{ "useTraefik" = $true }
}
else {
    $params.Add("publishPorts", @(8080,443,7046,7047,7048,7049))
}

$additionalParameters = @("--env RemovePasswordKeyFile=N",
                          "--storage-opt size=100GB")

if ("$appBacpacUri" -ne "") {
    if ("$sqlServerType" -eq "SQLExpress") {
        $additionalParameters += @("--env appbacpac=$appBacpacUri",
                                   "--env tenantbacpac=$tenantBacpacUri")
        $params += @{ "timeout" = 7200 }
    }
    elseif ("$sqlServerType" -eq "SQLDeveloper") {
        throw "bacpacs not yet supported with SQLDeveloper"
    }
    else {
        AddToStatus "using $azureSqlServer as database server"
        $params += @{ "databaseServer"     = "$azureSqlServer"
                      "databaseInstance"   = ""
                      "databaseName"       = "App"
                      "databaseCredential" = $azureSqlCredential }
        if ($tenantBacpacUri -ne "") {
            $multitenant = "Yes"
        }
    }
}
elseif ("$sqlServerType" -eq "SQLDeveloper") {

    $DatabaseFolder = "c:\databases"
    $DatabaseName = $containerName
    $dbcredentials = New-Object PSCredential -ArgumentList 'sa', $securePassword
    
    if (!(Test-Path $DatabaseFolder)) {
        New-Item $DatabaseFolder -ItemType Directory | Out-Null
    }
    
    if (Test-Path (Join-Path $DatabaseFolder "$($DatabaseName).*")) {

        Remove-BCContainer $containerName
        
        AddToStatus "Dropping database $DatabaseName from host SQL Server"
        Invoke-SqlCmd -Query "ALTER DATABASE [$DatabaseName] SET OFFLINE WITH ROLLBACK IMMEDIATE" 
        Invoke-Sqlcmd -Query "DROP DATABASE [$DatabaseName]"
        
        AddToStatus "Removing Database files $($databaseFolder)\$($DatabaseName).*"
        Remove-Item -Path (Join-Path $DatabaseFolder "$($DatabaseName).*") -Force
    }

    if ($databaseBakUri) {
        $dbPath = Join-Path "C:\DEMO" "$([Guid]::NewGuid().ToString()).bak"
        Download-File -sourceUrl $databaseBakUri -destinationFile $dbpath
        Restore-SqlDatabase -ServerInstance "localhost" -Database $DatabaseName -BackupFile $dbpath -SqlCredential $dbcredentials -AutoRelocateFile
        Remove-Item $dbPath
    }
    else {
        if ($artifactUrl) {
            if (($appManifest.PSObject.Properties.name -eq 'database') -and ($appManifest.database -ne "")) {
                $dbPath = Join-Path $appArtifactPath $appManifest.database
                Restore-SqlDatabase -ServerInstance "localhost" -Database $DatabaseName -BackupFile $dbpath -SqlCredential $dbcredentials -AutoRelocateFile
            }
            else {
                AddToStatus "WARNING: Application Artifact doesn't contain a database. You need to make sure that the database is restored."
            }
        }
        else {
            $imageName = Get-BestBCContainerImageName -imageName $imageName
            docker pull $imageName
        
            $dbPath = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())
            Extract-FilesFromBCContainerImage -imageName $imageName -extract database -path $dbPath -force
        
            $files = @()
            Get-ChildItem -Path (Join-Path $dbPath "databases") | % {
                $DestinationFile = "{0}\{1}{2}" -f $databaseFolder, $DatabaseName, $_.Extension
                Copy-Item -Path $_.FullName -Destination $DestinationFile -Force
                $files += @("(FILENAME = N'$DestinationFile')")
            }
        
            Remove-Item -Path $dbpath -Recurse -Force
        
            AddToStatus "Attaching files as new Database $DatabaseName on host SQL Server"
            AddToStatus "CREATE DATABASE [$DatabaseName] ON $([string]::Join(", ",$Files)) FOR ATTACH"
            Invoke-SqlCmd -Query "CREATE DATABASE [$DatabaseName] ON $([string]::Join(", ",$Files)) FOR ATTACH"
        }
    }

    AddToStatus "using host as database server"
    $params += @{
        "databaseServer"     = "host.containerhelper.internal"
        "databaseInstance"   = ""
        "databaseName"       = $databaseName
        "databaseCredential" = $dbcredentials
    }
}
elseif ($databaseBakUri) {
    $params += @{ "bakFile" = $databaseBakUri }
}

if ("$clickonce" -eq "Yes") {
    $params += @{"clickonce" = $true}
}

if ("$enableTaskScheduler" -eq "Yes") {
    $additionalParameters += @("--env CustomNavSettings=EnableTaskScheduler=true")
} elseif ("$enableTaskScheduler" -eq "No") {
    $additionalParameters += @("--env CustomNavSettings=EnableTaskScheduler=false")
}

if ($enableSymbolLoading -eq "Yes") {
    $params += @{ "enableSymbolLoading" = $true }
}

if ($includeCSIDE -eq "Yes") {
    $params += @{ 
        "includeCSIDE" = $true
    }
}

if ($includeAL -eq "Yes") {
    $params += @{ 
        "includeAL" = $true
    }
}

if ($isolation -eq "Process" -or $isolation -eq "Hyperv") {
    $params += @{ 
        "isolation" = $isolation
    }
}
else {
    $params += @{
        "useBestContainerOS" = $true
    }
}

if ($includeCSIDE -eq "Yes" -or $includeAL -eq "Yes") {
    $params += @{ 
        "doNotExportObjectsToText" = $true
    }
}

if ($multitenant -eq "Yes") {
    $params += @{ "multitenant" = $true }
}

if ($testToolkit -ne "No") {
    $params += @{ "includeTestToolkit" = $true }
    if ($testToolkit -eq "Framework") {
        $params += @{ "includeTestFrameworkOnly" = $true }
    }
    elseif ($testToolkit -eq "Libraries") {
        $params += @{ "includeTestLibrariesOnly" = $true }
    }
}

if ($assignPremiumPlan -eq "Yes") {
    $params += @{ "assignPremiumPlan" = $true }
}

$myScripts = @()
Get-ChildItem -Path "c:\myfolder" | % { $myscripts += $_.FullName }

try {
    AddToStatus "Running container (this might take some time)"
    New-NavContainer -accept_eula -accept_outdated @Params `
                     -containerName $containerName `
                     -useSSL `
                     -updateHosts `
                     -auth $Auth `
                     -authenticationEMail $Office365UserName `
                     -credential $credential `
                     -additionalParameters $additionalParameters `
                     -myScripts $myscripts
    
} catch {
    AddToStatus -color Red "Container output"
    docker logs $containerName | % { AddToStatus $_ }
    throw
}

if ("$sqlServerType" -eq "SQLDeveloper") {
    if ($artifactUrl) {
        if ($licenseFileUri) {
            $licenseFilePath = "c:\demo\license.flf"
            Download-File -sourceUrl $licensefileuri -destinationFile $licenseFilePath
            Import-NavContainerLicense -containerName $containerName -licenseFile $licenseFilePath
        }
        elseif (($appManifest.PSObject.Properties.name -eq 'licenseFile') -and ($appManifest.licenseFile -ne "")) {
            $licenseFilePath = Join-Path $appArtifactPath $appManifest.licenseFile
            Import-NavContainerLicense -containerName $containerName -licenseFile $licenseFilePath
        }
    }
    New-NavContainerNavUser -containerName $containerName -Credential $credential -ChangePasswordAtNextLogOn:$false -PermissionSetId SUPER
}

if ($auth -eq "AAD") {
    if (([System.Version]$navVersion).Major -lt 13) {
        throw "AAD authentication no longer supported for NAV"
    } 
    else {
        $appfile = Join-Path $env:TEMP "AzureAdAppSetup.app"
        if (([System.Version]$navVersion) -ge ([System.Version]"18.0.0.0")) {
            Download-File -sourceUrl "https://businesscentralapps.blob.core.windows.net/azureadappsetup/18.0.12.0/azureadappsetup-apps.zip" -destinationFile $appfile
        }
        elseif (([System.Version]$navVersion) -ge ([System.Version]"17.1.0.0")) {
            Download-File -sourceUrl "https://businesscentralapps.blob.core.windows.net/azureadappsetup/17.1.11.0/azureadappsetup-apps.zip" -destinationFile $appfile
        }
        elseif (([System.Version]$navVersion) -ge ([System.Version]"15.9.0.0")) {
            Download-File -sourceUrl "https://businesscentralapps.blob.core.windows.net/azureadappsetup/15.9.10.0/azureadappsetup-apps.zip" -destinationFile $appfile
        }
        elseif (([System.Version]$navVersion).Major -ge 15) {
            Download-File -sourceUrl "https://businesscentralapps.blob.core.windows.net/azureadappsetup/15.0.7.0/azureadappsetup-apps.zip" -destinationFile $appfile
        }
        else {
            Download-File -sourceUrl "https://businesscentralapps.blob.core.windows.net/azureadappsetup/Microsoft_AzureAdAppSetup_13.0.0.0.app" -destinationFile $appfile
        }

        Publish-NavContainerApp -containerName $containerName -appFile $appFile -skipVerification -install -sync

        $companyId = Get-NavContainerApiCompanyId -containerName $containerName -tenant "default" -credential $credential

        $parameters = @{ 
            "name" = "SetupAzureAdApp"
            "value" = "$OtherServicesAdAppId,$OtherServicesAdAppKeyValue"
        }
        Invoke-NavContainerApi -containerName $containerName -tenant "default" -credential $credential -APIPublisher "Microsoft" -APIGroup "Setup" -APIVersion "beta" -CompanyId $companyId -Method "POST" -Query "aadApps" -body $parameters | Out-Null

        if (([System.Version]$navVersion) -ge ([System.Version]"18.0.0.0")) {
            $parameters = @{ 
                "name" = "SetupAadApplication"
                "value" = "$ApiAdAppId,API,D365 ADMINISTRATOR:D365 FULL ACCESS"
            }
            Invoke-NavContainerApi -containerName $containerName -tenant "default" -credential $credential -APIPublisher "Microsoft" -APIGroup "Setup" -APIVersion "beta" -CompanyId $companyId -Method "POST" -Query "aadApps" -body $parameters | Out-Null
        }

        if (([System.Version]$navVersion) -ge ([System.Version]"17.1.0.0")) {
            $parameters = @{
                "name" = "SetupEMailAdApp"
                "value" = "$OtherServicesAdAppId,$OtherServicesAdAppKeyValue,$Office365UserName"
            }
            Invoke-NavContainerApi -containerName $containerName -tenant "default" -credential $credential -APIPublisher "Microsoft" -APIGroup "Setup" -APIVersion "beta" -CompanyId $companyId -Method "POST" -Query "aadApps" -body $parameters | Out-Null
    
            if ($sqlServerType -eq "SQLExpress") {
                Invoke-ScriptInBCContainer -containerName $containerName -scriptblock {
                    $config = Get-NAVServerConfiguration -serverinstance $serverinstance -asxml
                    if ($config.SelectSingleNode("//appSettings/add[@key='Multitenant']").Value -eq 'True') {
                        $databaseName = "default"
                    }
                    else {
                        $databaseName = $config.SelectSingleNode("//appSettings/add[@key='DatabaseName']").Value
                    }
                    Invoke-Sqlcmd -Database $databaseName -Query "INSERT INTO [dbo].[NAV App Setting] ([App ID],[Allow HttpClient Requests]) VALUES ('e6328152-bb29-4664-9dae-3bc7eaae1fd8', 1)"
                    Invoke-Sqlcmd -Database $databaseName -Query "UPDATE [dbo].[Isolated Storage] SET [App Id] = 'e6328152-bb29-4664-9dae-3bc7eaae1fd8' WHERE [App Id] = '4C06EAFF-C198-4764-94A4-B695861CE379'"
                }
            }
            else {
                if ($sqlserverType -eq "SQLDeveloper") {
                    $databaseServerInstance = "localhost"
                }
                else {
                    $databaseServerInstance = $params.databaseServer
                }
                if ($params.databaseInstance) {
                    $databaseServerInstance += "\$($params.databaseInstance)"
                }
                Invoke-Sqlcmd -ServerInstance $databaseServerInstance -Database $params.databaseName -Credential $params.databaseCredential -Query "INSERT INTO [dbo].[NAV App Setting] ([App ID],[Allow HttpClient Requests]) VALUES ('e6328152-bb29-4664-9dae-3bc7eaae1fd8', 1)"
                Invoke-Sqlcmd -ServerInstance $databaseServerInstance -Database $params.databaseName -Credential $params.databaseCredential -Query "UPDATE [dbo].[Isolated Storage] SET [App Id] = 'e6328152-bb29-4664-9dae-3bc7eaae1fd8' WHERE [App Id] = '4C06EAFF-C198-4764-94A4-B695861CE379'"
            }
        }

        UnPublish-NavContainerApp -containerName $containerName -appName AzureAdAppSetup -unInstall -doNotSaveData
    }
}

if ($CreateTestUsers -eq "Yes") {
    if ($licenseFileUri -eq "") {
        AddToStatus "Skipping creation of Test Users, as no licensefile has been specified"
    }
    else {
        Setup-NavContainerTestUsers -containerName $containerName -tenant "default" -password $credential.Password -credential $credential
    }
}

if ($CreateAadUsers -eq "Yes" -and $Office365UserName -ne "" -and $Office365Password -ne "") {
    AddToStatus "Creating Aad Users"
    $secureOffice365Password = ConvertTo-SecureString -String $Office365Password -Key $passwordKey
    $Office365Credential = New-Object System.Management.Automation.PSCredential($Office365UserName, $secureOffice365Password)
    Create-AadUsersInNavContainer -containerName $containerName -tenant "default" -AadAdminCredential $Office365Credential -permissionSetId SUPER -securePassword $securePassword
}

if ($sqlServerType -eq "AzureSQL") {
    if (Test-Path "c:\demo\objects.fob" -PathType Leaf) {
        AddToStatus "Importing c:\demo\objects.fob to container"
        Import-ObjectsToNavContainer -containerName $containerName -objectsFile "c:\demo\objects.fob" -sqlCredential $azureSqlCredential
    }
    # Check for Multitenant & Included "-ErrorAction Continue" to prevent an exit
    if ($multitenant -eq "Yes") {
        New-NavContainerTenant -containerName $containerName -tenantId "default" -sqlCredential $azureSqlCredential -ErrorAction Continue
    }    
    # Included "-ErrorAction Continue" to prevent an exit
    New-NavContainerNavUser -containerName $containerName -tenant "default" -Credential $credential -AuthenticationEmail $Office365UserName -ChangePasswordAtNextLogOn:$false -PermissionSetId "SUPER" -ErrorAction Continue
} else {
    if (Test-Path "c:\demo\objects.fob" -PathType Leaf) {
        AddToStatus "Importing c:\demo\objects.fob to container"
        $sqlCredential = New-Object System.Management.Automation.PSCredential ( "sa", $credential.Password )
        Import-ObjectsToNavContainer -containerName $containerName -objectsFile "c:\demo\objects.fob" -sqlCredential $sqlCredential
    }
}

if ("$includeappUris".Trim() -ne "") {
    foreach($includeApp in "$includeAppUris".Split(',;')) {
        Publish-NavContainerApp -containerName $containerName -appFile $includeApp -sync -install -skipVerification
    }
}

if ("$bingmapskey" -ne "") {

    $codeunitId = 0
    $apiMethod = ""
    switch (([System.Version]$navVersion).Major) {
               9 { $appFile = "" }
              10 { $appFile = "" }
              11 { $appFile = "https://businesscentralapps.blob.core.windows.net/bingmaps-pte/freddyk_BingMaps_11.0.0.0.app"; $codeunitId = 50103 }
              12 { $appFile = "https://businesscentralapps.blob.core.windows.net/bingmaps-pte/freddyk_BingMaps_12.0.0.0.app"; $codeunitId = 50103 }
              13 { $appFile = "https://businesscentralapps.blob.core.windows.net/bingmaps-pte/freddyk_BingMaps_12.0.0.0.app"; $codeunitId = 50103 }
              14 { $appFile = "https://businesscentralapps.blob.core.windows.net/bingmaps-pte/freddyk_BingMaps_12.0.0.0.app" }
              15 { $appFile = "https://businesscentralapps.blob.core.windows.net/bingmaps-pte/Freddy%20Kristiansen_BingMaps_15.0.app"; $codeunitId = 70103 }
              16 { $appFile = "https://businesscentralapps.blob.core.windows.net/bingmaps-pte/Freddy%20Kristiansen_BingMaps_16.0.app"; $apiMethod = "Settings" }
              17 { $appFile = "https://businesscentralapps.blob.core.windows.net/bingmaps-pte/Freddy%20Kristiansen_BingMaps_16.0.app"; $apiMethod = "Settings" }
              18 { $appFile = "https://businesscentralapps.blob.core.windows.net/bingmaps-pte/Freddy%20Kristiansen_BingMaps_16.0.app"; $apiMethod = "Settings" }
         default { 
             if ($nchBranch -eq "") {
                $appFile = "https://businesscentralapps.blob.core.windows.net/bingmaps-pte/latest/bingmaps-pte-apps.zip"; $apiMethod = "Settings" 
            }
            else {
                $appFile = "https://businesscentralapps.blob.core.windows.net/bingmaps-pte/preview/bingmaps-pte-apps.zip"; $apiMethod = "Settings" 
            }
        }
    }

    if ($appFile -eq "") {
        AddToStatus "BingMaps app is not supported for this version of NAV"
    }
    else {
        AddToStatus "Create Web Services Key for admin user"
        $webServicesKey = (Get-NavContainerNavUser -containerName $containerName -tenant "default" | Where-Object { $_.Username -eq $navAdminUsername }).WebServicesKey
        if ("$webServicesKey" -eq "") {
            $session = Get-NavContainerSession -containerName $containerName
            Invoke-Command -Session $session -ScriptBlock { Param($navAdminUsername)
                Set-NAVServerUser -ServerInstance $serverInstance -Tenant "default" -UserName $navAdminUsername -CreateWebServicesKey 
            } -ArgumentList $navAdminUsername
            $webServicesKey = (Get-NavContainerNavUser -containerName $containerName -tenant "default" | Where-Object { $_.Username -eq $navAdminUsername }).WebServicesKey
        }
        
        AddToStatus "Installing BingMaps app from $appFile"
        Publish-NavContainerApp -containerName $containerName `
                                -tenant "default" `
                                -packageType Extension `
                                -appFile $appFile `
                                -skipVerification `
                                -sync `
                                -install
    
        if ($codeunitId) {
            AddToStatus "Geocode customers, by invoking codeunit $codeunitId"
            Get-CompanyInNavContainer -containerName $containerName | % {
                Invoke-NavContainerCodeunit -containerName $containerName `
                                            -tenant "default" `
                                            -CompanyName $_.CompanyName `
                                            -Codeunitid $codeunitId `
                                            -MethodName "SetBingMapsSettings" `
                                            -Argument ('{ "BingMapsKey":"' + $bingMapsKey + '","WebServicesUsername": "' + $navAdminUsername + '","WebServicesKey": "' + $webServicesKey + '"}')
            }
        }
        elseif ($apiMethod) {
            AddToStatus "Geocode customers, by invoking api method $apiMethod"

            if ($sqlServerType -eq "SQLExpress") {
                Invoke-ScriptInBCContainer -containerName $containerName -scriptblock {
                    $config = Get-NAVServerConfiguration -serverinstance $serverinstance -asxml
                    if ($config.SelectSingleNode("//appSettings/add[@key='Multitenant']").Value -eq 'True') {
                        $databaseName = "default"
                    }
                    else {
                        $databaseName = $config.SelectSingleNode("//appSettings/add[@key='DatabaseName']").Value
                    }
                    Invoke-Sqlcmd -Database $databaseName -Query "INSERT INTO [dbo].[NAV App Setting] ([App ID],[Allow HttpClient Requests]) VALUES ('a949d4bf-5f3c-49d8-b4be-5359d609683b', 1)"
                }
            }
            else {
                if ($sqlserverType -eq "SQLDeveloper") {
                    $databaseServerInstance = "localhost"
                }
                else {
                    $databaseServerInstance = $params.databaseServer
                }
                if ($params.databaseInstance) {
                    $databaseServerInstance += "\$($params.databaseInstance)"
                }
                Invoke-Sqlcmd -ServerInstance $databaseServerInstance -Database $params.databaseName -Credential $params.databaseCredential -Query "INSERT INTO [dbo].[NAV App Setting] ([App ID],[Allow HttpClient Requests]) VALUES ('a949d4bf-5f3c-49d8-b4be-5359d609683b', 1)"
            }
           
            $tenant = "default"
            $companyId = Get-NavContainerApiCompanyId -containerName $containerName -tenant $tenant -credential $credential

            $parameters = @{ 
                "name" = "BingMapsKey"
                "value" = $bingMapsKey
            }
            Invoke-NavContainerApi `
                -containerName $containerName `
                -tenant $tenant `
                -credential $credential `
                -APIPublisher "Microsoft" `
                -APIGroup "BingMaps" `
                -APIVersion "v1.0" `
                -CompanyId $companyId `
                -Method "POST" `
                -Query $apiMethod `
                -body $parameters | Out-Null
        }
    }
}

# Copy .vsix and Certificate to container folder
$containerFolder = "C:\ProgramData\bccontainerhelper\Extensions\$containerName"
AddToStatus "Copying .vsix and Certificate to $containerFolder"
docker exec $containerName powershell "copy-item -Path 'C:\Run\*.vsix' -Destination '$containerFolder' -force
copy-item -Path 'C:\Run\*.cer' -Destination '$containerFolder' -force
copy-item -Path 'C:\Program Files\Microsoft Dynamics NAV\*\Service\CustomSettings.config' -Destination '$containerFolder' -force
if (Test-Path 'c:\inetpub\wwwroot\http\NAV' -PathType Container) {
    [System.IO.File]::WriteAllText('$containerFolder\clickonce.txt','http://${publicDnsName}:8080/NAV')
}"
[System.IO.File]::WriteAllText("$containerFolder\Version.txt",$navVersion)
[System.IO.File]::WriteAllText("$containerFolder\Cu.txt",$cu)
[System.IO.File]::WriteAllText("$containerFolder\Country.txt", $country)
[System.IO.File]::WriteAllText("$containerFolder\Title.txt",$title)

# Install Certificate on host
$certFile = Get-Item "$containerFolder\*.cer"
if ($certFile) {
    $certFileName = $certFile.FullName
    AddToStatus "Importing $certFileName to trusted root"
    $pfx = new-object System.Security.Cryptography.X509Certificates.X509Certificate2 
    $pfx.import($certFileName)
    $store = new-object System.Security.Cryptography.X509Certificates.X509Store([System.Security.Cryptography.X509Certificates.StoreName]::Root,"localmachine")
    $store.open("MaxAllowed") 
    $store.add($pfx) 
    $store.close()
}

AddToStatus -color Green "Container output"
docker logs $containerName | % { AddToStatus $_ }

AddToStatus -color Green "Container setup complete!"
