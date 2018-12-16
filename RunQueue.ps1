if (!(Test-Path function:Log)) {
    function Log([string]$line, [string]$color = "Gray") {
        ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt"
        Write-Host -ForegroundColor $color $line 
    }
}

if (Test-Path -Path "C:\demo\navcontainerhelper-dev\NavContainerHelper.psm1") {
    Import-module "C:\demo\navcontainerhelper-dev\NavContainerHelper.psm1" -DisableNameChecking
} else {
    Import-Module -name navcontainerhelper -DisableNameChecking
}

. (Join-Path $PSScriptRoot "settings.ps1")
Add-Type -AssemblyName System.Web

# Create Queue
$storageContext = New-AzureStorageContext -ConnectionString $storageConnectionString
$queuename = $publicDnsName.Split('.')[0]

$storageQueue = Get-AzureStorageQueue -Context $storageContext -Name $queuename -ErrorAction Ignore
if (!($storageQueue)) {
    New-AzureStorageQueue -Name $queuename -Context $storageContext -ErrorAction Ignore | Out-Null
}
$storageQueue = Get-AzureStorageQueue -Name $queuename -Context $storageContext

# Run this every x minutes from Task Scheduler
while ($true) {
    # Get message
    $timeUntilMessageReappearsInQueue = [TimeSpan]::FromMinutes(1)
    $message = $storageQueue.CloudQueue.GetMessage($timeUntilMessageReappearsInQueue)
    if (!($message)) {
        break
    }
    $cmd = ""
    try {
        $json = $message.AsString | ConvertFrom-Json

        $cmd = $json.cmd
        $LogStr = "$cmd"
        $Parameters = @{}

        $json | Get-Member -MemberType NoteProperty | ForEach-Object {
            $key = $_.Name
            $value = $json."$key"
            if ($key -ne "cmd") {
                $LogStr += " -$key '$value'"
                $Parameters += @{ $key = $value }
            }
        }

        $script = Get-Item -Path "c:\demo\request\$cmd.ps1" -ErrorAction Ignore
        if (($script) -and ($script.FullName.ToLowerInvariant().StartsWith("c:\demo\request\"))) {
            Log "Request: $LogStr"
            . $script @Parameters
        } else {
            Log "Illegal request: $LogStr"
        }
    } catch {
        Log "Exception performing RunQueue (Cmd=$cmd)"
    } finally {
        $storageQueue.CloudQueue.DeleteMessage($message)
    }
}
