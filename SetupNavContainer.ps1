if (!(Test-Path function:Log)) {
    function Log([string]$line, [string]$color = "Gray") {
        ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt"
        Write-Host -ForegroundColor $color $line 
    }
}

if (Test-Path -Path "C:\demo\navcontainerhelper-dev\NavContainerHelper.psm1") {
    Import-module "C:\demo\navcontainerhelper-dev\NavContainerHelper.psm1" -DisableNameChecking
} else {
    Import-Module -name navcontainerhelper -DisableNameChecking
}

$settingsScript = Join-Path $PSScriptRoot "settings.ps1"

. "$settingsScript"

if ($Office365UserName -eq "" -or $Office365Password -eq "") {
    $auth = "NavUserPassword"
    if (Test-Path "c:\myfolder\SetupConfiguration.ps1") {
        Remove-Item -Path "c:\myfolder\SetupConfiguration.ps1" -Force
    }
}
else {
    $auth = "AAD"
    if (Test-Path "c:\myfolder\SetupConfiguration.ps1") {
        Log "Reusing existing Aad Apps for Office 365 integration"
    }
    else {
        '. "c:\run\SetupConfiguration.ps1"
        ' | Set-Content "c:\myfolder\SetupConfiguration.ps1"

        Log "Creating Aad Apps for Office 365 integration"
        $publicWebBaseUrl = "https://$publicDnsName/NAV/"
        $secureOffice365Password = ConvertTo-SecureString -String $Office365Password -Key $passwordKey
        $Office365Credential = New-Object System.Management.Automation.PSCredential($Office365UserName, $secureOffice365Password)
        try {
            $AdProperties = Create-AadAppsForNav -AadAdminCredential $Office365Credential -appIdUri $publicWebBaseUrl -IncludeExcelAadApp -IncludePowerBiAadApp

            $SsoAdAppId = $AdProperties.SsoAdAppId
            $SsoAdAppKeyValue = $AdProperties.SsoAdAppKeyValue
            $ExcelAdAppId = $AdProperties.ExcelAdAppId
            $PowerBiAdAppId = $AdProperties.PowerBiAdAppId
            $PowerBiAdAppKeyValue = $AdProperties.PowerBiAdAppKeyValue

    'Write-Host "Changing Server config to NavUserPassword to enable basic web services"
    Set-NAVServerConfiguration -ServerInstance nav -KeyName "ClientServicesCredentialType" -KeyValue "NavUserPassword" -WarningAction Ignore
    Set-NAVServerConfiguration -ServerInstance nav -KeyName "ExcelAddInAzureActiveDirectoryClientId" -KeyValue "'+$ExcelAdAppId+'" -WarningAction Ignore
    Set-NAVServerConfiguration -ServerInstance nav -KeyName "ValidAudiences" -KeyValue "'+$SsoAdAppId+'" -WarningAction Ignore -ErrorAction Ignore
    ' | Add-Content "c:\myfolder\SetupConfiguration.ps1"
            
            $settings = Get-Content -path "c:\demo\settings.ps1"

            $settings += "`$SsoAdAppId = '$SsoAdAppId'"
            $settings += "`$SsoAdAppKeyValue = '$SsoAdAppKeyValue'"
            $settings += "`$ExcelAdAppId = '$ExcelAdAppId'"
            $settings += "`$PowerBiAdAppId = '$PowerBiAdAppId'"
            $settings += "`$PowerBiAdAppKeyValue = '$PowerBiAdAppKeyValue'"

            Set-Content -Path $settingsScript -Value $settings
    
        } catch {
            Log -color Red $_.Exception.Message
            Log -color Red "Reverting to NavUserPassword authentication"
        }
    }
}

$imageName = Get-BestNavContainerImageName -imageName ($navDockerImage.Split(',')[0])

docker ps --filter name=$containerName -a -q | % {
    Log "Removing container $containerName"
    docker rm $_ -f | Out-Null
}

$exist = $false
docker images -q --no-trunc | ForEach-Object {
    $inspect = docker inspect $_ | ConvertFrom-Json
    if ($inspect | % { $_.RepoTags | Where-Object { "$_" -eq "$imageName" -or "$_" -eq "${imageName}:latest"} } ) { $exist = $true }
}
if (!$exist) {
    Log "Pulling $imageName (this might take ~30 minutes)"
    docker pull $imageName
}

