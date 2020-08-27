# usage initialize.ps1
param
(
       [string] $templateLink              = "https://raw.githubusercontent.com/Microsoft/nav-arm-templates/master/navdeveloperpreview.json",
       [string] $containerName             = "navserver",
       [string] $hostName                  = "",
       [string] $storageConnectionString   = "",
       [string] $isolation                 = "Default",
       [string] $vmAdminUsername           = "vmadmin",
       [string] $navAdminUsername          = "admin",
       [string] $azureSqlAdminUsername     = "sqladmin",
       [string] $adminPassword             = "P@ssword1",
       [string] $artifactUrl               = "",
       [string] $navDockerImage            = "",
       [string] $registryUsername          = "",
       [string] $registryPassword          = "",
       [string] $sqlServerType             = "SQLExpress",
       [string] $azureSqlServer            = "",
       [string] $appBacpacUri              = "",
       [string] $tenantBacpacUri           = "",
       [string] $databaseBakUri            = "",
       [string] $includeAppUris            = "",
       [string] $enableSymbolLoading       = "No",
       [string] $includeCSIDE              = "No",
       [string] $includeAL                 = "No",
       [string] $clickonce                 = "No",
       [string] $enableTaskScheduler       = "Default",
       [string] $licenseFileUri            = "",
       [string] $certificatePfxUrl         = "",
       [string] $certificatePfxPassword    = "",
       [string] $publicDnsName             = "",
	   [string] $fobFileUrl                = "",
	   [string] $workshopFilesUrl          = "",
	   [string] $beforeContainerSetupScriptUrl = "",
	   [string] $finalSetupScriptUrl       = "",
       [string] $style                     = "devpreview",
       [string] $TestToolkit               = "No",
       [string] $AssignPremiumPlan         = "No",
       [string] $CreateTestUsers           = "No",
       [string] $CreateAadUsers            = "No",
       [string] $RunWindowsUpdate          = "No",
       [string] $Multitenant               = "No",
       [string] $ContactEMailForLetsEncrypt= "",
       [string] $RemoteDesktopAccess       = "*",
       [string] $WinRmAccess               = "-",
       [string] $BingMapsKey               = "",
       [string] $Office365UserName         = "",
       [string] $Office365Password         = "",
       [string] $Office365CreatePortal     = "No",
       [string] $requestToken              = "",
       [string] $createStorageQueue        = "",
       [string] $AddTraefik                = "No",
       [string] $nchBranch                 = ""
)

$verbosePreference = "SilentlyContinue"
$warningPreference = 'Continue'
$errorActionPreference = 'Stop'

function Get-VariableDeclaration([string]$name) {
    $var = Get-Variable -Name $name
    if ($var) {
        ('$'+$var.Name+' = "'+$var.Value+'"')
    } else {
        ""
    }
}

function AddToStatus([string]$line, [string]$color = "Gray") {
    ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt" -Force -ErrorAction SilentlyContinue
}

function Download-File([string]$sourceUrl, [string]$destinationFile)
{
    AddToStatus "Downloading $destinationFile"
    Remove-Item -Path $destinationFile -Force -ErrorAction Ignore
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    (New-Object System.Net.WebClient).DownloadFile($sourceUrl, $destinationFile)
}

if ($publicDnsName -eq "") {
    $publicDnsName = $hostname
}

if ($artifactUrl -ne "" -and $navDockerImage -ne "") {
    # Both artifact Url AND navDockerImage specified, navDockerImage wins
    # Reason: ArtifactUrl is defaulted, navDockerImage is not - hence user must have specified a navDockerImage
    $artifactUrl = ""
}

