# Script slightly modified from AJ Kaufmanns blog post https://www.kauffmann.nl/2019/03/04/how-to-install-docker-on-windows-10-without-hyper-v/

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This script needs to run as admin"
}

# Install Windows feature containers
$restartNeeded = $false
if (!(Get-WindowsOptionalFeature -FeatureName containers -Online).State -eq 'Enabled') {
    $restartNeeded = (Enable-WindowsOptionalFeature -FeatureName containers -Online).RestartNeeded
}

$dockerVersion = docker version -f "{{.Server.Version}}"
Write-Host "Current installed docker version $dockerVersion"

$json = Invoke-WebRequest https://dockermsft.azureedge.net/dockercontainer/DockerMsftIndex.json | ConvertFrom-Json
$stableversion = $json.channels.cs.alias
$version = $json.channels.$stableversion.version
$url = $json.versions.$version.url
$zipfile = Join-Path "$env:USERPROFILE\Downloads\" $json.versions.$version.url.Split('/')[-1]
Write-Host "Latest available docker engine $version"

if ([Version]$version -le [Version]$dockerVersion) {
    Write-Host "No new version available"
}
else {
    if (Get-Service docker -ErrorAction SilentlyContinue)
    {
        Stop-Service docker
    }
    
    Invoke-WebRequest -UseBasicparsing -Outfile $zipfile -Uri $url
    
    # Extract the archive.
    Expand-Archive $zipfile -DestinationPath $Env:ProgramFiles -Force
    
    # Modify PATH to persist across sessions.
    $newPath = [Environment]::GetEnvironmentVariable("PATH",[EnvironmentVariableTarget]::Machine) + ";$env:ProgramFiles\docker"
    $splittedPath = $newPath -split ';'
    $cleanedPath = $splittedPath | Sort-Object -Unique
    $newPath = $cleanedPath -join ';'
    [Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::Machine)
    $env:path = $newPath
    
    # Register the Docker daemon as a service.
    if (!(Get-Service docker -ErrorAction SilentlyContinue)) {
      dockerd --exec-opt isolation=process --register-service
    }
    
    # Start the Docker service.
    if ($restartNeeded) {
        Write-Host 'A restart is needed to finish the installation' -ForegroundColor Green
        If ((Read-Host 'Restart now? [Y/N]') -eq 'Y') {
          Restart-Computer
        }
    } else {
        Start-Service docker
    }
}
