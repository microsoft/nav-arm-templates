function Log([string]$line, [string]$color = "Gray") {
    ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt"
}

Log "SetupStart, User: $env:USERNAME"

. (Join-Path $PSScriptRoot "settings.ps1")

if (!(Get-Package -Name AzureRM -ErrorAction Ignore)) {
    Log "Installing AzureRM PowerShell package"
    Install-Package AzureRM -Force -WarningAction Ignore  -RequiredVersion 6.13.1 | Out-Null
}

if (!(Get-Package -Name AzureAD -ErrorAction Ignore)) {
    Log "Installing AzureAD PowerShell package"
    Install-Package AzureAD -Force -WarningAction Ignore | Out-Null
}

$securePassword = ConvertTo-SecureString -String $adminPassword -Key $passwordKey
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword))

if ($requestToken) {
    if (!(Get-ScheduledTask -TaskName request -ErrorAction Ignore)) {
        Log "Registering request task"
        $xml = [System.IO.File]::ReadAllText("c:\demo\RequestTaskDef.xml")
        Register-ScheduledTask -TaskName request -User $vmadminUsername -Password $plainPassword -Xml $xml
    }
}

if ("$createStorageQueue" -eq "yes") {
    if (!(Get-Package -Name AzureRmStorageTable -ErrorAction Ignore)) {
        Log "Installing AzureRmStorageTable PowerShell package"
        Install-Package AzureRmStorageTable -Force -WarningAction Ignore  -RequiredVersion 1.0.0.23 | Out-Null
    }

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


Log "Launch SetupVm"
$onceAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy UnRestricted -File c:\demo\setupVm.ps1"
Register-ScheduledTask -TaskName SetupVm `
                       -Action $onceAction `
                       -RunLevel Highest `
                       -User $vmAdminUsername `
                       -Password $plainPassword | Out-Null

Start-ScheduledTask -TaskName SetupVm
