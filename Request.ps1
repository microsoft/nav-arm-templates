Param (
    [int] $eventID
)

if (!(Test-Path function:AddToStatus)) {
    function AddToStatus([string]$line, [string]$color = "Gray") {
        ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt" -Force -ErrorAction SilentlyContinue
        Write-Host -ForegroundColor $color $line 
    }
}

if (Test-Path -Path "C:\demo\*\BcContainerHelper.psm1") {
    $module = Get-Item -Path "C:\demo\*\BcContainerHelper.psm1"
    Import-module $module.FullName -DisableNameChecking
} else {
    Import-Module -name bccontainerhelper -DisableNameChecking
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

        $token = $QueryParameters.Get("requesttoken")
        $cmd = $QueryParameters.Get("cmd")

        if ("$token".Equals("$requestToken")) {
            $StatusStr = "$cmd"
            $Parameters = @{}
            $queryParameters.Keys | ForEach-Object {
                if ($_ -ne "cmd" -and "$_" -ne "requesttoken") {
                    $StatusStr += " -$_ '$($queryParameters[$_])'"
                    $Parameters += @{ "$_" = $queryParameters[$_] }
                }
            }
            $script = Get-Item -Path "c:\demo\request\$cmd.ps1" -ErrorAction Ignore
            if (($script) -and ($script.FullName.ToLowerInvariant().StartsWith("c:\demo\request\"))) {
                AddToStatus "Request: $StatusStr"
                . $script @Parameters
            } else {
                AddToStatus "Illegal request: $StatusStr"
            }
        } else {
            AddToStatus "Illegal RequestToken"
        }
        if ($idx -gt 0) {
            Stop-Transcript
        }
    }
} else {
    AddToStatus "No Event found with event ID $eventId"
}
