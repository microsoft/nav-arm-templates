. (Join-Path $PSScriptRoot "Install-VS2017Community.ps1")

try {
    $Folder = "C:\DOWNLOAD\AdobeReader"
    $Filename = "$Folder\AdbeRdr11010_en_US.exe"
    New-Item $Folder -itemtype directory -ErrorAction ignore | Out-Null
    
    if (!(Test-Path $Filename)) {
        Log "Downloading Adobe Reader"
        $WebClient = New-Object System.Net.WebClient
        $WebClient.DownloadFile("http://ardownload.adobe.com/pub/adobe/reader/win/11.x/11.0.10/en_US/AdbeRdr11010_en_US.exe", $Filename)
    }
    
    Log "Installing Adobe Reader (this should only take a few minutes)"
    Start-Process $Filename -ArgumentList "/msi /qn" -Wait -Passthru | Out-Null
    Start-Sleep -Seconds 10

} catch {
    Log -color Red -line ($Error[0].ToString() + " (" + ($Error[0].ScriptStackTrace -split '\r\n')[0] + ")")
}

# Install Windows Updates
Log "Installing Windows Updates (this happens in the background and the machine might reboot when done)"
install-module PSWindowsUpdate -force
Start-Process "powershell.exe" -ArgumentList "Get-WUInstall -install -acceptall -autoreboot" -PassThru
