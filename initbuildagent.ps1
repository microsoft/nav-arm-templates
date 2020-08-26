#usage initbuildagent.ps1
param
(
    [string] $templateLink              = "https://raw.githubusercontent.com/Microsoft/nav-arm-templates/master/buildagent.json",
    [Parameter(Mandatory=$true)]
    [string] $vmAdminUsername,
    [Parameter(Mandatory=$true)]
    [string] $adminPassword,
    [Parameter(Mandatory=$true)]
    [string] $devopsorganization,
    [Parameter(Mandatory=$true)]
    [string] $personalaccesstoken,
    [Parameter(Mandatory=$true)]
    [string] $pool,
    [Parameter(Mandatory=$true)]
    [string] $vstsAgentUrl,
    [Parameter(Mandatory=$false)]
    [string] $finalSetupScriptUrl,
    [Parameter(Mandatory=$true)]
    [string] $vmname
)

function Download-File([string]$sourceUrl, [string]$destinationFile)
{
    Remove-Item -Path $destinationFile -Force -ErrorAction Ignore
    (New-Object System.Net.WebClient).DownloadFile($sourceUrl, $destinationFile)
}

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls -bor [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls12

Set-ExecutionPolicy -ExecutionPolicy unrestricted -Force

Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 | Out-Null
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 | Out-Null

if (!(Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction Ignore)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.208 -Force -WarningAction Ignore | Out-Null
}

Install-Module -Name bccontainerhelper -Force
Import-Module -Name bccontainerhelper -DisableNameChecking

$installDocker = (!(Test-Path -Path "C:\Program Files\Docker\docker.exe" -PathType Leaf))
if ($installDocker) {
    Install-module DockerMsftProvider -Force
    Install-Package -Name docker -ProviderName DockerMsftProvider -Force
}

$DownloadFolder = "C:\Download"
MkDir $DownloadFolder -ErrorAction Ignore | Out-Null

$agentFilename = $vstsAgentUrl.Substring($vstsAgentUrl.LastIndexOf('/')+1)
$agentFullname = Join-Path $DownloadFolder $agentFilename
Download-File -sourceUrl $vstsAgentUrl -destinationFile $agentFullname
$agentFolder = "C:\Agent"
mkdir $agentFolder -ErrorAction Ignore | Out-Null
cd $agentFolder
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($agentFullname, $agentFolder)

.\config.cmd --unattended --url "$devopsorganization" --auth PAT --token "$personalaccesstoken" --pool "$pool" --agent "$vmname" --runAsService --windowsLogonAccount $vmAdminUsername --windowsLogonPassword $adminPassword

if ($installDocker) {
    Start-Service docker
}

if ($finalSetupScriptUrl) {
    if ($finalSetupScriptUrl -notlike "https://*" -and $finalSetupScriptUrl -notlike "http://*") {
        $finalSetupScriptUrl = $templateLink.Substring(0,$templateLink.LastIndexOf('/')+1)+$finalSetupScriptUrl    
    }
    Set-Content -Path (Join-Path $DownloadFolder "url.txt") -Value "$finalSetupScriptUrl"
    $finalSetupScript = Join-Path $DownloadFolder "FinalSetupScript.ps1"
    Download-File -sourceUrl $finalSetupScriptUrl -destinationFile $finalSetupScript
    . $finalSetupScript
}

Shutdown -r -t 60
