$ErrorActionPreference = "Stop"
$WarningActionPreference = "Stop"
try {

if (Get-ScheduledTask -TaskName SetupVm -ErrorAction Ignore) {
    Remove-item -Path (Join-Path $PSScriptRoot "setupStart.ps1") -Force -ErrorAction Ignore
    schtasks /DELETE /TN SetupVm /F | Out-Null
}

function Log([string]$line, [string]$color = "Gray") {
    ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt" 
}

function DockerDo {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$imageName,
        [ValidateSet('run','start','pull')]
        [string]$command = "run",
        [switch]$accept_eula,
        [switch]$accept_outdated,
        [switch]$detach,
        [string[]]$parameters = @()
    )

    if ($accept_eula) {
        $parameters += "--env accept_eula=Y"
    }
    if ($accept_outdated) {
        $parameters += "--env accept_outdated=Y"
    }
    if ($detach) {
        $parameters += "--detach"
    }
    $arguments = ("$command "+[string]::Join(" ", $parameters)+" $imageName")

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "docker.exe"
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = $arguments
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $p.WaitForExit()
    $output = $p.StandardOutput.ReadToEnd()
    $output += $p.StandardError.ReadToEnd()
    if ($p.ExitCode -eq 0) {
        return $true
    } else {
        Log -color red $output
        Log -color red "Commandline: docker $arguments"
        return $false
    }
}

Import-Module -name navcontainerhelper -DisableNameChecking

. (Join-Path $PSScriptRoot "settings.ps1")

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls -bor [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls12

Log "Enabling File Download in IE"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3" -Name "1803" -Value 0
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3" -Name "1803" -Value 0

Log "Enabling Font Download in IE"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3" -Name "1604" -Value 0
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3" -Name "1604" -Value 0

Log "Disabling Server Manager Open At Logon"
New-ItemProperty -Path "HKCU:\Software\Microsoft\ServerManager" -Name "DoNotOpenServerManagerAtLogon" -PropertyType "DWORD" -Value "0x1" –Force | Out-Null

Log "Add Import navcontainerhelper to PowerShell profile"
$winPsFolder = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "WindowsPowerShell"
New-Item $winPsFolder -ItemType Directory -Force -ErrorAction Ignore | Out-Null
"Import-Module navcontainerhelper -DisableNameChecking" | Set-Content (Join-Path $winPsFolder "Profile.ps1")

Log "Adding Landing Page to Startup Group"
New-DesktopShortcut -Name "Landing Page" -TargetPath "C:\Program Files\Internet Explorer\iexplore.exe" -Shortcuts "Startup" -Arguments "http://$publicDnsName"
if ($style -eq "devpreview") {
    New-DesktopShortcut -Name "Modern Dev Tools" -TargetPath "C:\Program Files\Internet Explorer\iexplore.exe" -Shortcuts "Startup" -Arguments "http://aka.ms/moderndevtools"
}

$navDockerImage.Split(',') | % {
    $registry = $_.Split('/')[0]
    if (($registry -ne "microsoft") -and ($registryUsername -ne "") -and ($registryPassword -ne "")) {
        Log "Logging in to $registry"
        docker login "$registry" -u "$registryUsername" -p "$registryPassword"
    }
    $imageName = $_
    Log "Pulling $imageName (this might take ~30 minutes)"
    DockerDo -imageName $imageName -command pull
}

Log "Installing Visual C++ Redist"
$vcRedistUrl = "https://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x86.exe"
$vcRedistFile = "C:\DOWNLOAD\vcredist_x86.exe"
Download-File -sourceUrl $vcRedistUrl -destinationFile $vcRedistFile
Start-Process $vcRedistFile -argumentList "/q" -wait

Log "Installing SQL Native Client"
$sqlncliUrl = "https://download.microsoft.com/download/3/A/6/3A632674-A016-4E31-A675-94BE390EA739/ENU/x64/sqlncli.msi"
$sqlncliFile = "C:\DOWNLOAD\sqlncli.msi"
Download-File -sourceUrl $sqlncliUrl -destinationFile $sqlncliFile
Start-Process "C:\Windows\System32\msiexec.exe" -argumentList "/i $sqlncliFile ADDLOCAL=ALL IACCEPTSQLNCLILICENSETERMS=YES /qn" -wait

Log "Installing OpenXML 2.5"
$openXmlUrl = "https://download.microsoft.com/download/5/5/3/553C731E-9333-40FB-ADE3-E02DC9643B31/OpenXMLSDKV25.msi"
$openXmlFile = "C:\DOWNLOAD\OpenXMLSDKV25.msi"
Download-File -sourceUrl $openXmlUrl -destinationFile $openXmlFile
Start-Process $openXmlFile -argumentList "/qn /q /passive" -wait

. "c:\demo\SetupNavContainer.ps1"
. "c:\demo\SetupDesktop.ps1"

$finalSetupScript = (Join-Path $PSScriptRoot "FinalSetupScript.ps1")
if (Test-Path $finalSetupScript) {
    Log "Running FinalSetupScript"
    . $finalSetupScript
}

if ($RunWindowsUpdate -eq "Yes") {
    Log "Installing Windows Updates"
    install-module PSWindowsUpdate -force
    Get-WUInstall -install -acceptall -autoreboot | % { Log ($_.Status + " " + $_.KB + " " +$_.Title) }
    Log "Windows updates installed"
}

} catch {
    Log -Color Red -line $_.Exception.Message
    throw
}
