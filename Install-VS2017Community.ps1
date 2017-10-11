if (!(Test-Path function:Log)) {
    function Log([string]$line, [string]$color = "Gray") {
        ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt"
        Write-Host -ForegroundColor $color $line 
    }
}

$Folder = "C:\DOWNLOAD\VisualStudio2017Community"
$Filename = "$Folder\vs_community.exe"
New-Item $Folder -itemtype directory -ErrorAction ignore | Out-Null

if (!(Test-Path $Filename)) {
    Log "Downloading Visual Studio 2017 Community Setup Program"
    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile("https://aka.ms/vs/15/release/vs_community.exe", $Filename)
}

Log "Installing Visual Studio 2017 Community (this might take a while)"
$setupParameters = “--quiet --norestart"
Start-Process -FilePath $Filename -WorkingDirectory $Folder -ArgumentList $setupParameters -Wait -Passthru | Out-Null

$setupParameters = “--quiet --norestart --add Microsoft.VisualStudio.Component.Windows10SDK.14393"
Start-Process -FilePath $Filename -WorkingDirectory $Folder -ArgumentList $setupParameters -Wait -Passthru | Out-Null
