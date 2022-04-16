$ErrorActionPreference = "Stop"
$WarningActionPreference = "Continue"

$ComputerInfo = Get-ComputerInfo
$WindowsInstallationType = $ComputerInfo.WindowsInstallationType
$WindowsProductName = $ComputerInfo.WindowsProductName

try {

function AddToStatus([string]$line, [string]$color = "Gray") {
    ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt" -Force -ErrorAction SilentlyContinue
}

AddToStatus "SetupVm, User: $env:USERNAME"

function DockerDo {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$imageName,
        [ValidateSet('run','start','pull','restart','stop')]
        [string]$command = "run",
        [switch]$accept_eula,
        [switch]$accept_outdated,
        [switch]$detach,
        [switch]$silent,
        [string[]]$parameters = @()
    )

    if ($accept_eula) {
        $parameters += "--env accept_eula=Y"
    }
    if ($accept_outdated) {
        $parameters += "--env accept_outdated=Y"
    }
    if ($detach) {
        $parameters += "--detach"
    }

    $result = $true
    $arguments = ("$command "+[string]::Join(" ", $parameters)+" $imageName")
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "docker.exe"
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.CreateNoWindow = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = $arguments
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null

    $outtask = $null
    $errtask = $p.StandardError.ReadToEndAsync()
    $out = ""
    $err = ""
    
    do {
        if ($null -eq $outtask) {
            $outtask = $p.StandardOutput.ReadLineAsync()
        }
        $outtask.Wait(100) | Out-Null
        if ($outtask.IsCompleted) {
            $outStr = $outtask.Result
            if ($null -eq $outStr) {
                break
            }
            if (!$silent) {
                AddToStatus $outStr
            }
            $out += $outStr
            $outtask = $null
            if ($outStr.StartsWith("Please login")) {
                $registry = $imageName.Split("/")[0]
                if ($registry -eq "bcinsider.azurecr.io") {
                    AddToStatus -color red "You need to login to $registry prior to pulling images. Get credentials through the ReadyToGo program on Microsoft Collaborate."
                } else {
                    AddToStatus -color red "You need to login to $registry prior to pulling images."
                }
                break
            }
        } elseif ($outtask.IsCanceled) {
            break
        } elseif ($outtask.IsFaulted) {
            break
        }
    } while(!($p.HasExited))
    
    $err = $errtask.Result
    $p.WaitForExit();

    if ($p.ExitCode -ne 0) {
        $result = $false
        if (!$silent) {
            $err = $err.Trim()
            if ("$error" -ne "") {
                AddToStatus -color red $error
            }
            AddToStatus -color red "ExitCode: "+$p.ExitCode
            AddToStatus -color red "Commandline: docker $arguments"
        }
    }
    return $result
}

if (Test-Path -Path "C:\demo\*\BcContainerHelper.psm1") {
    $module = Get-Item -Path "C:\demo\*\BcContainerHelper.psm1"
    Import-module $module.FullName -DisableNameChecking
} else {
    Import-Module -name bccontainerhelper -DisableNameChecking
}

. (Join-Path $PSScriptRoot "settings.ps1")

if ($AddTraefik -eq "Yes") {

    if (Test-Path "c:\myfolder\certificate.pfx") {
        AddToStatus -color Red "Certificate specified, cannot add Traefik"
        $AddTraefik = "No"
    }

    if (-not $ContactEMailForLetsEncrypt) {
        AddToStatus -color Red "Contact EMail for LetsEncrypt not specified, cannot add Traefik"
        $AddTraefik = "No"
    }

    if ($clickonce -eq "Yes") {
        AddToStatus -color Red "ClickOnce specified, cannot add Traefik"
        $AddTraefik = "No"
    }

    if ($AddTraefik -eq "Yes") {

        if ([System.Environment]::OSVersion.Version.Build -gt 17763 -and $bcContainerHelperConfig.TraefikImage.EndsWith('-1809')) {
            $bestGenericImage = Get-BestGenericImageName
            $servercoreVersion = $bestGenericImage.Split(':')[1]
            $serverCoreImage = "mcr.microsoft.com/windows/servercore:$serverCoreVersion"

            AddToStatus "Pulling $serverCoreImage (this might take some time)"
            if (!(DockerDo -imageName $serverCoreImage -command pull))  {
                throw "Error pulling image"
            }
            $traefikVersion = "v1.7.33"

            New-Item 'C:\DEMO\Traefik' -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
            Set-Location 'C:\DEMO\Traefik'

            @"
FROM $serverCoreImage
SHELL ["powershell", "-Command", "`$ErrorActionPreference = 'Stop'; `$ProgressPreference = 'SilentlyContinue';"]

RUN Invoke-WebRequest \
    -Uri "https://github.com/traefik/traefik/releases/download/$traefikVersion/traefik_windows-amd64.exe" \
    -OutFile "/traefik.exe"

EXPOSE 80
ENTRYPOINT [ "/traefik" ]

# Metadata
LABEL org.opencontainers.image.vendor="Traefik Labs" \
    org.opencontainers.image.url="https://traefik.io" \
    org.opencontainers.image.title="Traefik" \
    org.opencontainers.image.description="A modern reverse-proxy" \
    org.opencontainers.image.version="$traefikVersion" \
    org.opencontainers.image.documentation="https://docs.traefik.io"
"@ | Set-Content 'DOCKERFILE'

            docker build --tag mytraefik .

            $bcContainerHelperConfig.TraefikImage = "mytraefik:latest"
        }

        AddToStatus "Setup Traefik container"
        Setup-TraefikContainerForNavContainers -overrideDefaultBinding -PublicDnsName $publicDnsName -ContactEMailForLetsEncrypt $ContactEMailForLetsEncrypt
    }
    else {
        Get-VariableDeclaration -name "AddTraefik" | Add-Content $settingsScript
    }
}