$ComputerInfo = Get-ComputerInfo
$WindowsInstallationType = $ComputerInfo.WindowsInstallationType
$WindowsProductName = $ComputerInfo.WindowsProductName

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls -bor [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls12

$settingsScript = "c:\demo\settings.ps1"
if (Test-Path $settingsScript) {
    . "$settingsScript"
} else {
    New-Item -Path "c:\myfolder" -ItemType Directory -ErrorAction Ignore | Out-Null
    New-Item -Path "C:\DEMO" -ItemType Directory -ErrorAction Ignore | Out-Null
    
    Get-VariableDeclaration -name "templateLink"           | Set-Content $settingsScript
    Get-VariableDeclaration -name "hostName"               | Add-Content $settingsScript
    Get-VariableDeclaration -name "StorageConnectionString"| Add-Content $settingsScript
    Get-VariableDeclaration -name "containerName"          | Add-Content $settingsScript
    Get-VariableDeclaration -name "isolation"              | Add-Content $settingsScript
    Get-VariableDeclaration -name "vmAdminUsername"        | Add-Content $settingsScript
    Get-VariableDeclaration -name "navAdminUsername"       | Add-Content $settingsScript
    Get-VariableDeclaration -name "azureSqlAdminUsername"  | Add-Content $settingsScript
    Get-VariableDeclaration -name "Office365Username"      | Add-Content $settingsScript
    Get-VariableDeclaration -name "Office365CreatePortal"  | Add-Content $settingsScript
    Get-VariableDeclaration -name "artifactUrl"            | Add-Content $settingsScript
    Get-VariableDeclaration -name "navDockerImage"         | Add-Content $settingsScript
    Get-VariableDeclaration -name "registryUsername"       | Add-Content $settingsScript
    Get-VariableDeclaration -name "registryPassword"       | Add-Content $settingsScript
    Get-VariableDeclaration -name "sqlServerType"          | Add-Content $settingsScript
    Get-VariableDeclaration -name "azureSqlServer"         | Add-Content $settingsScript
    Get-VariableDeclaration -name "appBacpacUri"           | Add-Content $settingsScript
    Get-VariableDeclaration -name "tenantBacpacUri"        | Add-Content $settingsScript
    Get-VariableDeclaration -name "databaseBakUri"         | Add-Content $settingsScript
    Get-VariableDeclaration -name "includeAppUris"         | Add-Content $settingsScript
    Get-VariableDeclaration -name "enableSymbolLoading"    | Add-Content $settingsScript
    Get-VariableDeclaration -name "includeCSIDE"           | Add-Content $settingsScript
    Get-VariableDeclaration -name "includeAL"              | Add-Content $settingsScript
    Get-VariableDeclaration -name "clickonce"              | Add-Content $settingsScript
    Get-VariableDeclaration -name "enableTaskScheduler"    | Add-Content $settingsScript
    Get-VariableDeclaration -name "licenseFileUri"         | Add-Content $settingsScript
    Get-VariableDeclaration -name "publicDnsName"          | Add-Content $settingsScript
    Get-VariableDeclaration -name "workshopFilesUrl"       | Add-Content $settingsScript
    Get-VariableDeclaration -name "style"                  | Add-Content $settingsScript
    Get-VariableDeclaration -name "RunWindowsUpdate"       | Add-Content $settingsScript
    Get-VariableDeclaration -name "TestToolkit"            | Add-Content $settingsScript
    Get-VariableDeclaration -name "AssignPremiumPlan"      | Add-Content $settingsScript
    Get-VariableDeclaration -name "CreateTestUsers"        | Add-Content $settingsScript
    Get-VariableDeclaration -name "CreateAadUsers"         | Add-Content $settingsScript
    Get-VariableDeclaration -name "Multitenant"            | Add-Content $settingsScript
    Get-VariableDeclaration -name "WindowsInstallationType"| Add-Content $settingsScript
    Get-VariableDeclaration -name "WindowsProductName"     | Add-Content $settingsScript
    Get-VariableDeclaration -name "ContactEMailForLetsEncrypt" | Add-Content $settingsScript
    Get-VariableDeclaration -name "RemoteDesktopAccess"    | Add-Content $settingsScript
    Get-VariableDeclaration -name "WinRmAccess"            | Add-Content $settingsScript
    Get-VariableDeclaration -name "BingMapsKey"            | Add-Content $settingsScript
    Get-VariableDeclaration -name "RequestToken"           | Add-Content $settingsScript
    Get-VariableDeclaration -name "CreateStorageQueue"     | Add-Content $settingsScript
    Get-VariableDeclaration -name "AddTraefik"             | Add-Content $settingsScript
    Get-VariableDeclaration -name "nchBranch"              | Add-Content $settingsScript

    $passwordKey = New-Object Byte[] 16
    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($passwordKey)
    ('$passwordKey = [byte[]]@('+"$passwordKey".Replace(" ",",")+')') | Add-Content $settingsScript

    $securePassword = ConvertTo-SecureString -String $adminPassword -AsPlainText -Force
    $encPassword = ConvertFrom-SecureString -SecureString $securePassword -Key $passwordKey
    ('$adminPassword = "'+$encPassword+'"') | Add-Content $settingsScript

    $encOffice365Password = ""
    if ("$Office365Password" -ne "") {
        $secureOffice365Password = ConvertTo-SecureString -String $Office365Password -AsPlainText -Force
        $encOffice365Password = ConvertFrom-SecureString -SecureString $secureOffice365Password -Key $passwordKey
    }
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
    AddToStatus "VM already initialized."
    exit
}

Set-Content "c:\DEMO\RemoteDesktopAccess.txt" -Value $RemoteDesktopAccess
Set-Content "c:\DEMO\WinRmAccess.txt" -Value $WinRmAccess

Set-ExecutionPolicy -ExecutionPolicy unrestricted -Force

AddToStatus -color Green "Starting initialization"
AddToStatus "Running $WindowsProductName"
AddToStatus "Initialize, user: $env:USERNAME"
AddToStatus "TemplateLink: $templateLink"
$scriptPath = $templateLink.SubString(0,$templateLink.LastIndexOf('/')+1)

New-Item -Path "C:\DOWNLOAD" -ItemType Directory -ErrorAction Ignore | Out-Null

if (!(Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction Ignore)) {
    AddToStatus "Installing NuGet Package Provider"
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.208 -Force -WarningAction Ignore | Out-Null
}
if (!(Get-Module powershellget | Where-Object { $_.Version -ge [version]"2.2.1" })) {
    AddToStatus "Installing PowerShellGet 2.2.1"
    Install-Module powershellget -RequiredVersion 2.2.1 -force
    Import-Module powershellget -RequiredVersion 2.2.1
}

AddToStatus "Installing Internet Information Server (this might take a few minutes)"
if ($WindowsInstallationType -eq "Server") {
    Add-WindowsFeature Web-Server,web-Asp-Net45
} else {
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServer,IIS-ASPNET45 -All -NoRestart | Out-Null
}

Remove-Item -Path "C:\inetpub\wwwroot\iisstart.*" -Force
Download-File -sourceUrl "$($scriptPath)Default.aspx"            -destinationFile "C:\inetpub\wwwroot\default.aspx"
Download-File -sourceUrl "$($scriptPath)status.aspx"             -destinationFile "C:\inetpub\wwwroot\status.aspx"
Download-File -sourceUrl "$($scriptPath)line.png"                -destinationFile "C:\inetpub\wwwroot\line.png"
Download-File -sourceUrl "$($scriptPath)Microsoft.png"           -destinationFile "C:\inetpub\wwwroot\Microsoft.png"
Download-File -sourceUrl "$($scriptPath)web.config"              -destinationFile "C:\inetpub\wwwroot\web.config"
if ($requestToken) {
    Download-File -sourceUrl "$($scriptPath)request.aspx"            -destinationFile "C:\inetpub\wwwroot\request.aspx"
}

$title = 'Dynamics Container Host'
[System.IO.File]::WriteAllText("C:\inetpub\wwwroot\title.txt", $title)
[System.IO.File]::WriteAllText("C:\inetpub\wwwroot\hostname.txt", $publicDnsName)

if ("$RemoteDesktopAccess" -ne "") {
AddToStatus "Creating Connect.rdp"
"full address:s:${publicDnsName}:3389
prompt for credentials:i:1
username:s:$vmAdminUsername" | Set-Content "c:\inetpub\wwwroot\Connect.rdp"
}

if ($WindowsInstallationType -eq "Server") {
    AddToStatus "Turning off IE Enhanced Security Configuration"
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 -ErrorAction SilentlyContinue | Out-Null
}

$setupDesktopScript = "c:\demo\SetupDesktop.ps1"
$setupStartScript = "c:\demo\SetupStart.ps1"
$setupVmScript = "c:\demo\SetupVm.ps1"
$setupNavContainerScript = "c:\demo\SetupNavContainer.ps1"
$setupAadScript = "c:\demo\SetupAAD.ps1"

if ($vmAdminUsername -ne $navAdminUsername) {
    '. "c:\run\SetupWindowsUsers.ps1"
Write-Host "Creating Host Windows user"
$hostUsername = "'+$vmAdminUsername+'"
if (!($securePassword)) {
    # old version of the generic nav container
    $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
}
New-LocalUser -AccountNeverExpires -FullName $hostUsername -Name $hostUsername -Password $securePassword -ErrorAction Ignore | Out-Null
Add-LocalGroupMember -Group administrators -Member $hostUsername -ErrorAction Ignore
' | Set-Content "c:\myfolder\SetupWindowsUsers.ps1"
}

Download-File -sourceUrl "$($scriptPath)SetupWebClient.ps1"    -destinationFile "c:\myfolder\SetupWebClient.ps1"

Download-File -sourceUrl "$($scriptPath)SetupDesktop.ps1"      -destinationFile $setupDesktopScript
Download-File -sourceUrl "$($scriptPath)SetupNavContainer.ps1" -destinationFile $setupNavContainerScript
Download-File -sourceUrl "$($scriptPath)SetupVm.ps1"           -destinationFile $setupVmScript
Download-File -sourceUrl "$($scriptPath)SetupStart.ps1"        -destinationFile $setupStartScript
Download-File -sourceUrl "$($scriptPath)RestartContainers.ps1" -destinationFile "c:\demo\restartContainers.ps1"
if ($requestToken) {
    Download-File -sourceUrl "$($scriptPath)Request.ps1"           -destinationFile "C:\DEMO\Request.ps1"
    Download-File -sourceUrl "$($scriptPath)RequestTaskDef.xml"    -destinationFile "C:\DEMO\RequestTaskDef.xml"
}
if ("$createStorageQueue" -eq "yes") {
    Download-File -sourceUrl "$($scriptPath)RunQueue.ps1"          -destinationFile "C:\DEMO\RunQueue.ps1"
}
if ("$requestToken" -ne "" -or "$createStorageQueue" -eq "yes") {
    # Request commands
    New-Item -Path "C:\DEMO\request" -ItemType Directory | Out-Null
    Download-File -sourceUrl "$($scriptPath)request\Demo.ps1"                         -destinationFile "C:\DEMO\request\Demo.ps1"
    Download-File -sourceUrl "$($scriptPath)request\ReplaceNavServerContainer.ps1"    -destinationFile "C:\DEMO\request\ReplaceNavServerContainer.ps1"
    Download-File -sourceUrl "$($scriptPath)request\RestartComputer.ps1"              -destinationFile "C:\DEMO\request\RestartComputer.ps1"
}
Download-File -sourceUrl "$($scriptPath)Install-VS2017Community.ps1" -destinationFile "C:\DEMO\Install-VS2017Community.ps1"

if ($beforeContainerSetupScriptUrl) {
    if ($beforeContainerSetupScriptUrl -notlike "https://*" -and $beforeContainerSetupScriptUrl -notlike "http://*") {
        $beforeContainerSetupScriptUrl = "$($scriptPath)$beforeContainerSetupScriptUrl"
    }
    $beforeContainerSetupScript = "c:\demo\BeforeContainerSetupScript.ps1"
    Download-File -sourceUrl $beforeContainerSetupScriptUrl -destinationFile $beforeContainerSetupScript
}

if ($finalSetupScriptUrl) {
    if ($finalSetupScriptUrl -notlike "https://*" -and $finalSetupScriptUrl -notlike "http://*") {
        $finalSetupScriptUrl = "$($scriptPath)$finalSetupScriptUrl"
    }
    $finalSetupScript = "c:\demo\FinalSetupScript.ps1"
    Download-File -sourceUrl $finalSetupScriptUrl -destinationFile $finalSetupScript
}

if ($fobFileUrl -ne "") {
    Download-File -sourceUrl $fobFileUrl -destinationFile "c:\demo\objects.fob"
}

if ($workshopFilesUrl -ne "") {
    if ($workshopFilesUrl -notlike "https://*" -and $workshopFilesUrl -notlike "http://*") {
        $workshopFilesUrl = "$($scriptPath)$workshopFilesUrl"
    }
    $workshopFilesFolder = "c:\WorkshopFiles"
    $workshopFilesFile = "C:\DOWNLOAD\WorkshopFiles.zip"
    New-Item -Path $workshopFilesFolder -ItemType Directory -ErrorAction Ignore | Out-Null
	Download-File -sourceUrl $workshopFilesUrl -destinationFile $workshopFilesFile
    AddToStatus "Unpacking Workshop Files to $WorkshopFilesFolder"
	[Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.Filesystem") | Out-Null
	[System.IO.Compression.ZipFile]::ExtractToDirectory($workshopFilesFile, $workshopFilesFolder)
}

if ($certificatePfxUrl -ne "" -and $certificatePfxPassword -ne "") {
    Download-File -sourceUrl $certificatePfxUrl -destinationFile "c:\myfolder\certificate.pfx"

('$certificatePfxPassword = "'+$certificatePfxPassword+'"
$certificatePfxFile = Join-Path $PSScriptRoot "certificate.pfx"
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certificatePfxFile, $certificatePfxPassword)
$certificateThumbprint = $cert.Thumbprint
Write-Host "Certificate File Thumbprint $certificateThumbprint"
if (!(Get-Item Cert:\LocalMachine\my\$certificateThumbprint -ErrorAction SilentlyContinue)) {
    Write-Host "Importing Certificate to LocalMachine\my"
    Import-PfxCertificate -FilePath $certificatePfxFile -CertStoreLocation cert:\localMachine\my -Password (ConvertTo-SecureString -String $certificatePfxPassword -AsPlainText -Force) | Out-Null
}
$dnsidentity = $cert.GetNameInfo("SimpleName",$false)
if ($dnsidentity.StartsWith("*")) {
    $dnsidentity = $dnsidentity.Substring($dnsidentity.IndexOf(".")+1)
}
Write-Host "DNS identity $dnsidentity"
') | Set-Content "c:\myfolder\SetupCertificate.ps1"

('Write-Host "DNS identity $dnsidentity"
') | Set-Content "c:\myfolder\AdditionalSetup.ps1"

$ContactEMailForLetsEncrypt = ""
Get-VariableDeclaration -name "ContactEMailForLetsEncrypt" | Add-Content $settingsScript

}

if ($WindowsInstallationType -eq "Server") {
    if (!(Test-Path -Path "C:\Program Files\Docker\docker.exe" -PathType Leaf)) {
        AddToStatus "Installing Docker"
        Install-module DockerMsftProvider -Force
        Install-Package -Name docker -ProviderName DockerMsftProvider -Force
    }
} else {
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V, Containers -All -NoRestart | Out-Null
}

$startupAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy UnRestricted -File $setupStartScript"
$startupTrigger = New-ScheduledTaskTrigger -AtStartup
$startupTrigger.Delay = "PT1M"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd
Register-ScheduledTask -TaskName "SetupStart" `
                       -Action $startupAction `
                       -Trigger $startupTrigger `
                       -Settings $settings `
                       -RunLevel "Highest" `
                       -User "NT AUTHORITY\SYSTEM" | Out-Null

AddToStatus "Restarting computer and start Installation tasks"
Shutdown -r -t 60
