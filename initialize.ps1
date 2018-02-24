#usage initialize.ps1
param
(
       [string]$templateLink              = "https://raw.githubusercontent.com/Microsoft/nav-arm-templates/master/navdeveloperpreview.json",
       [string]$containerName             = "navserver",
       [string]$hostName                  = "",
       [string]$vmAdminUsername           = "vmadmin",
       [string]$navAdminUsername          = "admin",
       [string]$azureSqlAdminUsername     = "sqladmin",
       [string]$adminPassword             = "P@ssword1",
       [string]$navDockerImage            = "microsoft/dynamics-nav:devpreview-finus",
       [string]$registryUsername          = "",
       [string]$registryPassword          = "",
       [string]$sqlServerType             = "Express",
       [string]$azureSqlServer            = "",
       [string]$appBacpacUri              = "",
       [string]$tenantBacpacUri           = "",
       [string]$includeAppUris            = "",
       [string]$clickonce                 = "No",
       [string]$licenseFileUri            = "",
       [string]$certificatePfxUrl         = "",
       [string]$certificatePfxPassword    = "",
       [string]$publicDnsName             = "",
	   [string]$fobFileUrl                = "",
	   [string]$workshopFilesUrl          = "",
	   [string]$finalSetupScriptUrl       = "",
       [string]$style                     = "devpreview",
       [string]$RunWindowsUpdate          = "No",
       [string]$Multitenant               = "No",
       [string]$UseLetsEncryptCertificate = "No",
       [string]$ContactEMailForLetsEncrypt= "",
       [string]$RemoteDesktopAccess       = "*",
       [string]$Office365UserName         = "",
       [string]$Office365Password         = "",
       [string]$Office365CreatePortal     = "No"
)

function Get-VariableDeclaration([string]$name) {
    $var = Get-Variable -Name $name
    if ($var) {
        ('$'+$var.Name+' = "'+$var.Value+'"')
    } else {
        ""
    }
}

function Log([string]$line, [string]$color = "Gray") {
    ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt"
}

function Download-File([string]$sourceUrl, [string]$destinationFile)
{
    Log "Downloading $destinationFile"
    Remove-Item -Path $destinationFile -Force -ErrorAction Ignore
    (New-Object System.Net.WebClient).DownloadFile($sourceUrl, $destinationFile)
}

