$ErrorActionPreference = "Stop"
$WarningActionPreference = "Stop"

# Specify which images to download
$ImagesToDownload = @()

$bcContainerHelperFolder = "C:\ProgramData\BcContainerHelper"

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (!($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    throw "This script must run with administrator privileges"
}

Write-Host "Checking Docker Service Settings..."
$dockerService = (Get-Service docker -ErrorAction Ignore)
if (!($dockerService)) {
    throw "Docker Service not found / Docker is not installed"
}

if ($dockerService.Status -ne "Running") {
    throw "Docker Service is $($dockerService.Status) (Needs to be running)"
}

$dockerInfo = (docker info)
$dockerOsMode = ($dockerInfo | Where-Object { $_.Trim().StartsWith('OSType: ') }).Trim().SubString(8)
if ($dockerOsMode -ne "Windows") {
    throw "Docker is not running Windows Containers"
}

$dockerRootDir = ($dockerInfo | Where-Object { $_.Trim().StartsWith('Docker Root Dir: ') }).Trim().SubString(17)
if (!(Test-Path $dockerRootDir -PathType Container)) {
    throw "Folder $dockerRootDir does not exist"
}

Write-Host -Foregroundcolor Red "This function will remove all containers, remove all images and clear the folder $dockerRootDir"
Write-Host -Foregroundcolor Red "The function will also clear the contents of $bcContainerHelperFolder."
Write-Host -Foregroundcolor Red "Are you absolutely sure you want to do this? (This cannot be undone)"
Write-Host -ForegroundColor Red "Type Yes to continue:" -NoNewline
if ((Read-Host) -ne "Yes") {
    throw "Mission aborted"
}

Write-Host "Running Docker System Prune"
docker system prune -f

Write-Host "Removing all containers (forced)"
docker ps -a -q | % { docker rm $_ -f 2> NULL }

Write-Host "Stopping Docker Service"
stop-service docker

Write-Host "Downloading Docker-Ci-Zap"
$dockerCiZapExe = Join-Path $Env:TEMP "docker-ci-zap.exe"
Remove-Item $dockerCiZapExe -Force -ErrorAction Ignore
(New-Object System.Net.WebClient).DownloadFile("https://github.com/jhowardmsft/docker-ci-zap/raw/master/docker-ci-zap.exe", $dockerCiZapExe)
Unblock-File -Path $dockerCiZapExe

Write-Host "Running Docker-Ci-Zap on $dockerRootDir"
Write-Host -ForegroundColor Yellow "Note: If this fails, please restart your computer and run this script again"
& $dockerCiZapExe -folder $dockerRootDir

Write-Host "Removing Docker-Ci-Zap"
Remove-Item $dockerCiZapExe

Write-Host "Starting Docker Service"
Start-Service docker

if (Test-Path $bcContainerHelperFolder -PathType Container) {
    Write-Host "Cleaning up $bcContainerHelperFolder"
    Get-ChildItem $bcContainerHelperFolder -Force | ForEach-Object { 
        Remove-Item $_.FullName -Recurse -force
    }
}

if ($ImagesToDownload) {
    Write-Host -ForegroundColor Green "Done cleaning up, pulling images for $os"

    $os = "ltsc2016"
    if ((Get-CimInstance win32_operatingsystem).BuildNumber -ge 17763) { $os = "ltsc2019" }
    
    # Download images needed
    $imagesToDownload | ForEach-Object {
        if ($_.EndsWith('-ltsc2016') -or $_.EndsWith('-1709') -or $_.EndsWith('-1803') -or $_.EndsWith('-ltsc2019') -or
            $_.EndsWith(':ltsc2016') -or $_.EndsWith(':1709') -or $_.EndsWith(':1803') -or $_.EndsWith(':ltsc2019')) {
            $imageName = $_
        } elseif ($_.Contains(':')) {
            $imageName = "$($_)-$os"
        } else {
            $imageName = "$($_):$os"
        }
        Write-Host "Pulling $imageName"
        docker pull $imageName
    }
}
