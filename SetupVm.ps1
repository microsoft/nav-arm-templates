function Log([string]$line, [string]$color = "Gray") {
    ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt" 
}

Import-Module (Join-Path $PSScriptRoot "NavContainerHelper.psm1") -DisableNameChecking

. (Join-Path $PSScriptRoot "settings.ps1")

Log "Enabling File Download in IE"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3" -Name "1803" -Value 0
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3" -Name "1803" -Value 0

Log "Enabling Font Download in IE"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3" -Name "1604" -Value 0
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3" -Name "1604" -Value 0

Log "Disabling Server Manager Open At Logon"
New-ItemProperty -Path "HKCU:\Software\Microsoft\ServerManager" -Name "DoNotOpenServerManagerAtLogon" -PropertyType "DWORD" -Value "0x1" –Force | Out-Null

Log "Adding Landing Page to Startup Group"
New-DesktopShortcut -Name "Landing Page" -TargetPath "C:\Program Files\Internet Explorer\iexplore.exe" -FolderName "Startup" -Arguments "http://$publicDnsName"

$navDockerImage.Split(',') | % {
    $registry = $_.Split('/')[0]
    if (($registryUsername -ne "") -and ($registryPassword -ne "")) {
        Log "Logging in to $registry"
        docker login "$registry" -u "$registryUsername" -p "$registryPassword"
    }
    Log "Pulling $_ (this might take a while)"
    docker pull "$_"
}

. "c:\demo\SetupNavContainer.ps1"
. "c:\demo\SetupDesktop.ps1"

if (Get-ScheduledTask -TaskName SetupVm -ErrorAction Ignore) {
    schtasks /DELETE /TN SetupVm /F | Out-Null
}