$inspect = docker inspect $imageName | ConvertFrom-Json
$country = $inspect.Config.Labels.country
$navVersion = $inspect.Config.Labels.version
$nav = $inspect.Config.Labels.nav
$cu = $inspect.Config.Labels.cu
$locale = Get-LocaleFromCountry $country

if ($nav -eq "2016" -or $nav -eq "2017" -or $nav -eq "2018") {
    $title = "Dynamics NAV $nav Demonstration Environment"
} elseif ($nav -eq "main") {
    $title = "Dynamics 365 Business Central Preview Environment"
} else {
    $title = "Dynamics 365 Business Central Sandbox Environment"
}

Log "Using image $imageName"
Log "Country $country"
Log "Version $navVersion"
Log "Locale $locale"

$securePassword = ConvertTo-SecureString -String $adminPassword -Key $passwordKey
$credential = New-Object System.Management.Automation.PSCredential($navAdminUsername, $securePassword)
$azureSqlCredential = New-Object System.Management.Automation.PSCredential($azureSqlAdminUsername, $securePassword)
$params = @{ "licensefile" = "$licensefileuri"
             "publicDnsName" = $publicDnsName }

if ($AddTraefik -eq "Yes") {
    $params += @{ "useTraefik" = $true }
}
else {
    $params.Add("publishPorts", @(8080,443,7046,7047,7048,7049))
}

$additionalParameters = @("--env RemovePasswordKeyFile=N",
                          "--storage-opt size=100GB")

