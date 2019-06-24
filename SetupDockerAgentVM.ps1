$ErrorActionPreference = "Stop"
$WarningActionPreference = "Continue"

$ComputerInfo = Get-ComputerInfo
$WindowsInstallationType = $ComputerInfo.WindowsInstallationType
$WindowsProductName = $ComputerInfo.WindowsProductName

try {

if (Get-ScheduledTask -TaskName SetupVm -ErrorAction Ignore) {
    schtasks /DELETE /TN SetupVm /F | Out-Null
}

function Log([string]$line) {
    ([DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line") | Add-Content -Path "c:\agent\status.txt"
}

function Login-Docker([string]$registry, [string]$registryUsername, [string]$registryPassword)
{
    if ("$registryUsername" -ne "" -and "$registryPassword" -ne "") {
        $securePassword = ConvertTo-SecureString -String $registryPassword -Key $passwordKey
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword))
        Log "Login to '$registry' with $registryUsername"
        docker login "$registry" -u "$registryUsername" -p "$plainPassword"
    }
}

Log "SetupDockerAgentVm, User: $env:USERNAME"

. (Join-Path $PSScriptRoot "settings.ps1")

Log "Starting docker"
start-service docker

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls -bor [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls12

Log "Enabling File Download in IE"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3" -Name "1803" -Value 0
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3" -Name "1803" -Value 0

Log "Enabling Font Download in IE"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3" -Name "1604" -Value 0
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3" -Name "1604" -Value 0

Log "Show hidden files and file types"
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'  -Name "Hidden"      -value 1
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'  -Name "HideFileExt" -value 0

Log "Disabling Server Manager Open At Logon"
New-ItemProperty -Path "HKCU:\Software\Microsoft\ServerManager" -Name "DoNotOpenServerManagerAtLogon" -PropertyType "DWORD" -Value "0x1" –Force | Out-Null

Login-Docker -registry "$registry1" -registryUsername "$registry1username" -registryPassword "$registry1password"
Login-Docker -registry "$registry2" -registryUsername "$registry2username" -registryPassword "$registry2password"
Login-Docker -registry "$registry3" -registryUsername "$registry3username" -registryPassword "$registry3password"
Login-Docker -registry "$registry4" -registryUsername "$registry4username" -registryPassword "$registry4password"

if (Get-ScheduledTask -TaskName SetupStart -ErrorAction Ignore) {
    schtasks /DELETE /TN SetupStart /F | Out-Null
}

$securePassword = ConvertTo-SecureString -String $adminPassword -Key $passwordKey
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword))

$vmno = [int]$vmName.Substring($vmName.LastIndexOf('-')+1)

Log "Register Build Agents"
1..$Processes | % {
    $agentNo = $vmno*$processes+$_
    $taskName = "$queue-$agentNo"
    $startupAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy UnRestricted -File c:\agent\StartDockerAgent.ps1 $taskName"
    $startupTrigger = New-ScheduledTaskTrigger -AtStartup
    $delay = (5+$_)
    $startupTrigger.Delay = "PT${delay}M"
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
}

Log "Complete, and start tasks"

shutdown -r -t 30

} catch {
    Log $_.Exception.Message
    $_.ScriptStackTrace.Replace("`r`n","`n").Split("`n") | % { Log $_ }
    throw
}
