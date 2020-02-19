function Log([string]$line, [string]$color = "Gray") {
    ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt"
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
        using System.Runtime.InteropServices;
        public class NativeMethods {
            $nativeMethodsCode
        }
"@
}

Log "SetupStart, User: $env:USERNAME"

. (Join-Path $PSScriptRoot "settings.ps1")

$ComputerInfo = Get-ComputerInfo
$WindowsInstallationType = $ComputerInfo.WindowsInstallationType
$WindowsProductName = $ComputerInfo.WindowsProductName


if (Test-Path -Path "C:\demo\navcontainerhelper-dev\NavContainerHelper.psm1") {
    Import-module "C:\demo\navcontainerhelper-dev\NavContainerHelper.psm1" -DisableNameChecking
} else {
    Import-Module -name navcontainerhelper -DisableNameChecking
}

if ("$ContactEMailForLetsEncrypt" -ne "" -and $AddTraefik -ne "Yes") {
if (-not (Get-InstalledModule ACME-PS -ErrorAction SilentlyContinue)) {

    Log "Installing ACME-PS PowerShell Module"
    Install-Module -Name ACME-PS -RequiredVersion "1.1.0-beta" -AllowPrerelease -Force

    Log "Using Lets Encrypt certificate"
    # Use Lets encrypt
    # If rate limits are hit, log an error and revert to Self Signed
    try {
        $plainPfxPassword = [GUID]::NewGuid().ToString()
        $certificatePfxFilename = "c:\ProgramData\navcontainerhelper\certificate.pfx"
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
        Log -color Red $_.Exception.Message
        Log -color Red "Reverting to Self Signed Certificate"
    }

}
}

if (-not (Get-InstalledModule Az -ErrorAction SilentlyContinue)) {
    Log "Installing Az module"
    Install-Module Az -Force
}

if (-not (Get-InstalledModule AzureAD -ErrorAction SilentlyContinue)) {
    Log "Installing AzureAD module"
    Install-Module AzureAD -Force
}

if (-not (Get-InstalledModule SqlServer -ErrorAction SilentlyContinue)) {
    Log "Installing SqlServer module"
    Install-Module SqlServer -Force
}

$securePassword = ConvertTo-SecureString -String $adminPassword -Key $passwordKey
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword))

if ($WindowsInstallationType -ne "Server") {
    if (-not (Test-Path "c:\users\$vmAdminUsername")) {   

        $script:nativeMethods = @()
        
        Register-NativeMethod "userenv.dll" "int CreateProfile([MarshalAs(UnmanagedType.LPWStr)] string pszUserSid,[MarshalAs(UnmanagedType.LPWStr)] string pszUserName,[Out][MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszProfilePath, uint cchProfilePath)"
        Add-NativeMethods
        
        $localUser = New-Object System.Security.Principal.NTAccount($vmAdminUsername)
        $userSID = $localUser.Translate([System.Security.Principal.SecurityIdentifier])
        $sb = new-object System.Text.StringBuilder(260)
        $pathLen = $sb.Capacity
        
        Log "Creating user profile for $vmAdminUsername"
        try
        {
            [NativeMethods]::CreateProfile($userSID.Value, $Username, $sb, $pathLen) | Out-Null
        }
        catch
        {
            Log $_.Exception.Message
        }
    }
}

if ($requestToken) {
    if (!(Get-ScheduledTask -TaskName request -ErrorAction Ignore)) {
        Log "Registering request task"
        $xml = [System.IO.File]::ReadAllText("c:\demo\RequestTaskDef.xml")
        Register-ScheduledTask -TaskName request -User $vmadminUsername -Password $plainPassword -Xml $xml
    }
}

if ("$createStorageQueue" -eq "yes") {
    if (-not (Get-InstalledModule AzTable -ErrorAction SilentlyContinue)) {
        Log "Installing AzTable Module"
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

Log "Register RestartContainers Task to start container delayed"
$taskName = "RestartContainers"
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

Log "Launch SetupVm"
$onceAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy UnRestricted -File c:\demo\setupVm.ps1"
Register-ScheduledTask -TaskName SetupVm `
                       -Action $onceAction `
                       -RunLevel Highest `
                       -User $vmAdminUsername `
                       -Password $plainPassword | Out-Null

Start-ScheduledTask -TaskName SetupVm
