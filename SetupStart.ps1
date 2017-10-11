function Log([string]$line, [string]$color = "Gray") {
    ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt"
}

. (Join-Path $PSScriptRoot "settings.ps1")

Log "Launching SetupVm"

if (Get-ScheduledTask -TaskName setupStart -ErrorAction Ignore) {
    schtasks /DELETE /TN setupStart /F | Out-Null
}

$onceAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "c:\demo\setupVm.ps1"
Register-ScheduledTask -TaskName SetupVm `
                       -Action $onceAction `
                       -RunLevel Highest `
                       -User $vmAdminUsername `
                       -Password $adminPassword | Out-Null
Start-ScheduledTask -TaskName SetupVm
