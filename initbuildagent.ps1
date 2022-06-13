#usage initbuildagent.ps1
param
(
    [string] $templateLink              = "https://raw.githubusercontent.com/Microsoft/nav-arm-templates/master/buildagent.json",
    [Parameter(Mandatory=$true)]
    [string] $vmAdminUsername,
    [Parameter(Mandatory=$true)]
    [string] $adminPassword,
    [Parameter(Mandatory=$true)]
    [string] $organization,
    [Parameter(Mandatory=$true)]
    [string] $token,
    [Parameter(Mandatory=$true)]
    [string] $pool,
    [Parameter(Mandatory=$true)]
    [string] $agentUrl,
    [Parameter(Mandatory=$false)]
    [string] $finalSetupScriptUrl,
    [Parameter(Mandatory=$true)]
    [int] $count = 1,
    [Parameter(Mandatory=$true)]
    [string] $vmname,
    [Parameter(Mandatory=$true)]
    [string] $runInsideDocker
)

function Download-File([string]$sourceUrl, [string]$destinationFile)
{
    Remove-Item -Path $destinationFile -Force -ErrorAction Ignore
    (New-Object System.Net.WebClient).DownloadFile($sourceUrl, $destinationFile)
}

Start-Transcript -Path "c:\log.txt"

$errorActionPreference = "Stop"

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls -bor [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls12

Set-ExecutionPolicy -ExecutionPolicy unrestricted -Force

Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 -ErrorAction SilentlyContinue | Out-Null

if (!(Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction Ignore)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.208 -Force -WarningAction Ignore | Out-Null
}

$DownloadFolder = "C:\Download"
MkDir $DownloadFolder -ErrorAction Ignore | Out-Null

$SetupAgentScriptUrl = $templateLink.Substring(0,$templateLink.LastIndexOf('/')+1)+'SetupAgents.ps1'
$SetupAgentsScript = "c:\Download\SetupAgents.ps1"
Download-File -sourceUrl $SetupAgentScriptUrl -destinationFile $SetupAgentsScript

$installDocker = (!(Test-Path -Path "C:\Program Files\Docker\docker.exe" -PathType Leaf))
if ($installDocker) {
    $installDockerScriptUrl = $templateLink.Substring(0,$templateLink.LastIndexOf('/')+1)+'InstallOrUpdateDockerEngine.ps1'
    $installDockerScript = Join-Path $DownloadFolder "InstallOrUpdateDockerEngine.ps1"
    Download-File -sourceUrl $installDockerScriptUrl -destinationFile $installDockerScript
    . $installDockerScript -Force -envScope "Machine" -dataRoot 'c:\d'
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

if ($token) {
    $setupAgentScriptContent = Get-Content -Path $setupAgentScript -Encoding UTF8 -Raw

    Set-Content -Path $setupAgentScript -Value @"
`$organization = '$organization'
`$token = '$token'
`$agentName = '$agentName'
`$pool = '$pool'
`$count = $count
`$templateLink = '$templateLink'
`$runInsideDocker = '$runInsideDocker'

$setupAgentScriptContent
"@

    $startupAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy UnRestricted -File $SetupAgentScript"
    $startupTrigger = New-ScheduledTaskTrigger -AtStartup
    $startupTrigger.Delay = "PT1M"
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd
    Register-ScheduledTask -TaskName "SetupStart" `
                           -Action $startupAction `
                           -Trigger $startupTrigger `
                           -Settings $settings `
                           -RunLevel "Highest" `
                           -User "NT AUTHORITY\SYSTEM" | Out-Null

    Shutdown -r -t 60
}