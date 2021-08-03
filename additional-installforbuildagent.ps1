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

AddToStatus "VSCode"
choco install vscode

AddToStatus "7zip"
choco install 7zip
