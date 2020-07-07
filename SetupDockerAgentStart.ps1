function AddToStatus([string]$line) {
    ([DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line") | Add-Content -Path "c:\agent\status.txt" -Force -ErrorAction SilentlyContinue
}

AddToStatus "SetupDockerAgentStart, User: $env:USERNAME"

. (Join-Path $PSScriptRoot "settings.ps1")

if (!(Get-Package -Name AzureRM -ErrorAction Ignore)) {
    AddToStatus "Installing AzureRM PowerShell package"
    Install-Package AzureRM -Force -WarningAction Ignore  -RequiredVersion 6.13.1 | Out-Null
}

if (!(Get-Package -Name AzureRmStorageTable -ErrorAction Ignore)) {
    AddToStatus "Installing AzureRmStorageTable PowerShell package"
    Install-Package AzureRmStorageTable -Force -WarningAction Ignore  -RequiredVersion 1.0.0.23 | Out-Null
}

$securePassword = ConvertTo-SecureString -String $adminPassword -Key $passwordKey
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword))

AddToStatus "Launch SetupDockerAgentVm"
$onceAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy UnRestricted -File c:\agent\setupDockerAgentVm.ps1"
Register-ScheduledTask -TaskName "SetupVm" `
                       -Action $onceAction `
                       -RunLevel Highest `
                       -User $vmAdminUsername `
                       -Password $plainPassword | Out-Null

Start-ScheduledTask -TaskName SetupVm
