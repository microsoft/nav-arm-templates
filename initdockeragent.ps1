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
    [string] $vmname,
    [string] $registry1 = "",
    [string] $registry1username = "",
    [string] $registry1password = "",
    [string] $registry2 = "",
    [string] $registry2username = "",
    [string] $registry2password = "",
    [string] $registry3 = "",
    [string] $registry3username = "",
    [string] $registry3password = ""
)

function Download-File([string]$sourceUrl, [string]$destinationFile)
{
    Log "Downloading $destinationFile"
    Remove-Item -Path $destinationFile -Force -ErrorAction Ignore
    (New-Object System.Net.WebClient).DownloadFile($sourceUrl, $destinationFile)
}

function Login-Docker([string]$registry, [string]$registryUsername, [string]$registryPassword)
{
    if ("$registryUsername" -ne "" -and "$registryPassword" -ne "") {
        docker login "$registry" -u "$registryUsername" -p "$registryPassword"
    }
}

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls -bor [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls12

Set-ExecutionPolicy -ExecutionPolicy unrestricted -Force

Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 | Out-Null
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 | Out-Null

if (!(Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction Ignore)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.208 -Force -WarningAction Ignore | Out-Null
}

# Install Docker
Install-module DockerMsftProvider -Force
Install-Package -Name docker -ProviderName DockerMsftProvider -Force

Start-Service docker

Login-Docker -registry "$registry1" -registryUsername "$registry1username" -registryPassword "$registry1password"
Login-Docker -registry "$registry2" -registryUsername "$registry2username" -registryPassword "$registry2password"
Login-Docker -registry "$registry3" -registryUsername "$registry3username" -registryPassword "$registry3password"

Restart-Computer -force

