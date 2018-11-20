function Log([string]$line, [string]$color = "Gray") {
    ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt"
}

Log "SetupStart, User: $env:USERNAME"

. (Join-Path $PSScriptRoot "settings.ps1")

if (!(Get-Package -Name AzureRM.ApiManagement -ErrorAction Ignore)) {
    Log "Installing AzureRM.ApiManagement PowerShell package"
    Install-Package AzureRM.ApiManagement -Force -WarningAction Ignore | Out-Null
}

if (!(Get-Package -Name AzureRM.Resources -ErrorAction Ignore)) {
    Log "Installing AzureRM.Resources PowerShell package"
    Install-Package AzureRM.Resources -Force -WarningAction Ignore | Out-Null
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

Log "Launch SetupVm"
$onceAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy UnRestricted -File c:\demo\setupVm.ps1"
Register-ScheduledTask -TaskName SetupVm `
                       -Action $onceAction `
                       -RunLevel Highest `
                       -User $vmAdminUsername `
                       -Password $plainPassword | Out-Null

Start-ScheduledTask -TaskName SetupVm
