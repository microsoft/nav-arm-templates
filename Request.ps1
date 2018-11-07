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
            Start-Transcript -Path "c:\demo\request\$id.txt" 
            $request = $request.Substring($idx)
        }

        $queryParameters = [System.Web.HttpUtility]::ParseQueryString($request)

        $token = $QueryParameters.Get("token")
        $cmd = $QueryParameters.Get("cmd")

        if ("$token".Equals("$requestToken")) {
            $LogStr = "$cmd"
            $Parameters = @{}
            $queryParameters.Keys | ForEach-Object {
                if ($_ -ne "cmd" -and "$_" -ne "token") {
                    $logStr += (" -$_ " + $queryParameters[$_])
                    $Parameters += @{ "$_" = $queryParameters[$_] }
                }
            }
            $script = Get-Item -Path "c:\demo\request\$cmd.ps1" -ErrorAction Ignore
            if (($script) -and ($script.FullName.ToLowerInvariant().StartsWith("c:\demo\request\"))) {
                Log "Request: $LogStr"
                . $script @Parameters
            } else {
                Log "Illegal request: $LogStr"
            }
        } else {
            Log "Illegal request token: $token"
        }
    }
} else {
    Log "No Event found with event ID $eventId"
}
