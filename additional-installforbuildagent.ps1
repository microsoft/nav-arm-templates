if (!(Test-Path function:AddToStatus)) {
  function AddToStatus([string]$line, [string]$color = "Gray") {
    ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt" -Force -ErrorAction SilentlyContinue
    Write-Host -ForegroundColor $color $line 
  }
}

Install-Module az -force

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

AddToStatus "GitHub CLI"
choco install gh

AddToStatus "PowerShell 7"
choco install pwsh -y

AddToStatus "Microsoft Visual C++ Redistributable for Visual Studio 2015-2022 14.36.32532"
choco install vcredist140 -y

AddToStatus "Microsoft dotnet"
choco install dotnet -y

AddToStatus "Microsoft dotnet SDK"
choco install dotnet-sdk -y

AddToStatus "Checking dotnet nuget list sources"
$sources = dotnet nuget list source
if (!($sources | where-Object { $_.Trim() -eq 'https://api.nuget.org/v3/index.json' })) {
  AddToStatus "Adding nuget.org source"
  dotnet nuget add source https://api.nuget.org/v3/index.json --name nuget.org
}
