function Log([string]$line) {
    ([DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line") | Add-Content -Path "c:\agent\status.txt"
}

Log "SetupDockerAgentStart, User: $env:USERNAME"

. (Join-Path $PSScriptRoot "settings.ps1")

if (!(Get-Package -Name AzureRM.Storage -ErrorAction Ignore)) {
    Log "Installing AzureRM.Storage PowerShell package"
    Install-Package AzureRM.Storage -Force -WarningAction Ignore | Out-Null
}

if (!(Get-Package -Name AzureRmStorageTable -ErrorAction Ignore)) {
    Log "Installing AzureRmStorageTable PowerShell package"
    Install-Package AzureRmStorageTable -Force -WarningAction Ignore | Out-Null
}

$securePassword = ConvertTo-SecureString -String $adminPassword -Key $passwordKey
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword))

Log "Launch SetupDockerAgentVm"
$onceAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy UnRestricted -File c:\agent\setupDockerAgentVm.ps1"
Register-ScheduledTask -TaskName "SetupVm" `
                       -Action $onceAction `
                       -RunLevel Highest `
                       -User $vmAdminUsername `
                       -Password $plainPassword | Out-Null

Start-ScheduledTask -TaskName SetupVm
