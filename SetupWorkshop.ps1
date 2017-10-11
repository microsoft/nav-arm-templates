try {
    $Folder = "C:\DOWNLOAD\VisualStudio2017Enterprise"
    $Filename = "$Folder\vs_enterprise.exe"
    New-Item $Folder -itemtype directory -ErrorAction ignore | Out-Null
    
    if (!(Test-Path $Filename)) {
        Log "Downloading Visual Studio 2017 Enterprise Setup Program"
        $WebClient = New-Object System.Net.WebClient
        $WebClient.DownloadFile("https://aka.ms/vs/15/release/vs_enterprise.exe", $Filename)
    }
    
    Log "Installing Visual Studio 2017 Enterprise (this might take a while)"
    $setupParameters = “--quiet --norestart"
    Start-Process -FilePath $Filename -WorkingDirectory $Folder -ArgumentList $setupParameters -Wait -Passthru | Out-Null

    $setupParameters = “--quiet --norestart --add Microsoft.VisualStudio.Component.Windows10SDK.14393"
    Start-Process -FilePath $Filename -WorkingDirectory $Folder -ArgumentList $setupParameters -Wait -Passthru | Out-Null
    
    Start-Sleep -Seconds 10

} catch {
    Log -color Red -line ($Error[0].ToString() + " (" + ($Error[0].ScriptStackTrace -split '\r\n')[0] + ")")
}

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
