if (!(Test-Path function:Log)) {
    function Log([string]$line, [string]$color = "Gray") {
        ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt"
        Write-Host -ForegroundColor $color $line 
    }
}

Import-Module -name navcontainerhelper -DisableNameChecking

. (Join-Path $PSScriptRoot "settings.ps1")

Log -color Green "Setting up Desktop Experience"

$codeCmd = "C:\Program Files\Microsoft VS Code\bin\Code.cmd"
$codeExe = "C:\Program Files\Microsoft VS Code\Code.exe"
$firsttime = (!(Test-Path $codeExe))
$disableVsCodeUpdate = $false

if ($firsttime) {
    $Folder = "C:\DOWNLOAD\VSCode"
    $Filename = "$Folder\VSCodeSetup-stable.exe"

    New-Item $Folder -itemtype directory -ErrorAction ignore | Out-Null
    if (!(Test-Path $Filename)) {
        $sourceUrl = "https://go.microsoft.com/fwlink/?Linkid=852157"

        Download-File -SourceUrl $sourceUrl -destinationFile $Filename
    }
    
    Log "Installing Visual Studio Code (this should only take a minute)"
    $setupParameters = “/VerySilent /CloseApplications /NoCancel /LoadInf=""c:\demo\vscode.inf"" /MERGETASKS=!runcode"
    Start-Process -FilePath $Filename -WorkingDirectory $Folder -ArgumentList $setupParameters -Wait -Passthru | Out-Null

    Log "Downloading samples"
    $Folder = "C:\DOWNLOAD"
    $Filename = "$Folder\samples.zip"
    Download-File -sourceUrl "https://www.github.com/Microsoft/AL/archive/master.zip" -destinationFile $filename

    Remove-Item -Path "$folder\AL-master" -Force -Recurse -ErrorAction Ignore | Out-null
    [Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.Filesystem") | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory($filename, $folder)
    
    $alFolder = "$([Environment]::GetFolderPath("MyDocuments"))\AL"
    Remove-Item -Path "$alFolder\Samples" -Recurse -Force -ErrorAction Ignore | Out-Null
    New-Item -Path "$alFolder\Samples" -ItemType Directory -Force -ErrorAction Ignore | Out-Null
    Copy-Item -Path "$folder\AL-master\samples\*" -Destination "$alFolder\samples" -Recurse -ErrorAction Ignore
    Copy-Item -Path "$folder\AL-master\snippets\*" -Destination "$alFolder\snippets" -Recurse -ErrorAction Ignore
}

$vsixFileName = (Get-Item "C:\Demo\$containerName\*.vsix").FullName
if ($vsixFileName -ne "") {

    Log "Installing .vsix"
    & $codeCmd @('--install-extension', $VsixFileName) | Out-Null

    $username = [Environment]::UserName
    if (Test-Path -path "c:\Users\Default\.vscode" -PathType Container -ErrorAction Ignore) {
        if (!(Test-Path -path "c:\Users\$username\.vscode" -PathType Container -ErrorAction Ignore)) {
            Copy-Item -Path "c:\Users\Default\.vscode" -Destination "c:\Users\$username\" -Recurse -Force -ErrorAction Ignore
        }
    }
}

if ($disableVsCodeUpdate) {
    $vsCodeSettingsFile = Join-Path ([Environment]::GetFolderPath("ApplicationData")) "Code\User\settings.json"
    '{
        "update.channel": "none"
    }' | Set-Content $vsCodeSettingsFile
}

Log "Creating Desktop Shortcuts"
New-DesktopShortcut -Name "Landing Page" -TargetPath "http://${publicDnsName}" -IconLocation "C:\Program Files\Internet Explorer\iexplore.exe, 3"
New-DesktopShortcut -Name "Visual Studio Code" -TargetPath $codeExe
New-DesktopShortcut -Name "$containerName Web Client" -TargetPath "https://${publicDnsName}/NAV/" -IconLocation "C:\Program Files\Internet Explorer\iexplore.exe, 3"

$winClientFolder = (Get-Item "C:\Program Files (x86)\Microsoft Dynamics NAV\*\RoleTailored Client").FullName
if ($winClientFolder) {

    if ($firsttime) {
        Log "Installing Visual C++ Redist"
        $vcRedistUrl = "https://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x86.exe"
        $vcRedistFile = "C:\DOWNLOAD\vcredist_x86.exe"
        Download-File -sourceUrl $vcRedistUrl -destinationFile $vcRedistFile
        Start-Process $vcRedistFile -argumentList "/q" -wait
        
        Log "Installing SQL Native Client"
        $sqlncliUrl = "https://download.microsoft.com/download/3/A/6/3A632674-A016-4E31-A675-94BE390EA739/ENU/x64/sqlncli.msi"
        $sqlncliFile = "C:\DOWNLOAD\sqlncli.msi"
        Download-File -sourceUrl $sqlncliUrl -destinationFile $sqlncliFile
        Start-Process "C:\Windows\System32\msiexec.exe" -argumentList "/i $sqlncliFile ADDLOCAL=ALL IACCEPTSQLNCLILICENSETERMS=YES /qn" -wait
    }

    Log "Creating Windows Client configuration file"
    $ps = '$customConfigFile = Join-Path (Get-Item ''C:\Program Files\Microsoft Dynamics NAV\*\Service'').FullName "CustomSettings.config"
    [System.IO.File]::ReadAllText($customConfigFile)'
    [xml]$customConfig = docker exec $containerName powershell $ps
    $databaseInstance = $customConfig.SelectSingleNode("//appSettings/add[@key='DatabaseInstance']").Value
    $databaseName = $customConfig.SelectSingleNode("//appSettings/add[@key='DatabaseName']").Value
    $CredentialType = $customConfig.SelectSingleNode("//appSettings/add[@key='ClientServicesCredentialType']").Value
    $databaseServer = "$containerName"
    if ($databaseInstance) { $databaseServer += "\$databaseInstance" }

    New-DesktopShortcut -Name "$containerName Windows Client" -TargetPath "$WinClientFolder\Microsoft.Dynamics.Nav.Client.exe"
    New-DesktopShortcut -Name "$containerName CSIDE" -TargetPath "$WinClientFolder\finsql.exe" -Arguments "servername=$databaseServer, Database=$databaseName, ntauthentication=yes"
}
New-DesktopShortcut -Name "$containerName Command Prompt" -TargetPath "CMD.EXE" -IconLocation "C:\Program Files\Docker\docker.exe, 0" -Arguments "/C docker.exe exec -it $containerName cmd"
New-DesktopShortcut -Name "$containerName PowerShell Prompt" -TargetPath "CMD.EXE" -IconLocation "C:\Program Files\Docker\docker.exe, 0" -Arguments "/C docker.exe exec -it $containerName powershell -noexit c:\run\prompt.ps1"
New-DesktopShortcut -Name "PowerShell ISE" -TargetPath "C:\Windows\system32\WindowsPowerShell\v1.0\powershell_ise.exe" -WorkingDirectory "c:\demo"
New-DesktopShortcut -Name "Command Prompt" -TargetPath "C:\Windows\system32\cmd.exe" -WorkingDirectory "c:\demo"
New-DesktopShortcut -Name "Nav Container Helper" -TargetPath "powershell.exe" -Arguments "-noexit ""& { Write-NavContainerHelperWelcomeText }""" -WorkingDirectory c:\demo

if ($firsttime) {

    $setupScript = (Join-Path $PSScriptRoot "Setup$style.ps1")
    if (Test-Path $setupScript) {
        . $setupScript
    }
}

Log -color Green "Desktop setup complete!"