if ($publicDnsName -eq "") {
    $publicDnsName = $hostname
}

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls -bor [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls12

$settingsScript = "c:\demo\settings.ps1"
if (Test-Path $settingsScript) {
    . "$settingsScript"
} else {
    New-Item -Path "c:\myfolder" -ItemType Directory -ErrorAction Ignore | Out-Null
    New-Item -Path "C:\DEMO" -ItemType Directory -ErrorAction Ignore | Out-Null
    
    Get-VariableDeclaration -name "templateLink"           | Set-Content $settingsScript
    Get-VariableDeclaration -name "hostName"               | Add-Content $settingsScript
    Get-VariableDeclaration -name "containerName"          | Add-Content $settingsScript
    Get-VariableDeclaration -name "vmAdminUsername"        | Add-Content $settingsScript
    Get-VariableDeclaration -name "navAdminUsername"       | Add-Content $settingsScript
    Get-VariableDeclaration -name "azureSqlAdminUsername"  | Add-Content $settingsScript
    Get-VariableDeclaration -name "Office365Username"      | Add-Content $settingsScript
    Get-VariableDeclaration -name "Office365CreatePortal"  | Add-Content $settingsScript
    Get-VariableDeclaration -name "navDockerImage"         | Add-Content $settingsScript
    Get-VariableDeclaration -name "registryUsername"       | Add-Content $settingsScript
    Get-VariableDeclaration -name "registryPassword"       | Add-Content $settingsScript
    Get-VariableDeclaration -name "sqlServerType"          | Add-Content $settingsScript
    Get-VariableDeclaration -name "azureSqlServer"         | Add-Content $settingsScript
    Get-VariableDeclaration -name "appBacpacUri"           | Add-Content $settingsScript
    Get-VariableDeclaration -name "tenantBacpacUri"        | Add-Content $settingsScript
    Get-VariableDeclaration -name "includeAppUris"         | Add-Content $settingsScript
    Get-VariableDeclaration -name "clickonce"              | Add-Content $settingsScript
    Get-VariableDeclaration -name "licenseFileUri"         | Add-Content $settingsScript
    Get-VariableDeclaration -name "publicDnsName"          | Add-Content $settingsScript
    Get-VariableDeclaration -name "workshopFilesUrl"       | Add-Content $settingsScript
    Get-VariableDeclaration -name "style"                  | Add-Content $settingsScript
    Get-VariableDeclaration -name "RunWindowsUpdate"       | Add-Content $settingsScript
    Get-VariableDeclaration -name "Multitenant"            | Add-Content $settingsScript

    $passwordKey = New-Object Byte[] 16
    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($passwordKey)
    ('$passwordKey = [byte[]]@('+"$passwordKey".Replace(" ",",")+')') | Add-Content $settingsScript

    $securePassword = ConvertTo-SecureString -String $adminPassword -AsPlainText -Force
    $encPassword = ConvertFrom-SecureString -SecureString $securePassword -Key $passwordKey
    ('$adminPassword = "'+$encPassword+'"') | Add-Content $settingsScript

    $secureOffice365Password = ConvertTo-SecureString -String $Office365Password -AsPlainText -Force
    $encOffice365Password = ConvertFrom-SecureString -SecureString $secureOffice365Password -Key $passwordKey
    ('$Office365Password = "'+$encOffice365Password+'"') | Add-Content $settingsScript
}

#
# styles:
#   devpreview
#   developer
#   workshop
#   sandbox
#   demo
#

$includeWindowsClient = $true

if (Test-Path -Path "c:\DEMO\Status.txt" -PathType Leaf) {
    Log "VM already initialized."
    exit
}

Set-Content "c:\DEMO\RemoteDesktopAccess.txt" -Value $RemoteDesktopAccess

Set-ExecutionPolicy -ExecutionPolicy unrestricted -Force

Log -color Green "Starting initialization"
Log "TemplateLink: $templateLink"
$scriptPath = $templateLink.SubString(0,$templateLink.LastIndexOf('/')+1)

New-Item -Path "C:\DOWNLOAD" -ItemType Directory -ErrorAction Ignore | Out-Null

#Log "Upgrading Docker Engine"
#Unregister-PackageSource -ProviderName DockerMsftProvider -Name DockerDefault -Erroraction Ignore
#Register-PackageSource -ProviderName DockerMsftProvider -Name Docker -Erroraction Ignore -Location https://download.docker.com/components/engine/windows-server/index.json
#Install-Package -Name docker -ProviderName DockerMsftProvider -Update -Force
#Start-Service docker

Log "Installing Internet Information Server (this might take a few minutes)"
Add-WindowsFeature Web-Server,web-Asp-Net45
Remove-Item -Path "C:\inetpub\wwwroot\iisstart.*" -Force
Download-File -sourceUrl "${scriptPath}Default.aspx"            -destinationFile "C:\inetpub\wwwroot\default.aspx"
Download-File -sourceUrl "${scriptPath}status.aspx"             -destinationFile "C:\inetpub\wwwroot\status.aspx"
Download-File -sourceUrl "${scriptPath}line.png"                -destinationFile "C:\inetpub\wwwroot\line.png"
Download-File -sourceUrl "${scriptPath}Microsoft.png"           -destinationFile "C:\inetpub\wwwroot\Microsoft.png"
Download-File -sourceUrl "${scriptPath}web.config"              -destinationFile "C:\inetpub\wwwroot\web.config"

$title = 'Dynamics NAV Container Host'
[System.IO.File]::WriteAllText("C:\inetpub\wwwroot\title.txt", $title)
[System.IO.File]::WriteAllText("C:\inetpub\wwwroot\hostname.txt", $publicDnsName)

if ("$RemoteDesktopAccess" -ne "-") {
Log "Creating Connect.rdp"
"full address:s:${publicDnsName}:3389
prompt for credentials:i:1
username:s:$vmAdminUsername" | Set-Content "c:\inetpub\wwwroot\Connect.rdp"
}

Log "Enabling Docker API"
'{
    "hosts": ["tcp://0.0.0.0:2375", "npipe://"]
}' | Set-Content "C:\ProgramData\docker\config\daemon.json"
restart-service docker
netsh advfirewall firewall add rule name="Docker" dir=in action=allow protocol=TCP localport=2375

Log "Turning off IE Enhanced Security Configuration"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 | Out-Null
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 | Out-Null

$setupDesktopScript = "c:\demo\SetupDesktop.ps1"
$setupStartScript = "c:\demo\SetupStart.ps1"
$setupVmScript = "c:\demo\SetupVm.ps1"
$setupNavContainerScript = "c:\demo\SetupNavContainer.ps1"

