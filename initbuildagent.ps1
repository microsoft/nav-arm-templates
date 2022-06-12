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

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls -bor [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls12

Set-ExecutionPolicy -ExecutionPolicy unrestricted -Force

Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 | Out-Null
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 | Out-Null

if (!(Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction Ignore)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.208 -Force -WarningAction Ignore | Out-Null
}

$DownloadFolder = "C:\Download"
MkDir $DownloadFolder -ErrorAction Ignore | Out-Null

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

if ($runInsideDocker -eq "Yes") {
    Set-Location $DownloadFolder
    New-Item -Path 'image' -ItemType Directory | Out-Null
    Set-Location 'image'

    $startScriptUrl = $templateLink.Substring(0,$templateLink.LastIndexOf('/')+1)+'AgentImage.start.ps1'
    Download-File -sourceUrl $startScriptUrl -destinationFile 'start.ps1'
    $dockerFileUrl = $templateLink.Substring(0,$templateLink.LastIndexOf('/')+1)+'AgentImage.DOCKERFILE'
    Download-File -sourceUrl $dockerFileUrl -destinationFile 'DOCKERFILE'

    $os = (Get-CimInstance Win32_OperatingSystem)
    $UBR = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name UBR).UBR
    $hostOsVersion = [System.Version]::Parse("$($os.Version).$UBR")
    if ($os.version -eq '10.0.22000') {
        $hostOsVersion = 'ltsc2022'
    }
    $serverCoreImage = "mcr.microsoft.com/windows/servercore:$($hostOsVersion)"
    $imageName = 'runneragent:latest'
    docker build --build-arg baseimage=$serverCoreImage --tag $imageName .

    1..$count | ForEach-Object {
        $agentContainerName = "agent$_"

        $agentName = "$vmName-docker-$_-$([guid]::NewGuid().ToString())"
        
        $bcartifactsCacheVolumeName = 'bcartifacts.cache'
        $bcContainerHelperVolumeName = 'hostHelperFolder'
        $AgentWorkVolumeName = "$($agentContainerName)_Work"
        
        $allVolumes = "{$(((docker volume ls --format "'{{.Name}}': '{{.Mountpoint}}'") -join ",").Replace('\','\\').Replace("'",'"'))}" | ConvertFrom-Json | ConvertTo-HashTable
        $bcartifactsCacheVolumeName, $bcContainerHelperVolumeName, $AgentWorkVolumeName | ForEach-Object {
            if (-not $allVolumes.ContainsKey($_)) { docker volume create $_ }
        }
        $allVolumes = (docker volume ls --format "{ '{{.Name}}': '{{.Mountpoint}}' }").Replace('\','\\').Replace("'",'"') | ConvertFrom-Json | ConvertTo-HashTable
        @{ "useVolumes" = $true; "ContainerHelperFolder" = "c:\bcch"; "defaultNewContainerParameters" = @{ "isolation" = "hyperv" } } | ConvertTo-Json -Depth 99 | Set-Content (Join-Path $allVolumes.hosthelperfolder "BcContainerHelper.config.json") -Encoding UTF8
        
        docker run -d --name $agentContainerName -v \\.\pipe\docker_engine:\\.\pipe\docker_engine -v C:\ProgramData\docker\volumes:C:\ProgramData\docker\volumes --mount source=$bcartifactsCacheVolumeName,target=c:\bcartifacts.cache --mount source=$bcContainerHelperVolumeName,target=C:\BCCH --mount source=$AgentWorkVolumeName,target=C:\Sources --env AGENTURL=$agentUrl --env ORGANIZATIOn=$organization --env AGENTNAME=$agentName --env POOL=$pool --env TOKEN=$token $imageName
    }
}
else {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $agentFilename = $agentUrl.Substring($agentUrl.LastIndexOf('/')+1)
    $agentFullname = Join-Path $DownloadFolder $agentFilename
    Download-File -sourceUrl $agentUrl -destinationFile $agentFullname
    1..$count | ForEach-Object {
        $agentName = "$vmName-$_-$([guid]::NewGuid().ToString())"
        $agentFolder = "C:\$_"
        mkdir $agentFolder -ErrorAction Ignore | Out-Null
        Set-Location $agentFolder
        [System.IO.Compression.ZipFile]::ExtractToDirectory($agentFullname, $agentFolder)
    
        if ($agentUrl -like 'https://github.com/actions/runner/releases/download/*') {
            .\config.cmd --unattended --url "$organization" --token "$token" --name $agentName --labels "$pool" --runAsService --windowslogonaccount "NT AUTHORITY\SYSTEM"
        }
        else {
            .\config.cmd --unattended --url "$organization" --auth PAT --token "$token" --pool "$pool" --agent $agentName --runAsService --windowslogonaccount "NT AUTHORITY\SYSTEM"
        }
    }
}

Shutdown -r -t 60
