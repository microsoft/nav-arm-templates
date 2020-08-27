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

AddToStatus -color Green "Setting up Desktop Experience"

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
    
    AddToStatus "Installing Visual Studio Code (this might take a few minutes)"
    $setupParameters = “/VerySilent /CloseApplications /NoCancel /LoadInf=""c:\demo\vscode.inf"" /MERGETASKS=!runcode"
    Start-Process -FilePath $Filename -WorkingDirectory $Folder -ArgumentList $setupParameters -Wait -Passthru | Out-Null

    AddToStatus "Downloading samples"
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

$codeProcess = get-process Code -ErrorAction SilentlyContinue
if ($codeProcess) {
    AddToStatus "WARNING: VS Code is running, skipping .vsix installation"
}
elseif (Test-Path "C:\ProgramData\bccontainerhelper\Extensions\$containerName\*.vsix") {
    $vsixFileName = (Get-Item "C:\ProgramData\bccontainerhelper\Extensions\$containerName\*.vsix").FullName
    if ($vsixFileName -ne "") {
    
        AddToStatus "Installing .vsix"
        try { & $codeCmd @('--install-extension', $VsixFileName) | Out-Null } catch {}
    
        $username = [Environment]::UserName
        if (Test-Path -path "c:\Users\Default\.vscode" -PathType Container -ErrorAction Ignore) {
            if (!(Test-Path -path "c:\Users\$username\.vscode" -PathType Container -ErrorAction Ignore)) {
                Copy-Item -Path "c:\Users\Default\.vscode" -Destination "c:\Users\$username\" -Recurse -Force -ErrorAction Ignore
            }
        }
    }
}

if ($disableVsCodeUpdate) {
    $vsCodeSettingsFile = Join-Path ([Environment]::GetFolderPath("ApplicationData")) "Code\User\settings.json"
    '{
        "update.channel": "none"
    }' | Set-Content $vsCodeSettingsFile
}

AddToStatus "Creating Desktop Shortcuts"
if ($AddTraefik -eq "Yes") {
    $landingPageUrl = "http://${publicDnsName}:8180"
}
else {
    $landingPageUrl = "http://${publicDnsName}"
}
New-DesktopShortcut -Name "Landing Page" -TargetPath $landingPageUrl -IconLocation "C:\Program Files\Internet Explorer\iexplore.exe, 3"
New-DesktopShortcut -Name "Visual Studio Code" -TargetPath $codeExe
New-DesktopShortcut -Name "PowerShell ISE" -TargetPath "C:\Windows\system32\WindowsPowerShell\v1.0\powershell_ise.exe" -WorkingDirectory "c:\demo"
New-DesktopShortcut -Name "Command Prompt" -TargetPath "C:\Windows\system32\cmd.exe" -WorkingDirectory "c:\demo"
New-DesktopShortcut -Name "Nav Container Helper" -TargetPath "c:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Arguments "-noexit ""& { Write-BcContainerHelperWelcomeText }""" -WorkingDirectory "C:\ProgramData\bccontainerhelper"

AddToStatus -color Green "Desktop setup complete!"
