Param(
    [string] $taskName
)

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
$azureQueue = Get-AzureStorageQueue -Name $queue -Context $storageContext -ErrorAction Ignore

$table = Get-AzureStorageTable –Name "QueueStatus" –Context $storageContext -ErrorAction Ignore
if (!($table)) {
    $table = New-AzureStorageTable –Name "QueueStatus" –Context $storageContext
}

while ($true) {
    $message = $azureQueue.CloudQueue.GetMessage([TimeSpan]::FromHours(2))
    if (!($message)) {
        break
    }
    $description = "description not set!"
    try {
        if (!(Test-Path $tempFolder -PathType Container)) {
            New-Item -ItemType Directory -Path $tempFolder | out-null
            (New-Object System.Net.WebClient).DownloadFile($navDockerUrl, $tempFile)
            [System.IO.Compression.ZipFile]::ExtractToDirectory($tempFile, $tempFolder)
        }
        $navDockerPath = Join-Path $tempFolder "nav-docker-master"
        $json = $message.AsString | ConvertFrom-Json
        $ht = @{"vmName" = $vmName; "TaskName" = $TaskName}
        $json.psobject.properties | Foreach { $ht[$_.Name] = $_.Value }

        Add-StorageTableRow -table $table -partitionKey $queue -rowKey ([Guid]::NewGuid()).ToString() -property (@{"Status" = "Build"} + $ht)
        . (Join-Path $navDockerPath "$($json.task)\build-local.ps1") $json
        Add-StorageTableRow -table $table -partitionKey $queue -rowKey ([Guid]::NewGuid()).ToString() -property (@{"Status" = "Success"} + $ht)
        $azureQueue.CloudQueue.DeleteMessage($message)
    } catch {
        if ($message.DequeueCount -eq 10) {
            Add-StorageTableRow -table $table -partitionKey $queue -rowKey ([Guid]::NewGuid()).ToString() -property (@{"Status" = "Error"} + $ht)
            $azureQueue.CloudQueue.DeleteMessage($message)
        } else {
            Add-StorageTableRow -table $table -partitionKey $queue -rowKey ([Guid]::NewGuid()).ToString() -property (@{"Status" = "Warning $($message.DequeueCount)"} + $ht)
            Start-Sleep -Seconds 60
        }
    } finally {
        Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction Ignore
        Remove-Item -Path $tempFile -Force -ErrorAction Ignore
    }
}