if ("$appBacpacUri" -ne "" -and "$tenantBacpacUri" -ne "") {
    if ("$sqlServerType" -eq "SQLExpress") {
        $additionalParameters += @("--env appbacpac=$appBacpacUri",
                                   "--env tenantbacpac=$tenantBacpacUri")
    } else {
        Log "using $azureSqlServer as database server"
        $params += @{ "databaseServer"     = "$azureSqlServer"
                      "databaseInstance"   = ""
                      "databaseName"       = "App"
                      "databaseCredential" = $azureSqlCredential }
        $multitenant = "Yes"
    }
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

if ($includeCSIDE -eq "Yes" -or $includeAL -eq "Yes") {
    $params += @{ 
        "doNotExportObjectsToText" = $true
    }
}

if ($multitenant -eq "Yes") {
    $params += @{ "multitenant" = $true }
}

if ($assignPremiumPlan -eq "Yes") {
    $params += @{ "assignPremiumPlan" = $true }
}

$myScripts = @()
Get-ChildItem -Path "c:\myfolder" | % { $myscripts += $_.FullName }

try {
    Log "Running $imageName (this will take a few minutes)"
    New-NavContainer -accept_eula -accept_outdated @Params `
                     -containerName $containerName `
                     -useSSL `
                     -updateHosts `
                     -auth $Auth `
                     -authenticationEMail $Office365UserName `
                     -credential $credential `
                     -useBestContainerOS `
                     -additionalParameters $additionalParameters `
                     -myScripts $myscripts `
                     -imageName $imageName
    
} catch {
    Log -color Red "Container output"
    docker logs $containerName | % { log $_ }
    throw
}

if ($auth -eq "AAD") {
    if (([System.Version]$navVersion).Major -lt 13) {
        $fobfile = Join-Path $env:TEMP "AzureAdAppSetup.fob"
        Download-File -sourceUrl "http://aka.ms/azureadappsetupfob" -destinationFile $fobfile
        $sqlCredential = New-Object System.Management.Automation.PSCredential ( "sa", $credential.Password )
        Import-ObjectsToNavContainer -containerName $containerName -objectsFile $fobfile -sqlCredential $sqlCredential
        Invoke-NavContainerCodeunit -containerName $containerName -tenant "default" -CodeunitId 50000 -MethodName SetupAzureAdApp -Argument ($PowerBiAdAppId+','+$PowerBiAdAppKeyValue)
    } 
    else {
        $appfile = Join-Path $env:TEMP "AzureAdAppSetup.app"
        Download-File -sourceUrl "http://aka.ms/Microsoft_AzureAdAppSetup_13.0.0.0.app" -destinationFile $appfile

        Publish-NavContainerApp -containerName $containerName -appFile $appFile -skipVerification -install -sync

        $companyId = Get-NavContainerApiCompanyId -containerName $containerName -tenant "default" -credential $credential

        $parameters = @{ 
            "name" = "SetupAzureAdApp"
            "value" = "$PowerBiAdAppId,$PowerBiAdAppKeyValue"
        }
        Invoke-NavContainerApi -containerName $containerName -tenant "default" -credential $credential -APIPublisher "Microsoft" -APIGroup "Setup" -APIVersion "beta" -CompanyId $companyId -Method "POST" -Query "aadApps" -body $parameters | Out-Null

        UnPublish-NavContainerApp -containerName $containerName -appName AzureAdAppSetup -unInstall
    }
}

if ($CreateTestUsers -eq "Yes") {
    Setup-NavContainerTestUsers -containerName $containerName -tenant "default" -password $credential.Password -credential $credential
}

if ($CreateAadUsers -eq "Yes" -and $Office365UserName -ne "" -and $Office365Password -ne "") {
    Log "Creating Aad Users"
    $secureOffice365Password = ConvertTo-SecureString -String $Office365Password -Key $passwordKey
    $Office365Credential = New-Object System.Management.Automation.PSCredential($Office365UserName, $secureOffice365Password)
    Create-AadUsersInNavContainer -containerName $containerName -tenant "default" -AadAdminCredential $Office365Credential -permissionSetId SUPER -securePassword $securePassword
}

if ($sqlServerType -eq "AzureSQL") {
    if (Test-Path "c:\demo\objects.fob" -PathType Leaf) {
        Log "Importing c:\demo\objects.fob to container"
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
        Log "Importing c:\demo\objects.fob to container"
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

    $appFile = switch (([System.Version]$navVersion).Major) {
     9 { "" }
    10 { "" }
    11 { "http://aka.ms/bingmaps11.app" }
    default { "http://aka.ms/bingmaps.app" }
    }

    if ($appFile -eq "") {
        Log "BingMaps app is not supported for this version of NAV"
    } else {
        Log "Create Web Services Key for admin user"
        $webServicesKey = (Get-NavContainerNavUser -containerName $containerName -tenant "default" | Where-Object { $_.Username -eq $navAdminUsername }).WebServicesKey
        if ("$webServicesKey" -eq "") {
            $session = Get-NavContainerSession -containerName $containerName
            Invoke-Command -Session $session -ScriptBlock { Param($navAdminUsername)
                Set-NAVServerUser -ServerInstance NAV -Tenant "default" -UserName $navAdminUsername -CreateWebServicesKey 
            } -ArgumentList $navAdminUsername
            $webServicesKey = (Get-NavContainerNavUser -containerName $containerName -tenant "default" | Where-Object { $_.Username -eq $navAdminUsername }).WebServicesKey
        }
        
        Log "Installing BingMaps app from $appFile"
        Publish-NavContainerApp -containerName $containerName `
                                -tenant "default" `
                                -packageType Extension `
                                -appFile $appFile `
                                -skipVerification `
                                -sync `
                                -install
    
        Log "Geocode customers"
        Get-CompanyInNavContainer -containerName $containerName | % {
            Invoke-NavContainerCodeunit -containerName $containerName `
                                        -tenant "default" `
                                        -CompanyName $_.CompanyName `
                                        -Codeunitid 50103 `
                                        -MethodName "SetBingMapsSettings" `
                                        -Argument ('{ "BingMapsKey":"' + $bingMapsKey + '","WebServicesUsername": "' + $navAdminUsername + '","WebServicesKey": "' + $webServicesKey + '"}')
        }
    }
}

# Copy .vsix and Certificate to container folder
$containerFolder = "C:\ProgramData\navcontainerhelper\Extensions\$containerName"
Log "Copying .vsix and Certificate to $containerFolder"
docker exec -t $containerName powershell "copy-item -Path 'C:\Run\*.vsix' -Destination '$containerFolder' -force
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
    Log "Importing $certFileName to trusted root"
    $pfx = new-object System.Security.Cryptography.X509Certificates.X509Certificate2 
    $pfx.import($certFileName)
    $store = new-object System.Security.Cryptography.X509Certificates.X509Store([System.Security.Cryptography.X509Certificates.StoreName]::Root,"localmachine")
    $store.open("MaxAllowed") 
    $store.add($pfx) 
    $store.close()
}

Log -color Green "Container output"
docker logs $containerName | % { log $_ }

Log -color Green "Container setup complete!"
