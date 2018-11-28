Param(
    [string] $AgentName = "Manual"
)

$erroractionpreference = "Stop"

. (Join-Path $PSScriptRoot "settings.ps1")

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls -bor [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls12
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
    New-AzureStorageTable –Name "QueueStatus" –Context $storageContext -ErrorAction Ignore | Out-Null
}
$table = Get-AzureStorageTable –Name "QueueStatus" –Context $storageContext

while ($true) {
    $message = $azureQueue.CloudQueue.GetMessage([TimeSpan]::FromHours(2))
    if (!($message)) {
        break
    }
    try {
        if (!(Test-Path $tempFolder -PathType Container)) {
            New-Item -ItemType Directory -Path $tempFolder | out-null
            (New-Object System.Net.WebClient).DownloadFile($navDockerUrl, $tempFile)
            [System.IO.Compression.ZipFile]::ExtractToDirectory($tempFile, $tempFolder)
        }
        $navDockerPath = Join-Path $tempFolder "nav-docker-master"
        $json = $message.AsString | ConvertFrom-Json
        $ht = @{ "vmName" = $vmName
                 "Queue" = $queue
                 "Task" = $json.task
                 "navversion" = $json.navversion
                 "cu" = $json.cu
                 "Country" = $json.country
                 "Tags" = $json.tags
                 "version" = $json.version
               }
        Add-StorageTableRow -table $table -partitionKey $AgentName -rowKey ([string]::Format("{0:D19}", [DateTime]::MaxValue.Ticks - [DateTime]::UtcNow.Ticks)) -property (@{"Status" = "Build"} + $ht) | Out-Null
        . (Join-Path $navDockerPath "$($json.task)\build.ps1") -json $json
        Add-StorageTableRow -table $table -partitionKey $AgentName -rowKey ([string]::Format("{0:D19}", [DateTime]::MaxValue.Ticks - [DateTime]::UtcNow.Ticks)) -property (@{"Status" = "Success"} + $ht) | Out-Null
        $azureQueue.CloudQueue.DeleteMessage($message)
        . (Join-Path $navDockerPath "$($json.task)\cleanup.ps1") -Context $storageContext -json $json
    } catch {
        if ($message.DequeueCount -eq 10) {
            Add-StorageTableRow -table $table -partitionKey $AgentName -rowKey ([string]::Format("{0:D19}", [DateTime]::MaxValue.Ticks - [DateTime]::UtcNow.Ticks)) -property (@{"Status" = "Error"} + $ht) | Out-Null
            $azureQueue.CloudQueue.DeleteMessage($message)
            . (Join-Path $navDockerPath "$($json.task)\cleanup.ps1") -Context $storageContext -json $json
        } else {
            Add-StorageTableRow -table $table -partitionKey $AgentName -rowKey ([string]::Format("{0:D19}", [DateTime]::MaxValue.Ticks - [DateTime]::UtcNow.Ticks)) -property (@{"Status" = "Warning $($message.DequeueCount)"} + $ht) | Out-Null
            Start-Sleep -Seconds 60
        }
    } finally {
        Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction Ignore
        Remove-Item -Path $tempFile -Force -ErrorAction Ignore
    }
}

