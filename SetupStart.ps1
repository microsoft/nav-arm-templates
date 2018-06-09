﻿if (Get-ScheduledTask -TaskName setupStart -ErrorAction Ignore) {
    schtasks /DELETE /TN setupStart /F | Out-Null
}

function Log([string]$line, [string]$color = "Gray") {
    ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt"
}

. (Join-Path $PSScriptRoot "settings.ps1")

Log "Starting docker"
start-service docker

Log "Launching SetupVm"
$securePassword = ConvertTo-SecureString -String $adminPassword -Key $passwordKey
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword))
$onceAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "c:\demo\setupVm.ps1"
Register-ScheduledTask -TaskName SetupVm `
                       -Action $onceAction `
                       -RunLevel Highest `
                       -User $vmAdminUsername `
                       -Password $plainPassword | Out-Null

Start-ScheduledTask -TaskName SetupVm

if (!(Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction Ignore)) {
    Log "Installing NuGet Package Provider"
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -WarningAction Ignore | Out-Null
}

if (!(Get-Package -Name AzureRM.ApiManagement -ErrorAction Ignore)) {
    Log "Installing AzureRM.ApiManagement PowerShell package"
    Install-Package AzureRM.ApiManagement -Force -WarningAction Ignore | Out-Null
}

if (!(Get-Package -Name AzureRM.Resources -ErrorAction Ignore)) {
    Log "Installing AzureRM.Resources PowerShell package"
    Install-Package AzureRM.Resources -Force -WarningAction Ignore | Out-Null
}

