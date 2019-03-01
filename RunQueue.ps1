# Run this every x minutes from Task Scheduler

$ErrorActionPreference = "Stop"

. (Join-Path $PsScriptRoot "settings.ps1")

if (Test-Path -Path "C:\demo\navcontainerhelper-dev\NavContainerHelper.psm1") {
    Import-module "C:\demo\navcontainerhelper-dev\NavContainerHelper.psm1" -DisableNameChecking
} else {
    Import-Module -name navcontainerhelper -DisableNameChecking
}

$storageContext = New-AzureStorageContext -ConnectionString $storageConnectionString
$queuename = $publicDnsName.Split('.')[0]

# Create Queue (if it doesn't exist)
$storageQueue = Get-AzureStorageQueue -Context $storageContext -Name $queuename -ErrorAction Ignore
if (!($storageQueue)) {
    New-AzureStorageQueue -Name $queuename -Context $storageContext -ErrorAction Ignore | Out-Null
}
$storageQueue = Get-AzureStorageQueue -Name $queuename -Context $storageContext

# Create table for replies (if it doesn't exist)
$table = Get-AzureStorageTable –Name "QueueStatus" –Context $storageContext -ErrorAction Ignore
if (!($table)) {
    New-AzureStorageTable –Name "QueueStatus" –Context $storageContext -ErrorAction Ignore | Out-Null
}
$table = Get-AzureStorageTable –Name "QueueStatus" –Context $storageContext

# Transcript container on azure storage
New-AzureStorageContainer -Context $storageContext -Name "transcript" -Permission Blob -ErrorAction SilentlyContinue | Out-Null

# Folder where command scripts are placed
$commandFolder = (Join-Path $PsScriptRoot "request").ToLowerInvariant()

# Folder for temp storage of transcripts
$transcriptFolder = Join-Path $PsScriptRoot "transcript"
if (!(Test-Path -Path $transcriptFolder -PathType Container)) {
    New-Item -Path $transcriptFolder -ItemType Directory | Out-Null
}

# Backup folder
$backupFolder = "c:\ProgramData\NavContainerHelper\backup"
if (!(Test-Path -Path $backupFolder -PathType Container)) {
    New-Item -Path $backupFolder -ItemType Directory | Out-Null
}


while ($true) {
    # Get message
    $timeUntilMessageReappearsInQueue = [TimeSpan]::FromMinutes(10)
    $message = $storageQueue.CloudQueue.GetMessage($timeUntilMessageReappearsInQueue)
    if (!($message)) {
        break
    }

    $transcriptname = ([Guid]::NewGuid().ToString()+".txt")
    $transcriptfilename = Join-Path $transcriptFolder $transcriptname
    $transcripting = $false

    $maxAttempts = 1
    $backup = $false
    $cmd = ""
    try {
        $json = $message.AsString | ConvertFrom-Json

        $cmd = $json.cmd
        $LogStr = "$cmd"

        $Parameters = @{}
        $json | Get-Member -MemberType NoteProperty | ForEach-Object {
            $key = $_.Name
            $value = $json."$key"
            if ($key -eq "backup") {
                $backup = $value
            } elseif ($key -eq "maxAttempts") {
                $maxAttempts = $value
            } elseif ($key -ne "cmd") {
                $LogStr += " -$key '$value'"
                $Parameters += @{ $key = $value }
            }
        }

        if ($message.DequeueCount -gt $maxAttempts) {
            throw "No more attempts"
        }

        $ht = @{ "Queue" = $queuename
            "Cmd" = $json.cmd
            "Logstr" = $LogStr
            "Dequeue" = $message.DequeueCount
            "Status" = "Begin"
            "transcript" = ""
        }
        Add-StorageTableRow -table $table -partitionKey $queuename -rowKey ([string]::Format("{0:D19}", [DateTime]::MaxValue.Ticks - [DateTime]::UtcNow.Ticks)) -property $ht | Out-Null

        Start-Transcript -Path $transcriptfilename
        $transcripting = $true
        Write-Host '---------------------------'
        Write-Host $message.AsString
        Write-Host '---------------------------'

        if ($backup) {
            Write-Host "Backing up database (if not exists)"
            . (Join-Path $commandFolder "backup.ps1") -backupFolder $backupFolder -backupName $message.Id
        }

        $script = Get-Item -Path (Join-Path $commandFolder "$cmd.ps1") -ErrorAction Ignore
        if (($script) -and ($script.FullName.ToLowerInvariant().StartsWith($commandFolder))) {
            . $script @Parameters
            $ht.Status = "Success"
        } else {
            $ht.Status = "Error"
            Write-Host "Illegal request"
        }

        if ($backup) {
            Write-Host "Removing Backup"
            $backupDir = Join-Path $backupFolder $message.Id
            Remove-Item $backupDir -Recurse -Force
        }
        $storageQueue.CloudQueue.DeleteMessage($message)

    } catch {
        $ht.Status = "Exception"
        Write-Host "Exception performing RunQueue (Cmd=$cmd)"
        Write-Host $_.Exception.Message
        Write-Host $_.ScriptStackTrace

        if ($backup) {
            Write-Host "Restoring backup (if exists)"
            . (Join-Path $commandFolder "restore.ps1") -backupFolder $backupFolder -backupName $message.Id -removeBackup "yes"
        }

        if ($message.DequeueCount -ge $maxAttempts) {
            $storageQueue.CloudQueue.DeleteMessage($message)
        }
    } finally {
    }

    if ($transcripting) {
        $transcripting = $false
        Stop-Transcript

        Set-AzureStorageBlobContent -File $transcriptfilename -Context $storageContext -Container "transcript" -Blob $transcriptname -Force | Out-Null
        $ht.transcript = "$($StorageContext.BlobEndPoint)transcript/$transcriptname"
    }
    Add-StorageTableRow -table $table -partitionKey $queuename -rowKey ([string]::Format("{0:D19}", [DateTime]::MaxValue.Ticks - [DateTime]::UtcNow.Ticks)) -property $ht | Out-Null

}
