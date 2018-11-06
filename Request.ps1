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
Add-Type -AssemblyName System.Web

$event = Get-EventLog -LogName Application -Source Application -Newest 1 | Where-Object { $_.EventID -eq $eventID }
if ($event) {
    $event.ReplacementStrings | ForEach-Object {
        $request = $_
        $idx = $request.IndexOf("?")
        if ($idx -gt 0) {
            $id = $request.Substring(0,$idx)
            if (!(Test-Path -Path "c:\demo\request")) {
                New-Item -Path "c:\demo\request" -ItemType Directory | Out-Null
            }
            Start-Transcript -Path "c:\demo\request\$id.txt" 
            $request = $request.Substring($idx)
        }

        $cmd = ([System.Web.HttpUtility]::ParseQueryString($request)).Get("cmd");

        if ($cmd -eq "Replace-NavServerContainer") {
            $log = "Request: Replace-NavServerContainer"
            $alwaysPull = ([System.Web.HttpUtility]::ParseQueryString($request)).Get("alwayspull");
            $parameters = @{}
            if ($alwaysPull -eq "yes") {
                $parameters += @{ "alwayspull" = $true }
                $log += " -alwaysPull"
            }
            Log $log
            Replace-NavServerContainer @parameters
        } else {
            Log "Unknown request: $cmd"
        }
    }
} else {
    Log "No Event found with event ID $eventId"
}
