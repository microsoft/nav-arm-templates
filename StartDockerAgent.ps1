$erroractionpreference = "Stop"

function Log([string]$line) {
    ([DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line") | Add-Content -Path "c:\agent\status.txt"
}

. (Join-Path $PSScriptRoot "settings.ps1")

[Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.Filesystem") | Out-Null

$navDockerUrl = "https://github.com/Microsoft/nav-docker/archive/master.zip"
$tempFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
$tempFile = "$tempFolder.zip"

$StorageAccountName = "nav2016wswe0"
$secureStorageAccountKey = ConvertTo-SecureString -String $StorageAccountKey -Key $passwordKey
$plainStorageAccountKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureStorageAccountKey))

$storageContext = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $plainStorageAccountKey
$queue = Get-AzureStorageQueue -Name $queue -Context $storageContext -ErrorAction Ignore

while ($true) {
    $message = $queue.CloudQueue.GetMessage([TimeSpan]::FromHours(2))
    if (!($message)) {
        break
    }
    $description = "description not set!"
    try {
        if (!(Test-Path $tempFolder -PathType Container)) {
            Log "Downloading nav-docker repo"
            New-Item -ItemType Directory -Path $tempFolder | out-null
            (New-Object System.Net.WebClient).DownloadFile($navDockerUrl, $tempFile)
            [System.IO.Compression.ZipFile]::ExtractToDirectory($tempFile, $tempFolder)
        }
        $navDockerPath = Join-Path $tempFolder "nav-docker-master"
        $json = $message.AsString | ConvertFrom-Json
        $description = "$($json.task) $($json.version) $($json.country) $($json.platform) ($($message.Id))"
        Log "BUILD: $description"
        . (Join-Path $navDockerPath "$($json.task)\build-local.ps1") $json
        Log "SUCCESS: $description"
        $queue.CloudQueue.DeleteMessage($message)
    } catch {
        if ($message.DequeueCount -eq 10) {
            Log "ERROR: $description"
            $queue.CloudQueue.DeleteMessage($message)
        } else {
            Log "WARNING: $description"
            Start-Sleep -Seconds 60
        }
    } finally {
        Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction Ignore
        Remove-Item -Path $tempFile -Force -ErrorAction Ignore
    }
}
