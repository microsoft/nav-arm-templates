function Download-File([string]$sourceUrl, [string]$destinationFile)
{
    Remove-Item -Path $destinationFile -Force -ErrorAction Ignore
    (New-Object System.Net.WebClient).DownloadFile($sourceUrl, $destinationFile)
}

function ConvertTo-HashTable() {
    [CmdletBinding()]
    Param(
        [parameter(ValueFromPipeline)]
        [PSCustomObject] $object
    )
    $ht = @{}
    if ($object) {
        $object.PSObject.Properties | Foreach { $ht[$_.Name] = $_.Value }
    }
    $ht
}

Start-Transcript -Path "c:\log2.txt"

$errorActionPreference = "Stop"
$DownloadFolder = 'c:\download'
if ($runInsideDocker -eq "Yes") {
    Set-Location $DownloadFolder
    New-Item -Path 'image' -ItemType Directory | Out-Null
    Set-Location 'image'
    $runnerImageFolder = Get-Location

    $startScriptUrl = $templateLink.Substring(0,$templateLink.LastIndexOf('/')+1)+'AgentImage.start.ps1'
    Download-File -sourceUrl $startScriptUrl -destinationFile (Join-Path $runnerImageFolder 'start.ps1')
    $dockerFileUrl = $templateLink.Substring(0,$templateLink.LastIndexOf('/')+1)+'AgentImage.DOCKERFILE'
    Download-File -sourceUrl $dockerFileUrl -destinationFile (Join-Path $runnerImageFolder 'DOCKERFILE')

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
        @{ "useVolumes" = $true; "ContainerHelperFolder" = "c:\bcch"; "defaultNewContainerParameters" = @{ "isolation" = "process" } } | ConvertTo-Json -Depth 99 | Set-Content (Join-Path $allVolumes.hosthelperfolder "BcContainerHelper.config.json") -Encoding UTF8
        
        docker run -d --name $agentContainerName -v \\.\pipe\docker_engine:\\.\pipe\docker_engine -v C:\d\volumes:C:\d\volumes --mount source=$bcartifactsCacheVolumeName,target=c:\bcartifacts.cache --mount source=$bcContainerHelperVolumeName,target=C:\BCCH --mount source=$AgentWorkVolumeName,target=C:\Sources --env AGENTURL=$agentUrl --env ORGANIZATIOn=$organization --env AGENTNAME=$agentName --env POOL=$pool --env TOKEN=$token $imageName
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