Download-File -sourceUrl "${scriptPath}SetupNavUsers.ps1" -destinationFile "c:\myfolder\SetupNavUsers.ps1"

if ($vmAdminUsername -ne $navAdminUsername) {
    '. "c:\run\SetupWindowsUsers.ps1"
    Write-Host "Creating Host Windows user"
    $hostUsername = "'+$vmAdminUsername+'"
    if (!($securePassword)) {
        # old version of the generic nav container
        $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
    }
    New-LocalUser -AccountNeverExpires -FullName $hostUsername -Name $hostUsername -Password $securePassword -ErrorAction Ignore | Out-Null
    Add-LocalGroupMember -Group administrators -Member $hostUsername -ErrorAction Ignore' | Set-Content "c:\myfolder\SetupWindowsUsers.ps1"
}

'. "c:\run\SetupConfiguration.ps1"
if ($auth -eq "AccessControlService") {
    Write-Host "Changing Server config to NavUserPassword to enable basic web services"
    Set-NAVServerConfiguration -ServerInstance nav -KeyName ClientServicesCredentialType -KeyValue NavUserPassword -WarningAction Ignore
}
Set-NAVServerConfiguration -ServerInstance nav -KeyName EnableSaasExtensionInstall -KeyValue true -ErrorAction Ignore -WarningAction Ignore
' | Set-Content "c:\myfolder\SetupConfiguration.ps1"

Download-File -sourceUrl "${scriptPath}SetupDesktop.ps1"      -destinationFile $setupDesktopScript
Download-File -sourceUrl "${scriptPath}SetupNavContainer.ps1" -destinationFile $setupNavContainerScript
Download-File -sourceUrl "${scriptPath}SetupVm.ps1"           -destinationFile $setupVmScript
Download-File -sourceUrl "${scriptPath}SetupStart.ps1"        -destinationFile $setupStartScript
Download-File -sourceUrl "${scriptPath}Install-VS2017Community.ps1" -destinationFile "C:\DEMO\Install-VS2017Community.ps1"

if ($finalSetupScriptUrl) {
    $finalSetupScript = "c:\demo\FinalSetupScript.ps1"
    Download-File -sourceUrl $finalSetupScriptUrl -destinationFile $finalSetupScript
}


if ($licenseFileUri -ne "") {
    Download-File -sourceUrl $licenseFileUri -destinationFile "c:\demo\license.flf"
}

if ($fobFileUrl -ne "") {
    Download-File -sourceUrl $fobFileUrl -destinationFile "c:\demo\objects.fob"
}

