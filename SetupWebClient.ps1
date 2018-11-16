. "c:\run\SetupWebClient.ps1"

# Copy missing files to Web Client folder

$sourcepath = (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Web Client\WebPublish")
if ($sourcepath) {
    if (!(Get-Variable WebServerInstance -ErrorAction Ignore)) {
        $WebServerInstance = "NAV"
    }
    $destpath = "c:\inetpub\wwwroot\$WebServerInstance"
    
    Get-ChildItem $sourcepath.FullName -Recurse -File | % {
        $fp = $_.FullName
        $df = ($destpath + $fp.Substring($sourcepath.FullName.Length))
        if (!(Test-Path -Path $df)) {
            Write-Host "Copy missing file $fp"
            Copy-Item -Path $fp -Destination $df

        }
    }
} 
