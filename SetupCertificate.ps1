$ContactEMailForLetsEncrypt = $env:ContactEMailForLetsEncrypt

mkdir c:\inetpub\wwwroot\http | Out-Null
new-website -name http -port 80 -physicalpath c:\inetpub\wwwroot\http

Write-Host "Installing NuGet PackageProvider"
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

Write-Host "Installing ACMESharp PowerShell modules"
Install-Module -Name ACMESharp -AllowClobber -force
Install-Module -Name ACMESharp.Providers.IIS -force
Import-Module ACMESharp
Enable-ACMEExtensionModule -ModuleName ACMESharp.Providers.IIS

Write-Host "Install modules and dependencies for LetsEncrypt"
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name ACMESharp -Force
Install-Module -Name ACMESharp.Providers.IIS -Force
Import-Module ACMESharp
Enable-ACMEExtensionModule -ModuleName ACMESharp.Providers.IIS

Write-Host "Initializing ACMEVault"
Initialize-ACMEVault
            
Write-Host "Register Contact EMail address and accept Terms Of Service"
New-ACMERegistration -Contacts "mailto:$ContactEMailForLetsEncrypt" -AcceptTos
            
Write-Host "Creating new dns Identifier"
$dnsAlias = "dnsAlias"
New-ACMEIdentifier -Dns $publicDnsName -Alias $dnsAlias

Write-Host "Performing Lets Encrypt challenge to default web site"
Complete-ACMEChallenge -IdentifierRef $dnsAlias -ChallengeType http-01 -Handler iis -HandlerParameters @{ WebSiteRef = 'http' }
Submit-ACMEChallenge -IdentifierRef $dnsAlias -ChallengeType http-01
sleep -s 60
Update-ACMEIdentifier -IdentifierRef $dnsAlias

Write-Host "Requesting certificate"
$certAlias = "certAlias"
$certificatePfxPassword = [GUID]::NewGuid().ToString()
$certificatePfxFile = Join-Path $runPath "certificate.pfx"
New-ACMECertificate -Generate -IdentifierRef $dnsAlias -Alias $certAlias
Submit-ACMECertificate -CertificateRef $certAlias
Update-ACMECertificate -CertificateRef $certAlias
Get-ACMECertificate -CertificateRef $certAlias -ExportPkcs12 $certificatePfxFile -CertificatePassword $certificatePfxPassword

$certificatePemFile = Join-Path $runPath "certificate.pem"
Remove-Item -Path $certificatePemFile -Force -ErrorAction Ignore
Get-ACMECertificate -CertificateRef $certAlias -ExportKeyPEM $certificatePemFile

$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certificatePfxFile, $certificatePfxPassword)
$certificateThumbprint = $cert.Thumbprint

$dnsidentity = $cert.GetNameInfo("SimpleName",$false)
if ($dnsidentity.StartsWith("*")) {
    $dnsidentity = $dnsidentity.Substring($dnsidentity.IndexOf(".")+1)
}
