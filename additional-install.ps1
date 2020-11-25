if (!(Test-Path function:AddToStatus)) {
  function AddToStatus([string]$line, [string]$color = "Gray") {
    ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt" -Force -ErrorAction SilentlyContinue
    Write-Host -ForegroundColor $color $line 
  }
}

#Install Choco
AddToSTatus "Install Choco"
Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
choco feature enable -n allowGlobalConfirmation

AddToStatus "Install git"
choco install git --force --params "/NoAutoCrlf"

AddToStatus "Install Edge"
choco install microsoft-edge

AddToStatus "Install Chrome"
choco install googlechrome

AddToStatus "Install firefox"
choco install firefox

#AddToStatus "Install Office 365 Business"
#choco install office365business

#AddToStatus "Install PowerBI Desktop"
#choco install powerbi

#Add VSCode Extensions
"eamodio.gitlens", "ms-vscode.PowerShell", "heaths.vscode-guid", "github.vscode-pull-request-github", "formulahendry.docker-explorer" | % {
    AddToStatus "Install VSCode Extension: $_"
    code --install-extension $_
}

. "C:\DEMO\Settings.ps1"
& "C:\Program Files\GIT\bin\git.exe" config --global core.safecrlf false
& "C:\Program Files\GIT\bin\git.exe" config --global user.email "$($vmAdminUsername)@$($hostName)"
& "C:\Program Files\GIT\bin\git.exe" config --global user.name "$vmAdminUsername"
