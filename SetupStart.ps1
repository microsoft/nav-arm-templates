function Log([string]$line, [string]$color = "Gray") {
    ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt"
}

. (Join-Path $PSScriptRoot "settings.ps1")

if ($WindowsInstallationType -eq "Server") {
    if (Get-ScheduledTask -TaskName setupStart -ErrorAction Ignore) {
        schtasks /DELETE /TN setupStart /F | Out-Null
    }
    Log "Starting docker"
    start-service docker
} else {
    if (!(Test-Path -Path "C:\Program Files\Docker\Docker\Docker for Windows.exe" -PathType Leaf)) {
        Log "Install Docker"
        $dockerexe = "C:\DOWNLOAD\DockerInstall.exe"
        (New-Object System.Net.WebClient).DownloadFile("https://download.docker.com/win/stable/Docker%20for%20Windows%20Installer.exe", $dockerexe)
        Start-Process -FilePath $dockerexe -ArgumentList "install --quiet" -Wait
        Log "Restarting computer and start Docker"
        Restart-Computer -Force
    } else {
        if (Get-ScheduledTask -TaskName setupStart -ErrorAction Ignore) {
            schtasks /DELETE /TN setupStart /F | Out-Null
        }
        Log "Waiting for docker to start... (this should only take a few minutes)"
        $serverOsStr = "  OS/Arch:      "
        do {
            Start-Sleep -Seconds 10
            $dockerver = docker version
        } while ($LASTEXITCODE -ne 0)
        $serverOs = ($dockerver | where-Object { $_.startsWith($serverOsStr) }).SubString($serverOsStr.Length)
        if (!$serverOs.startsWith("windows")) {
            Log "Switching to Windows Containers"
            & "c:\program files\docker\docker\dockercli" -SwitchDaemon
        }
    }
}

Log "Enabling Docker API"
New-item -Path "C:\ProgramData\docker\config" -ItemType Directory -Force -ErrorAction Ignore | Out-Null
'{
    "hosts": ["tcp://0.0.0.0:2375", "npipe://"]
}' | Set-Content "C:\ProgramData\docker\config\daemon.json"
netsh advfirewall firewall add rule name="Docker" dir=in action=allow protocol=TCP localport=2375

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

Log "Launching SetupVm"
$securePassword = ConvertTo-SecureString -String $adminPassword -Key $passwordKey
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword))
$onceAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-executionpolicy unrestricted -file c:\demo\setupVm.ps1"
Register-ScheduledTask -TaskName SetupVm `
                       -Action $onceAction `
                       -RunLevel Highest `
                       -User $vmAdminUsername `
                       -Password $plainPassword | Out-Null

Start-ScheduledTask -TaskName SetupVm