if ($workshopFilesUrl -ne "") {
    $workshopFilesFolder = "c:\WorkshopFiles"
    $workshopFilesFile = "C:\DOWNLOAD\WorkshopFiles.zip"
    New-Item -Path $workshopFilesFolder -ItemType Directory -ErrorAction Ignore | Out-Null
	Download-File -sourceUrl $workshopFilesUrl -destinationFile $workshopFilesFile
    Log "Unpacking Workshop Files to $WorkshopFilesFolder"
	[Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.Filesystem") | Out-Null
	[System.IO.Compression.ZipFile]::ExtractToDirectory($workshopFilesFile, $workshopFilesFolder)
}

Log "Install Nav Container Helper from PowerShell Gallery"
Install-Module -Name navcontainerhelper -RequiredVersion 0.2.6.5 -Force
Import-Module -Name navcontainerhelper -DisableNameChecking

if ($certificatePfxUrl -ne "" -and $certificatePfxPassword -ne "") {
    Download-File -sourceUrl $certificatePfxUrl -destinationFile "c:\programdata\navcontainerhelper\certificate.pfx"

('$certificatePfxPassword = "'+$certificatePfxPassword+'"
$certificatePfxFile = "c:\programdata\navcontainerhelper\certificate.pfx"
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certificatePfxFile, $certificatePfxPassword)
$certificateThumbprint = $cert.Thumbprint
Write-Host "Certificate File Thumbprint $certificateThumbprint"
if (!(Get-Item Cert:\LocalMachine\my\$certificateThumbprint -ErrorAction SilentlyContinue)) {
    Write-Host "Import Certificate to LocalMachine\my"
    Import-PfxCertificate -FilePath $certificatePfxFile -CertStoreLocation cert:\localMachine\my -Password (ConvertTo-SecureString -String $certificatePfxPassword -AsPlainText -Force) | Out-Null
}
$dnsidentity = $cert.GetNameInfo("SimpleName",$false)
if ($dnsidentity.StartsWith("*")) {
    $dnsidentity = $dnsidentity.Substring($dnsidentity.IndexOf(".")+1)
}
') | Set-Content "c:\myfolder\SetupCertificate.ps1"

} elseif ($UseLetsEncryptCertificate -eq "Yes") {

    if ("$ContactEMailForLetsEncrypt" -eq "") {
        Log -color Red "Contact EMail not specified for Lets Encrypt, subscriber agreement not accepted, reverting to Self Signed Certificate"
    } else {

        Log "Using Lets Encrypt certificate"

        # Use Lets encrypt
        # If rate limits are hit, log an error and revert to Self Signed

        try {
            Log "Installing ACMESharp PowerShell modules"
            Install-Module -Name ACMESharp -AllowClobber -force -ErrorAction SilentlyContinue
            Install-Module -Name ACMESharp.Providers.IIS -force -ErrorAction SilentlyContinue
            Import-Module ACMESharp
            Enable-ACMEExtensionModule -ModuleName ACMESharp.Providers.IIS -ErrorAction SilentlyContinue
            
            Log "Initializing ACMEVault"
            Initialize-ACMEVault
            
            Log "Register Contact EMail address and accept Terms Of Service"
            New-ACMERegistration -Contacts "mailto:$ContactEMailForLetsEncrypt" -AcceptTos
            
            Log "Creating new dns Identifier"
            $dnsAlias = "dnsAlias"
            New-ACMEIdentifier -Dns $publicDnsName -Alias $dnsAlias

            Log "Performing Lets Encrypt challenge to default web site"
            Complete-ACMEChallenge -IdentifierRef $dnsAlias -ChallengeType http-01 -Handler iis -HandlerParameters @{ WebSiteRef = 'Default Web Site' }
            Submit-ACMEChallenge -IdentifierRef $dnsAlias -ChallengeType http-01
            sleep -s 60
            Update-ACMEIdentifier -IdentifierRef $dnsAlias
            
            Log "Requesting certificate"
            $certAlias = "certAlias"
            $certPassword = [GUID]::NewGuid().ToString()
            $certPfxFilename = "c:\ProgramData\navcontainerhelper\certificate.pfx"
            Remove-Item -Path $certPfxFilename -Force -ErrorAction Ignore
            New-ACMECertificate -Generate -IdentifierRef $dnsAlias -Alias $certAlias
            Submit-ACMECertificate -CertificateRef $certAlias
            Update-ACMECertificate -CertificateRef $certAlias
            Get-ACMECertificate -CertificateRef $certAlias -ExportPkcs12 $certPfxFilename -CertificatePassword $certPassword
            
            $certPemFilename = "c:\ProgramData\navcontainerhelper\certificate.pem"
            Remove-Item -Path $certPemFilename -Force -ErrorAction Ignore
            Get-ACMECertificate -CertificateRef $certAlias -ExportKeyPEM $certPemFilename

            ('$certificatePfxPassword = "'+$certPassword+'"
            $certificatePfxFile = "'+$certPfxFilename+'"
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certificatePfxFile, $certificatePfxPassword)
            $certificateThumbprint = $cert.Thumbprint
            Write-Host "Certificate File Thumbprint $certificateThumbprint"
            if (!(Get-Item Cert:\LocalMachine\my\$certificateThumbprint -ErrorAction SilentlyContinue)) {
                Write-Host "Import Certificate to LocalMachine\my"
                Import-PfxCertificate -FilePath $certificatePfxFile -CertStoreLocation cert:\localMachine\my -Password (ConvertTo-SecureString -String $certificatePfxPassword -AsPlainText -Force) | Out-Null
            }
            $dnsidentity = $cert.GetNameInfo("SimpleName",$false)
            if ($dnsidentity.StartsWith("*")) {
                $dnsidentity = $dnsidentity.Substring($dnsidentity.IndexOf(".")+1)
            }
            ') | Set-Content "c:\myfolder\SetupCertificate.ps1"
        } catch {
            Log -color Red $_.ErrorDetails.Message
            Log -color Red "Reverting to Self Signed Certificate"
        }
    }
}

$startupAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $setupStartScript
$startupTrigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName "SetupStart" `
                       -Action $startupAction `
                       -Trigger $startupTrigger `
                       -RunLevel Highest `
                       -User System | Out-Null

Log "Restarting computer and start Installation tasks"
Restart-Computer -Force
