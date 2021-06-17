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

function Register-NativeMethod([string]$dll, [string]$methodSignature)
{
    $script:nativeMethods += [PSCustomObject]@{ Dll = $dll; Signature = $methodSignature; }
}

function Add-NativeMethods()
{
    $nativeMethodsCode = $script:nativeMethods | % { "
        [DllImport(`"$($_.Dll)`")]
        public static extern $($_.Signature);
    " }

    Add-Type @"
        using System;
        using System.Text;
        using System.Runtime.InteropServices;
        public class NativeMethods {
            $nativeMethodsCode
        }
"@
}

AddToStatus "SetupStart, User: $env:USERNAME"

. (Join-Path $PSScriptRoot "settings.ps1")

$ComputerInfo = Get-ComputerInfo
$WindowsInstallationType = $ComputerInfo.WindowsInstallationType
$WindowsProductName = $ComputerInfo.WindowsProductName
$nchBranch = "preview"

if ($nchBranch -eq "preview") {
    AddToStatus "Installing Latest BcContainerHelper preview from PowerShell Gallery"
    Install-Module -Name bccontainerhelper -Force -AllowPrerelease
    Import-Module -Name bccontainerhelper -DisableNameChecking
    AddToStatus ("Using BcContainerHelper version "+(get-module BcContainerHelper).Version.ToString())
}
elseif ($nchBranch -eq "") {
    AddToStatus "Installing Latest Business Central Container Helper from PowerShell Gallery"
    Install-Module -Name bccontainerhelper -Force
    Import-Module -Name bccontainerhelper -DisableNameChecking
    AddToStatus ("Using BcContainerHelper version "+(get-module BcContainerHelper).Version.ToString())
} else {
    if ($nchBranch -notlike "https://*") {
        $nchBranch = "https://github.com/Microsoft/navcontainerhelper/archive/$($nchBranch).zip"
    }
    AddToStatus "Using BcContainerHelper from $nchBranch"
    Download-File -sourceUrl $nchBranch -destinationFile "c:\demo\bccontainerhelper.zip"
    [Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.Filesystem") | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory("c:\demo\bccontainerhelper.zip", "c:\demo")
    $module = Get-Item -Path "C:\demo\*\BcContainerHelper.psm1"
    AddToStatus "Loading BcContainerHelper from $($module.FullName)"
    Import-Module $module.FullName -DisableNameChecking
}

if ($AddTraefik -eq "Yes") {

    if (Test-Path "c:\myfolder\certificate.pfx") {
        AddToStatus -color Red "Certificate specified, cannot add Traefik"
        $AddTraefik = "No"
    }

    if (-not $ContactEMailForLetsEncrypt) {
        AddToStatus -color Red "Contact EMail for LetsEncrypt not specified, cannot add Traefik"
        $AddTraefik = "No"
    }

    if ($clickonce -eq "Yes") {
        AddToStatus -color Red "ClickOnce specified, cannot add Traefik"
        $AddTraefik = "No"
    }

    if ($AddTraefik -eq "Yes") {
        Setup-TraefikContainerForNavContainers -overrideDefaultBinding -PublicDnsName $publicDnsName -ContactEMailForLetsEncrypt $ContactEMailForLetsEncrypt
    }
    else {
        Get-VariableDeclaration -name "AddTraefik" | Add-Content $settingsScript
    }
}

if ("$ContactEMailForLetsEncrypt" -ne "" -and $AddTraefik -ne "Yes") {
if (-not (Get-InstalledModule ACME-PS -ErrorAction SilentlyContinue)) {

    AddToStatus "Installing ACME-PS PowerShell Module"
    Install-Module -Name ACME-PS -RequiredVersion "1.1.0-beta" -AllowPrerelease -Force

    AddToStatus "Using Lets Encrypt certificate"
    # Use Lets encrypt
    # If rate limits are hit, log an error and revert to Self Signed
    try {
        $plainPfxPassword = [GUID]::NewGuid().ToString()
        $certificatePfxFilename = "c:\ProgramData\bccontainerhelper\certificate.pfx"
        New-LetsEncryptCertificate -ContactEMailForLetsEncrypt $ContactEMailForLetsEncrypt -publicDnsName $publicDnsName -CertificatePfxFilename $certificatePfxFilename -CertificatePfxPassword (ConvertTo-SecureString -String $plainPfxPassword -AsPlainText -Force)

        # Override SetupCertificate.ps1 in container
        ('if ([int](get-item "C:\Program Files\Microsoft Dynamics NAV\*").Name -le 100) {
    Write-Host "WARNING: This version doesn''t support LetsEncrypt certificates, reverting to self-signed"
    . "C:\run\SetupCertificate.ps1"
}
else {
    . (Join-Path $PSScriptRoot "InstallCertificate.ps1")
}
') | Set-Content "c:\myfolder\SetupCertificate.ps1"


        ('$CertificatePfxPassword = ConvertTo-SecureString -String "'+$plainPfxPassword+'" -AsPlainText -Force
$certificatePfxFile = "'+$certificatePfxFilename+'"
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certificatePfxFile, $certificatePfxPassword)
$certificateThumbprint = $cert.Thumbprint
Write-Host "Certificate File Thumbprint $certificateThumbprint"
if (!(Get-Item Cert:\LocalMachine\my\$certificateThumbprint -ErrorAction SilentlyContinue)) {
    Write-Host "Import Certificate to LocalMachine\my"
    Import-PfxCertificate -FilePath $certificatePfxFile -CertStoreLocation cert:\localMachine\my -Password $certificatePfxPassword | Out-Null
}
$dnsidentity = $cert.GetNameInfo("SimpleName",$false)
if ($dnsidentity.StartsWith("*")) {
    $dnsidentity = $dnsidentity.Substring($dnsidentity.IndexOf(".")+1)
}
') | Set-Content "c:\myfolder\InstallCertificate.ps1"

        # Create RenewCertificate script
        ('$CertificatePfxPassword = ConvertTo-SecureString -String "'+$plainPfxPassword+'" -AsPlainText -Force
$certificatePfxFile = "'+$certificatePfxFilename+'"
$publicDnsName = "'+$publicDnsName+'"
Renew-LetsEncryptCertificate -publicDnsName $publicDnsName -certificatePfxFilename $certificatePfxFile -certificatePfxPassword $certificatePfxPassword
Start-Sleep -seconds 30
Restart-NavContainer -containerName navserver -renewBindings
') | Set-Content "c:\demo\RenewCertificate.ps1"

    } catch {
        AddToStatus -color Red $_.Exception.Message
        AddToStatus -color Red "Reverting to Self Signed Certificate"
    }

}
}

if (-not (Get-InstalledModule Az -ErrorAction SilentlyContinue)) {
    AddToStatus "Installing Az module"
    Install-Module Az -Force
}

if (-not (Get-InstalledModule AzureAD -ErrorAction SilentlyContinue)) {
    AddToStatus "Installing AzureAD module"
    Install-Module AzureAD -Force
}

if (-not (Get-InstalledModule SqlServer -ErrorAction SilentlyContinue)) {
    AddToStatus "Installing SqlServer module"
    Install-Module SqlServer -Force
}

$securePassword = ConvertTo-SecureString -String $adminPassword -Key $passwordKey
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword))

if ($requestToken) {
    if (!(Get-ScheduledTask -TaskName request -ErrorAction Ignore)) {
        AddToStatus "Registering request task"
        $xml = [System.IO.File]::ReadAllText("c:\demo\RequestTaskDef.xml")
        Register-ScheduledTask -TaskName request -User $vmadminUsername -Password $plainPassword -Xml $xml
    }
}

if ("$createStorageQueue" -eq "yes") {
    if (-not (Get-InstalledModule AzTable -ErrorAction SilentlyContinue)) {
        AddToStatus "Installing AzTable Module"
        Install-Module AzTable -Force
    
        $taskName = "RunQueue"
        $startupAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy UnRestricted -File c:\demo\RunQueue.ps1"
        $startupTrigger = New-ScheduledTaskTrigger -AtStartup
        $startupTrigger.Delay = "PT5M"
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd
        $task = Register-ScheduledTask -TaskName $taskName `
                               -Action $startupAction `
                               -Trigger $startupTrigger `
                               -Settings $settings `
                               -RunLevel Highest `
                               -User $vmAdminUsername `
                               -Password $plainPassword
        
        $task.Triggers.Repetition.Interval = "PT5M"
        $task | Set-ScheduledTask -User $vmAdminUsername -Password $plainPassword | Out-Null
    
        Start-ScheduledTask -TaskName $taskName
    }
}

$taskName = "RestartContainers"
if (-not (Get-ScheduledTask -TaskName $taskName -ErrorAction Ignore)) {
    AddToStatus "Register RestartContainers Task to start container delayed"
    $startupAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy UnRestricted -file c:\demo\restartcontainers.ps1"
    $startupTrigger = New-ScheduledTaskTrigger -AtStartup
    $startupTrigger.Delay = "PT5M"
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd
    $task = Register-ScheduledTask -TaskName $taskName `
                           -Action $startupAction `
                           -Trigger $startupTrigger `
                           -Settings $settings `
                           -RunLevel Highest `
                           -User $vmadminUsername `
                           -Password $plainPassword
}

if ($WindowsInstallationType -eq "Server") {

    if (Get-ScheduledTask -TaskName SetupVm -ErrorAction Ignore) {
        schtasks /DELETE /TN SetupVm /F | Out-Null
    }

    AddToStatus "Launch SetupVm"
    $onceAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy UnRestricted -File c:\demo\setupVm.ps1"
    Register-ScheduledTask -TaskName SetupVm `
                           -Action $onceAction `
                           -RunLevel Highest `
                           -User $vmAdminUsername `
                           -Password $plainPassword | Out-Null
    
    Start-ScheduledTask -TaskName SetupVm
}
else {
    
    if (Get-ScheduledTask -TaskName SetupStart -ErrorAction Ignore) {
        schtasks /DELETE /TN SetupStart /F | Out-Null
    }
    
    $startupAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy UnRestricted -File c:\demo\SetupVm.ps1"
    $startupTrigger = New-ScheduledTaskTrigger -AtStartup
    $startupTrigger.Delay = "PT1M"
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd -WakeToRun
    Register-ScheduledTask -TaskName "SetupVm" `
                           -Action $startupAction `
                           -Trigger $startupTrigger `
                           -Settings $settings `
                           -RunLevel "Highest" `
                           -User $vmAdminUsername `
                           -Password $plainPassword | Out-Null
    
    AddToStatus -color Yellow "Restarting computer. After restart, please Login to computer using RDP in order to resume the installation process. This is not needed for Windows Server."
    
    Shutdown -r -t 60

}
