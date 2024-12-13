ARG baseimage

FROM $baseimage

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

RUN iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1')); \
    choco feature enable -n allowGlobalConfirmation; \
    choco install docker-cli --no-progress; \
    choco install 7zip --no-progress; \
    choco install git --force --params "/NoAutoCrlf" --no-progress; \
    choco install gh --no-progress; \
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; \
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.208 -Force -WarningAction Ignore | Out-Null; \
    Install-Module powershellget -RequiredVersion 2.2.5 -force; \
    Import-Module powershellget -RequiredVersion 2.2.5; \
    Install-Module az -Force

COPY start.ps1 .

CMD .\start.ps1