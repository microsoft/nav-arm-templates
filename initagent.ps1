Set-ExecutionPolicy -ExecutionPolicy unrestricted -Force

Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 | Out-Null
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 | Out-Null

Install-Module -Name navcontainerhelper -Force
Import-Module -Name navcontainerhelper -DisableNameChecking

Install-module DockerMsftProvider -Force
Install-Package -Name docker -ProviderName DockerMsftProvider -Force

Restart-Computer -force