if ("$ContactEMailForLetsEncrypt" -ne "" -and $AddTraefik -ne "Yes") {
if (-not (Get-InstalledModule ACME-PS -ErrorAction SilentlyContinue)) {

    AddToStatus "Installing ACME-PS PowerShell Module"
    Install-Module -Name ACME-PS -RequiredVersion "1.5.2" -AllowPrerelease -Force

    AddToStatus "Using Lets Encrypt certificate"
    # Use Lets encrypt
    # If rate limits are hit, log an error and revert to Self Signed
    try {
        $plainPfxPassword = [GUID]::NewGuid().ToString()
        $certificatePfxFilename = "c:\ProgramData\bccontainerhelper\certificate.pfx"
        New-LetsEncryptCertificate -ContactEMailForLetsEncrypt $ContactEMailForLetsEncrypt -publicDnsName $publicDnsName -CertificatePfxFilename $certificatePfxFilename -CertificatePfxPassword (ConvertTo-SecureString -String $plainPfxPassword -AsPlainText -Force)

        # Override SetupCertificate.ps1 in container
        ('if ([int](get-item "C:\Program Files\Microsoft Dynamics NAV\*").Name -le 100) {
    Write-Host "WARNING: This version doesn''t support LetsEncrypt certificates, reverting to self-signed"
    . "C:\run\SetupCertificate.ps1"
}
else {
    . (Join-Path $PSScriptRoot "InstallCertificate.ps1")
}
') | Set-Content "c:\myfolder\SetupCertificate.ps1"


        ('$CertificatePfxPassword = ConvertTo-SecureString -String "'+$plainPfxPassword+'" -AsPlainText -Force
$certificatePfxFile = "'+$certificatePfxFilename+'"
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certificatePfxFile, $certificatePfxPassword)
$certificateThumbprint = $cert.Thumbprint
Write-Host "Certificate File Thumbprint $certificateThumbprint"
if (!(Get-Item Cert:\LocalMachine\my\$certificateThumbprint -ErrorAction SilentlyContinue)) {
    Write-Host "Import Certificate to LocalMachine\my"
    Import-PfxCertificate -FilePath $certificatePfxFile -CertStoreLocation cert:\localMachine\my -Password $certificatePfxPassword | Out-Null
}
$dnsidentity = $cert.GetNameInfo("SimpleName",$false)
if ($dnsidentity.StartsWith("*")) {
    $dnsidentity = $dnsidentity.Substring($dnsidentity.IndexOf(".")+1)
}
') | Set-Content "c:\myfolder\InstallCertificate.ps1"

        # Create RenewCertificate script
        ('$CertificatePfxPassword = ConvertTo-SecureString -String "'+$plainPfxPassword+'" -AsPlainText -Force
$certificatePfxFile = "'+$certificatePfxFilename+'"
$publicDnsName = "'+$publicDnsName+'"
Renew-LetsEncryptCertificate -publicDnsName $publicDnsName -certificatePfxFilename $certificatePfxFile -certificatePfxPassword $certificatePfxPassword
Start-Sleep -seconds 30
Restart-NavContainer -containerName "'+$containerName+'" -renewBindings
') | Set-Content "c:\demo\RenewCertificate.ps1"

    } catch {
        AddToStatus -color Red $_.Exception.Message
        AddToStatus -color Red "Reverting to Self Signed Certificate"
    }

}
}

if ("$WinRmAccess" -ne "") {
    if (Test-Path "c:\myfolder\InstallCertificate.ps1") {
        # Using trusted certificate - install on host
        . "c:\myfolder\InstallCertificate.ps1"
    }
    elseif (Test-Path "c:\myfolder\SetupCertificate.ps1") {
        # Using trusted certificate - install on host
        . "c:\myfolder\SetupCertificate.ps1"
    }
    else {
        $certificateThumbprint = (New-SelfSignedCertificate -DnsName $publicDnsName -CertStoreLocation Cert:\LocalMachine\My).Thumbprint   
    }

    AddToStatus "Enabling PS Remoting"
    Enable-PSRemoting -Force   

    AddToStatus "Creating Firewall rule for WinRM"
    New-NetFirewallRule -Name "WinRM HTTPS" -DisplayName "WinRM HTTPS" -Enabled True -Profile "Any" -Action "Allow" -Direction "Inbound" -LocalPort 5986 -Protocol "TCP"    

    AddToStatus "Creating WinRM listener"
    $cmd = "winrm create winrm/config/Listener?Address=*+Transport=HTTPS @{Hostname=""$publicDnsName""; CertificateThumbprint=""$certificateThumbprint""}" 
    cmd.exe /C $cmd   
}

if ($sqlServerType -eq "SQLDeveloper") {
    AddToStatus "Installing SQL Server Developer edition"

    $securePassword = ConvertTo-SecureString -String $adminPassword -Key $passwordKey
    $dbCredential = New-Object System.Management.Automation.PSCredential('sa', $securePassword)

    cd c:\demo
    $exeUrl = "https://go.microsoft.com/fwlink/?linkid=840945"
    $boxUrl = "https://go.microsoft.com/fwlink/?linkid=840944"
    $sqlExe = "c:\demo\SQL.exe"
    $sqlBox = "c:\demo\SQL.box"
    Download-File -sourceUrl $exeUrl -destinationFile $sqlExe
    Download-File -sourceUrl $boxUrl -destinationFile $sqlBox
    Start-Process -Wait -FilePath $sqlExe -ArgumentList /qs, /x:setup 
    .\setup\setup.exe /q /ACTION=Install /INSTANCENAME=MSSQLSERVER /FEATURES=SQLEngine /UPDATEENABLED=0 /SQLSVCACCOUNT='NT AUTHORITY\NETWORK SERVICE' /SQLSYSADMINACCOUNTS='BUILTIN\ADMINISTRATORS' /TCPENABLED=1 /NPENABLED=0 /IACCEPTSQLSERVERLICENSETERMS
    Remove-Item -Recurse -Force $sqlExe, $sqlBox, setup
    stop-service MSSQLSERVER
    set-itemproperty -path 'HKLM:\software\microsoft\microsoft sql server\mssql14.MSSQLSERVER\mssqlserver\supersocketnetlib\tcp\ipall' -name tcpdynamicports -value ''
    set-itemproperty -path 'HKLM:\software\microsoft\microsoft sql server\mssql14.MSSQLSERVER\mssqlserver\supersocketnetlib\tcp\ipall' -name tcpport -value 1433
    set-itemproperty -path 'HKLM:\software\microsoft\microsoft sql server\mssql14.MSSQLSERVER\mssqlserver\' -name LoginMode -value 2
    start-service MSSQLSERVER
    
    $sqlcmd = "ALTER LOGIN sa with password='" + ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($dbcredential.Password)).Replace('"','""').Replace('''','''''')) + "',CHECK_POLICY = OFF;ALTER LOGIN sa ENABLE;"
    Invoke-SqlCmd -ServerInstance "localhost" -QueryTimeout 0 -ErrorAction Stop -Query $sqlcmd

    New-NetFirewallRule -DisplayName "SQLDeveloper" -Direction Inbound -LocalPort 1433 -Protocol tcp -Action Allow
}


AddToStatus "Starting docker"
start-service docker

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls -bor [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls12

AddToStatus "Enabling File Download in IE"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3" -Name "1803" -Value 0
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3" -Name "1803" -Value 0

AddToStatus "Enabling Font Download in IE"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3" -Name "1604" -Value 0
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3" -Name "1604" -Value 0

AddToStatus "Show hidden files and file types"
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'  -Name "Hidden"      -value 1
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'  -Name "HideFileExt" -value 0

if ($WindowsInstallationType -eq "Server") {
    AddToStatus "Disabling Server Manager Open At Logon"
    New-ItemProperty -Path "HKCU:\Software\Microsoft\ServerManager" -Name "DoNotOpenServerManagerAtLogon" -PropertyType "DWORD" -Value "0x1" –Force | Out-Null
}

AddToStatus "Add Import bccontainerhelper to PowerShell profile"
$winPsFolder = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "WindowsPowerShell"
New-Item $winPsFolder -ItemType Directory -Force -ErrorAction Ignore | Out-Null

'if (Test-Path -Path "C:\demo\*\BcContainerHelper.psm1") {
    $module = Get-Item -Path "C:\demo\*\BcContainerHelper.psm1"
    Import-module $module.FullName -DisableNameChecking
} else {
    Import-Module -name bccontainerhelper -DisableNameChecking
}' | Set-Content (Join-Path $winPsFolder "Profile.ps1")

AddToStatus "Adding Landing Page to Startup Group"
if ($AddTraefik -eq "Yes") {
    $landingPageUrl = "http://${publicDnsName}:8180"
}
else {
    $landingPageUrl = "http://${publicDnsName}"
}
New-DesktopShortcut -Name "Landing Page" -TargetPath "C:\Program Files\Internet Explorer\iexplore.exe" -Shortcuts "CommonStartup" -Arguments $landingPageUrl
if ($style -eq "devpreview") {
    New-DesktopShortcut -Name "Modern Dev Tools" -TargetPath "C:\Program Files\Internet Explorer\iexplore.exe" -Shortcuts "CommonStartup" -Arguments "http://aka.ms/moderndevtools"
}

if ($artifactUrl -ne "") {
    $imageName = Get-BestGenericImageName
    AddToStatus "Pulling $imageName (this might take some time)"
    if (!(DockerDo -imageName $imageName -command pull))  {
        throw "Error pulling image"
    }
}
else {
    $imageName = ""
    $navDockerImage.Split(',') | Where-Object { $_ } | ForEach-Object {
        $registry = $_.Split('/')[0]
        if (($registry -ne "microsoft") -and ($registryUsername -ne "") -and ($registryPassword -ne "")) {
            AddToStatus "Logging in to $registry"
            docker login "$registry" -u "$registryUsername" -p "$registryPassword"
        }
    
        $imageName = Get-BestNavContainerImageName -imageName $_
    
        AddToStatus "Pulling $imageName (this might take ~30 minutes)"
        if (!(DockerDo -imageName $imageName -command pull))  {
            throw "Error pulling image"
        }
    }
}

AddToStatus "Installing Visual C++ Redist"
$vcRedistUrl = "https://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x86.exe"
$vcRedistFile = "C:\DOWNLOAD\vcredist_x86.exe"
Download-File -sourceUrl $vcRedistUrl -destinationFile $vcRedistFile
Start-Process $vcRedistFile -argumentList "/q" -wait

AddToStatus "Installing SQL Native Client"
$sqlncliUrl = "https://download.microsoft.com/download/3/A/6/3A632674-A016-4E31-A675-94BE390EA739/ENU/x64/sqlncli.msi"
$sqlncliFile = "C:\DOWNLOAD\sqlncli.msi"
Download-File -sourceUrl $sqlncliUrl -destinationFile $sqlncliFile
Start-Process "C:\Windows\System32\msiexec.exe" -argumentList "/i $sqlncliFile ADDLOCAL=ALL IACCEPTSQLNCLILICENSETERMS=YES /qn" -wait

AddToStatus "Installing OpenXML 2.5"
$openXmlUrl = "https://download.microsoft.com/download/5/5/3/553C731E-9333-40FB-ADE3-E02DC9643B31/OpenXMLSDKV25.msi"
$openXmlFile = "C:\DOWNLOAD\OpenXMLSDKV25.msi"
Download-File -sourceUrl $openXmlUrl -destinationFile $openXmlFile
Start-Process $openXmlFile -argumentList "/qn /q /passive" -wait

$beforeContainerSetupScript = (Join-Path $PSScriptRoot "BeforeContainerSetupScript.ps1")
if (Test-Path $beforeContainerSetupScript) {
    AddToStatus "Running beforeContainerSetupScript"
    . $beforeContainerSetupScript
}

. "c:\demo\SetupNavContainer.ps1"
. "c:\demo\SetupDesktop.ps1"

$finalSetupScript = (Join-Path $PSScriptRoot "FinalSetupScript.ps1")
if (Test-Path $finalSetupScript) {
    AddToStatus "Running FinalSetupScript"
    . $finalSetupScript
}

if (Get-ScheduledTask -TaskName SetupStart -ErrorAction Ignore) {
    schtasks /DELETE /TN SetupStart /F | Out-Null
}

if (Get-ScheduledTask -TaskName SetupVm -ErrorAction Ignore) {
    schtasks /DELETE /TN SetupVm /F | Out-Null
}

if ($RunWindowsUpdate -eq "Yes") {
    AddToStatus "Installing Windows Updates"
    install-module PSWindowsUpdate -force
    Get-WUInstall -install -acceptall -autoreboot | ForEach-Object { AddToStatus ($_.Status + " " + $_.KB + " " +$_.Title) }
    AddToStatus "Windows updates installed"
}

if (!($imageName)) {
    Remove-Item -path "c:\demo\status.txt" -Force -ErrorAction SilentlyContinue
}

shutdown -r -t 30

} catch {
    AddToStatus -Color Red -line $_.Exception.Message
    $_.ScriptStackTrace.Replace("`r`n","`n").Split("`n") | ForEach-Object { AddToStatus -Color Red -line $_ }
    throw
}
