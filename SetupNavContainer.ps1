$ErrorActionPreference = "Stop"
$WarningActionPreference = "Ignore"

if (!(Test-Path function:Log)) {
    function Log([string]$line, [string]$color = "Gray") {
        ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt"
        Write-Host -ForegroundColor $color $line 
    }
}

Import-Module -name navcontainerhelper -DisableNameChecking

. (Join-Path $PSScriptRoot "settings.ps1")

$imageName = $navDockerImage.Split(',')[0]

docker ps --filter name=$containerName -a -q | % {
    Log "Removing container $containerName"
    docker rm $_ -f | Out-Null
}

$exist = $false
docker images -q --no-trunc | % {
    $inspect = docker inspect $_ | ConvertFrom-Json
    if ($inspect.RepoTags | Where-Object { "$_" -eq "$imageName" -or "$_" -eq "${imageName}:latest"}) { $exist = $true }
}
if (!$exist) {
    try {
        Log "Pulling $imageName (this might take ~30 minutes)"
        docker pull $imageName
    } catch {
        Log -Color Red -line $_.Exception
        throw
    }
}

$inspect = docker inspect $imageName | ConvertFrom-Json
$country = $inspect.Config.Labels.country
$navVersion = $inspect.Config.Labels.version
$nav = $inspect.Config.Labels.nav
$cu = $inspect.Config.Labels.cu
$locale = Get-LocaleFromCountry $country

if ($nav -eq "devpreview") {
    $title = "Dynamics 365 ""Tenerife"" Preview Environment"
} elseif ($nav -eq "main") {
    $title = "Dynamics 365 ""Tenerife"" Preview Environment"
} else {
    $title = "Dynamics NAV $nav Demonstration Environment"
}

Log "Using image $imageName"
Log "Country $country"
Log "Version $navVersion"
Log "Locale $locale"

$securePassword = ConvertTo-SecureString -String $adminPassword -Key $passwordKey
$credential = New-Object System.Management.Automation.PSCredential($navAdminUsername, $securePassword)
$azureSqlCredential = New-Object System.Management.Automation.PSCredential($azureSqlAdminUsername, $securePassword)
$params = @{}
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

if ($multitenant -eq "Yes") {
    $params += @{ "multitenant" = $true }
}

$myScripts = @()
Get-ChildItem -Path "c:\myfolder" | % { $myscripts += $_.FullName }

$auth = "NavUserPassword"
if ($Office365UserName -ne "" -and $Office365Password -ne "") {
    $auth = "AAD"
}

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

foreach($includeApp in "$includeAppUris".Split(',;')) {
    Publish-NavContainerApp -containerName $containerName -appFile $includeApp -install
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

if ($Office365UserName -ne "" -and $Office365Password -ne "") {
    Log "Creating Aad Apps for Office 365 integration"
    $CustomConfigFile =  Join-Path $containerFolder "CustomSettings.config"
    $CustomConfig = [xml](Get-Content $CustomConfigFile)
    $publicWebBaseUrl = $CustomConfig.SelectSingleNode("//appSettings/add[@key='PublicWebBaseUrl']").Value
    $secureOffice365Password = ConvertTo-SecureString -String $Office365Password -Key $passwordKey
    $Office365Credential = New-Object System.Management.Automation.PSCredential($Office365UserName, $secureOffice365Password)
    Create-AadAppsForNav -AadAdminCredential $Office365Credential -appIdUri $publicWebBaseUrl -IncludeExcelAadApp -IncludePowerBiAadApp
    $auth = "AAD"
}

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
