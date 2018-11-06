Param (
    [int] $eventID
)

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

$event = Get-EventLog -LogName Application -Source Application -Newest 1 | Where-Object { $_.EventID -eq $eventID }
if ($event) {
    $event.ReplacementStrings | ForEach-Object {
        $request = $_
        if ($request -eq "Replace-NavServerContainer") {
            Log "Replacing NavServerContainer"
            Replace-NavServerContainer
        } elseif ($request -eq "Replace-NavServerContainer-AlwaysPull") {
            Log "Replacing NavServerContainer (with alwaysPull)"
            Replace-NavServerContainer -alwaysPull
        } else {
            Log "Unknown request: $request"
        }
    }
} else {
    Log "No Event found with event ID $eventId"
}
