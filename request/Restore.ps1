Param(
    [string] $backupFolder = "c:\ProgramData\BcContainerHelper\backup",
    [string] $backupName = ([Guid]::NewGuid.ToString()),
    [string] $removeBackup = ""
)

$sessionParam = @{ "session" = (Get-NavContainerSession -containerName navserver -silent) }
$backupDir = Join-Path "c:\ProgramData\BcContainerHelper\backup" $backupName

if (!(Test-Path -Path $backupDir)) {
    throw "Backup doesn't exist"
}

Invoke-Command @sessionParam -ScriptBlock { Param($backupDir)

    $serviceTierFolder = (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service").FullName
    $customConfigFile = Join-Path $serviceTierFolder "CustomSettings.config"
    [xml]$customConfig = [System.IO.File]::ReadAllText($customConfigFile)
    $databaseServer = $customConfig.SelectSingleNode("//appSettings/add[@key='DatabaseServer']").Value
    $databaseInstance = $customConfig.SelectSingleNode("//appSettings/add[@key='DatabaseInstance']").Value
    $databaseName = $customConfig.SelectSingleNode("//appSettings/add[@key='DatabaseName']").Value

    Set-NavServerInstance -ServerInstance NAV -Stop
    try
    {
        Write-Host "Taking database $DatabaseName offline"
        Invoke-SqlCmd -Query ("ALTER DATABASE [{0}] SET OFFLINE WITH ROLLBACK IMMEDIATE" -f $DatabaseName)

        Write-Host "Copying database files"
        Invoke-SqlCmd -Query "SELECT f.physical_name FROM sys.sysdatabases db INNER JOIN sys.master_files f ON f.database_id = db.dbid WHERE db.name = '$DatabaseName'" | % {
            $FileInfo = Get-Item -Path $_.physical_name
            Write-Host $FileInfo.FullName
            $SourceFile = Join-Path $backupDir $FileInfo.Name
            Copy-Item -Path $SourceFile -Destination $FileInfo.FullName -Force
        }
    }
    finally
    {
        Write-Host "Putting database $DatabaseName back online"
        Invoke-SqlCmd -Query ("ALTER DATABASE [{0}] SET ONLINE" -f $DatabaseName)

        Set-NavServerInstance -ServerInstance NAV -Start
    }
} -ArgumentList $backupDir

if ($removeBackup -eq "yes") {
    Write-Host "Removing Backup"
    Remove-Item -Path $backupDir -Force -Recurse
}
