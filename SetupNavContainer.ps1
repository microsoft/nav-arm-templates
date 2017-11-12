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

$country = Get-NavContainerCountry -containerOrImageName $imageName
$navVersion = Get-NavContainerNavVersion -containerOrImageName $imageName
$locale = Get-LocaleFromCountry $country

Log "Using image $imageName"
Log "Country $country"
Log "Version $navVersion"
Log "Locale $locale"

$securePassword = ConvertTo-SecureString -String $adminPassword -Key $passwordKey
$credential = New-Object System.Management.Automation.PSCredential($navAdminUsername, $securePassword)
$additionalParameters = @("--publish  8080:8080",
                          "--publish  443:443", 
                          "--publish  7046-7049:7046-7049", 
                          "--env publicFileSharePort=8080",
                          "--env PublicDnsName=$publicdnsName",
                          "--env RemovePasswordKeyFile=N"
                          )
$myScripts = @()
Get-ChildItem -Path "c:\myfolder" | % { $myscripts += $_.FullName }

Log "Running $imageName (this will take a few minutes)"
New-NavContainer -accept_eula `
                 -containerName $containerName `
                 -useSSL `
                 -includeCSide `
                 -doNotExportObjectsToText `
                 -credential $credential `
                 -additionalParameters $additionalParameters `
                 -myScripts $myscripts `
                 -imageName $imageName

# Copy .vsix and Certificate to container folder
$containerFolder = "C:\Demo\Extensions\$containerName"
Log "Copying .vsix and Certificate to $containerFolder"
docker exec -it $containerName powershell "copy-item -Path 'C:\Run\*.vsix' -Destination '$containerFolder' -force
copy-item -Path 'C:\Run\*.cer' -Destination '$containerFolder' -force
copy-item -Path 'C:\Program Files\Microsoft Dynamics NAV\*\Service\CustomSettings.config' -Destination '$containerFolder' -force
if (Test-Path 'c:\inetpub\wwwroot\http\NAV' -PathType Container) {
    [System.IO.File]::WriteAllText('$containerFolder\clickonce.txt','http://${publicDnsName}:8080/NAV')
}"
[System.IO.File]::WriteAllText("$containerFolder\Version.txt",$navVersion)
[System.IO.File]::WriteAllText("$containerFolder\Country.txt", $country)

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
