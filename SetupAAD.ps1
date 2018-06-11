. (Join-Path $PSScriptRoot "settings.ps1")
$publicWebBaseUrl = "https://$publicDnsName/NAV/"
$secureOffice365Password = ConvertTo-SecureString -String $Office365Password -Key $passwordKey
$Office365Credential = New-Object System.Management.Automation.PSCredential($Office365UserName, $secureOffice365Password)
Create-AadAppsForNav -AadAdminCredential $Office365Credential -appIdUri $publicWebBaseUrl -IncludeExcelAadApp -IncludePowerBiAadApp
