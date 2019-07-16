#usage initdockeragent.ps1
param
(
    [string] $templateLink              = "https://raw.githubusercontent.com/Microsoft/nav-arm-templates/master/dockeragent.json",
    [Parameter(Mandatory=$true)]
    [string] $vmAdminUsername,
    [Parameter(Mandatory=$true)]
    [string] $adminPassword,
    [Parameter(Mandatory=$true)]
    [string] $StorageAccountName,
    [Parameter(Mandatory=$true)]
    [string] $StorageAccountKey,
    [Parameter(Mandatory=$true)]
    [string] $Queue,
    [Parameter(Mandatory=$true)]
    [string] $Processes,
    [Parameter(Mandatory=$true)]
    [string] $vmname,
    [string] $registry1 = "",
    [string] $registry1username = "",
    [string] $registry1password = "",
    [string] $registry2 = "",
    [string] $registry2username = "",
    [string] $registry2password = "",
    [string] $registry3 = "",
    [string] $registry3username = "",
    [string] $registry3password = "",
    [string] $registry4 = "",
    [string] $registry4username = "",
    [string] $registry4password = ""
)

function Get-VariableDeclaration([string]$name) {
    $var = Get-Variable -Name $name
    if ($var) {
        ('$'+$var.Name+' = "'+$var.Value+'"')
    } else {
        ""
    }
}

function Log([string]$line) {
    ([DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line") | Add-Content -Path "c:\agent\status.txt"
}

function Download-File([string]$sourceUrl, [string]$destinationFile)
{
    Log "Downloading $destinationFile"
    Remove-Item -Path $destinationFile -Force -ErrorAction Ignore
    (New-Object System.Net.WebClient).DownloadFile($sourceUrl, $destinationFile)
}

$settingsScript = "c:\agent\settings.ps1"
if (Test-Path $settingsScript) {
    . "$settingsScript"
} else {
    New-Item -Path "c:\agent" -ItemType Directory -ErrorAction Ignore | Out-Null
    
    Get-VariableDeclaration -name "templateLink"           | Set-Content $settingsScript
    Get-VariableDeclaration -name "vmAdminUsername"        | Add-Content $settingsScript
    Get-VariableDeclaration -name "vmName"                 | Add-Content $settingsScript
    Get-VariableDeclaration -name "StorageAccountName"     | Add-Content $settingsScript
    Get-VariableDeclaration -name "Queue"                  | Add-Content $settingsScript
    Get-VariableDeclaration -name "Processes"              | Add-Content $settingsScript
    Get-VariableDeclaration -name "registry1"              | Add-Content $settingsScript
    Get-VariableDeclaration -name "registry1username"      | Add-Content $settingsScript
    Get-VariableDeclaration -name "registry2"              | Add-Content $settingsScript
    Get-VariableDeclaration -name "registry2username"      | Add-Content $settingsScript
    Get-VariableDeclaration -name "registry3"              | Add-Content $settingsScript
    Get-VariableDeclaration -name "registry3username"      | Add-Content $settingsScript
    Get-VariableDeclaration -name "registry4"              | Add-Content $settingsScript
    Get-VariableDeclaration -name "registry4username"      | Add-Content $settingsScript

    $passwordKey = New-Object Byte[] 16
    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($passwordKey)
    ('$passwordKey = [byte[]]@('+"$passwordKey".Replace(" ",",")+')') | Add-Content $settingsScript

    'adminPassword','StorageAccountKey','registry1password','registry2password','registry3password','registry4password' | % {
        $var = Get-Variable -Name $_
        $securePassword = ConvertTo-SecureString -String $var.Value -AsPlainText -Force
        $encPassword = ConvertFrom-SecureString -SecureString $securePassword -Key $passwordKey
        ('$' + $_ + ' = "'+$encPassword+'"') | Add-Content $settingsScript
    }

}

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls -bor [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls12

Set-ExecutionPolicy -ExecutionPolicy unrestricted -Force

Log "TemplateLink: $templateLink"
$scriptPath = $templateLink.SubString(0,$templateLink.LastIndexOf('/')+1)

$CurrentSize = (get-partition -DriveLetter C).Size
$AvailableSize = (Get-PartitionSupportedSize -DriveLetter C).SizeMax
if ($CurrentSize -ne $AvailableSize) {
    Log "Resizing C drive from $currentSize to $AvailableSize"
    Resize-Partition -DriveLetter C -Size $AvailableSize
}

Log "Turning off IE Enhanced Security Configuration"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 | Out-Null
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 | Out-Null

$startDockerAgentScript = "c:\agent\StartDockerAgent.ps1"
$setupDockerAgentStartScript = "c:\agent\SetupDockerAgentStart.ps1"
$setupDockerAgentVMScript = "c:\agent\SetupDockerAgentVM.ps1"
Download-File -sourceUrl "${scriptPath}StartDockerAgent.ps1" -destinationFile $startDockerAgentScript
Download-File -sourceUrl "${scriptPath}SetupDockerAgentStart.ps1" -destinationFile $setupDockerAgentStartScript
Download-File -sourceUrl "${scriptPath}SetupDockerAgentVM.ps1" -destinationFile $setupDockerAgentVMScript

if (!(Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction Ignore)) {
    Log "Installing NuGet Package Provider"
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.208 -Force -WarningAction Ignore | Out-Null
}

Log "Install Docker"
Install-module DockerMsftProvider -Force
Install-Package -Name docker -ProviderName DockerMsftProvider -Force

Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart

$startupAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy UnRestricted -File ""$setupDockerAgentStartScript"""
$startupTrigger = New-ScheduledTaskTrigger -AtStartup
$startupTrigger.Delay = "PT1M"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd
Register-ScheduledTask -TaskName "SetupStart" `
                       -Action $startupAction `
                       -Trigger $startupTrigger `
                       -Settings $settings `
                       -RunLevel "Highest" `
                       -User "NT AUTHORITY\SYSTEM" | Out-Null

Log "Restarting computer and start Installation tasks"
Shutdown -r -t 60
