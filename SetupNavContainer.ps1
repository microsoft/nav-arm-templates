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

. (Join-Path $PSScriptRoot "settings.ps1")

'. "c:\run\SetupConfiguration.ps1"
' | Set-Content "c:\myfolder\SetupConfiguration.ps1"
$auth = "NavUserPassword"
if ($Office365UserName -ne "" -and $Office365Password -ne "") {
    Log "Creating Aad Apps for Office 365 integration"
    $publicWebBaseUrl = "https://$publicDnsName/NAV/"
    $secureOffice365Password = ConvertTo-SecureString -String $Office365Password -Key $passwordKey
    $Office365Credential = New-Object System.Management.Automation.PSCredential($Office365UserName, $secureOffice365Password)
    try {
        $AdProperties = Create-AadAppsForNav -AadAdminCredential $Office365Credential -appIdUri $publicWebBaseUrl -IncludeExcelAadApp -IncludePowerBiAadApp
        $auth = "AAD"
'Write-Host "Changing Server config to NavUserPassword to enable basic web services"
Set-NAVServerConfiguration -ServerInstance nav -KeyName "ClientServicesCredentialType" -KeyValue "NavUserPassword" -WarningAction Ignore
Set-NAVServerConfiguration -ServerInstance nav -KeyName "ExcelAddInAzureActiveDirectoryClientId" -KeyValue "'+$AdProperties.ExcelAdAppId+'" -WarningAction Ignore
Set-NAVServerConfiguration -ServerInstance nav -KeyName "AzureActiveDirectoryClientId" -KeyValue "'+$AdProperties.SsoAdAppId+'" -WarningAction Ignore
Set-NAVServerConfiguration -ServerInstance nav -KeyName "AzureActiveDirectoryClientSecret" -KeyValue "'+$AdProperties.SsoAdAppKeyValue+'" -WarningAction Ignore
}
' | Add-Content "c:\myfolder\SetupConfiguration.ps1"
    } catch {
        Log -color Red $_.ErrorDetails.Message
        Log -color Red "Reverting to NavUserPassword authentication"
    }
}

$imageName = $navDockerImage.Split(',')[0]

docker ps --filter name=$containerName -a -q | % {
    Log "Removing container $containerName"
    docker rm $_ -f | Out-Null
}

$exist = $false
docker images -q --no-trunc | % {
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
$params = @{ "enableSymbolLoading" = $true 
             "licensefile" = "$licensefileuri" }
$additionalParameters = @("--publish  8080:8080",
                          "--publish  443:443", 
                          "--publish  7046-7049:7046-7049", 
                          "--env publicFileSharePort=8080",
                          "--env PublicDnsName=$publicdnsName",
                          "--env RemovePasswordKeyFile=N"
                          )
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
    $additionalParameters += @("--env clickonce=Y")
}

if ("$enableTaskScheduler" -eq "Yes") {
    $additionalParameters += @("--env CustomNavSettings=EnableTaskScheduler=true")
} elseif ("$enableTaskScheduler" -eq "No") {
    $additionalParameters += @("--env CustomNavSettings=EnableTaskScheduler=false")
}

if ($multitenant -eq "Yes") {
    $params += @{ "multitenant" = $true }
}

if ($assignPremiumPlan -eq "Yes") {
    $params += @{ "assignPremiumPlan" = $true }
}

$myScripts = @()
Get-ChildItem -Path "c:\myfolder" | % { $myscripts += $_.FullName }

Log "Running $imageName (this will take a few minutes)"
New-NavContainer -accept_eula @Params `
                 -containerName $containerName `
                 -useSSL `
                 -auth $Auth `
                 -includeCSide `
                 -doNotExportObjectsToText `
                 -authenticationEMail $Office365UserName `
                 -credential $credential `
                 -additionalParameters $additionalParameters `
                 -myScripts $myscripts `
                 -imageName $imageName

if ($auth -eq "AAD") {
    $fobfile = Join-Path $env:TEMP "AzureAdAppSetup.fob"
    Download-File -sourceUrl "http://aka.ms/azureadappsetupfob" -destinationFile $fobfile
    $sqlCredential = New-Object System.Management.Automation.PSCredential ( "sa", $credential.Password )
    Import-ObjectsToNavContainer -containerName $containerName -objectsFile $fobfile -sqlCredential $sqlCredential
    Invoke-NavContainerCodeunit -containerName $containerName -tenant "default" -CodeunitId 50000 -MethodName AzureAdAppSetup -Argument ($AdProperties.PowerBiAdAppId+','+$AdProperties.PowerBiAdAppKeyValue)
}

if ($CreateTestUsers -eq "Yes") {
    Setup-NavContainerTestUsers -containerName $containerName -tenant "default" -password $credential.Password
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
    New-NavContainerTenant -containerName $containerName -tenantId "default" -sqlCredential $azureSqlCredential
    New-NavContainerNavUser -containerName $containerName -tenant "default" -Credential $credential -AuthenticationEmail $Office365UserName -ChangePasswordAtNextLogOn:$false -PermissionSetId "SUPER"
} else {
    if (Test-Path "c:\demo\objects.fob" -PathType Leaf) {
        Log "Importing c:\demo\objects.fob to container"
        $sqlCredential = New-Object System.Management.Automation.PSCredential ( "sa", $credential.Password )
        Import-ObjectsToNavContainer -containerName $containerName -objectsFile "c:\demo\objects.fob" -sqlCredential $sqlCredential
    }
}

if ("$includeappUris".Trim() -ne "") {
    foreach($includeApp in "$includeAppUris".Split(',;')) {
        Publish-NavContainerApp -containerName $containerName -appFile $includeApp -sync -install
    }
}

# Copy .vsix and Certificate to container folder
$containerFolder = "C:\ProgramData\navcontainerhelper\Extensions\$containerName"
Log "Copying .vsix and Certificate to $containerFolder"
docker exec -it $containerName powershell "copy-item -Path 'C:\Run\*.vsix' -Destination '$containerFolder' -force
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
