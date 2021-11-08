. (Get-Item "C:\src\github\Microsoft\navcontainerhelper\*ContainerHelper.ps1").FullName -exportTelemetryFunctions

$VerbosePreference = "Continue"
$ErrorActionPreference = "stop"
$ConfirmPreference = "none"

if (!($licenseFileSecret)) {
    Get-AzKeyVaultSecret -VaultName "BuildVariables" | % {
        Write-Host $_.Name
        Set-Variable -Name "$($_.Name)Secret" -Value (Get-AzKeyVaultSecret -VaultName "BuildVariables" -Name $_.Name)
    }
}

# My subscriptions
$FreddysSubscription = "97d6b765-89fc-40e9-b253-baee2b19d6db"
$subscriptionId = $FreddysSubscription

try {
    Set-AzContext -Subscription $subscriptionId
} catch {
    Connect-AzAccount -Environment AzureCloud -TenantId 'd5c7cb1f-b4df-4224-b710-522adc1f049c'
    Set-AzContext -Subscription $subscriptionId
}

$remotedesktopaccess = "-"

$getnavProperties = @{ 
    "artifactUrl" = "bcartifacts/onprem/14/w1/latest"
    "autoShutdown" = "Enabled"
    "includeCSIDE" = "No"
    "enableSymbolLoading" = "No"
}
$getnavextProperties = @{
    "artifactUrl" = "bcartifacts/onprem/14.0.29537.31096/nl/closest"
    "winRmAccess" = "$remotedesktopaccess"
    "StorageAccountType" = "Premium_LRS"
    "includeCSIDE" = "Yes"
    "enableSymbolLoading" = "Yes"
    "requestToken" = $PasswordSecret.SecretValue | Get-PlainText
}
$getbcProperties = @{
    "artifactUrl" = "bcartifacts/sandbox//dk/latest"
}
$getbcextProperties = @{
    "artifactUrl" = "bcinsider/sandbox//us/latest/$($InsiderSasTokenSecret.SecretValue | Get-PlainText)"
    "winRmAccess" = "$remotedesktopaccess"
    "StorageAccountType" = "Premium_LRS"
    "includeAL" = "Yes"
    "SQLServerType" = "SQLDeveloper"
    "CreateStorageQueue" = "Yes"
    "FinalSetupScriptUrl" = "https://raw.githubusercontent.com/microsoft/nav-arm-templates/dev/additional-install.ps1"
}

$licensefile = $licenseFileSecret.SecretValue | Get-PlainText

$username = "student"
$vmSize = "Standard_D4s_v3"
$oss = @("Windows Server 2022","Windows Server 2019","Windows Server 2019 with Containers")
$vmPrefix = "fk"
$jsons = @('getbc','getbcext','getnav','getnavext')
$traefiks = @('Yes','No')
$branch = "dev"

$password = $PasswordSecret.SecretValue | Get-PlainText
$resLocation = "West Europe"
$credential = New-Object pscredential $username, $PasswordSecret.SecretValue
$pair ="$($UserName):$($Password)"
$bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
$base64 = [System.Convert]::ToBase64String($bytes)
$basicAuthValue = "Basic $base64"
$headers = @{ Authorization = $basicAuthValue }
$authParam = @{ "headers" = $headers }

#throw "init done"

$oss | ForEach-Object {
    $operatingSystem = $_
    $osp = $operatingSystem[$operatingSystem.Length-1]

    $traefiks | ForEach-Object {
        $AddTraefik = $_
    
        $jsons | % {
        
            $tp = "bc"
            if ("$_".StartsWith('getnav')) {
                $tp = "nav"
            }
        
            $ext = ("$_".EndsWith('ext'))
        
            $traefik = "n"
            if ($AddTraefik -eq "Yes") {
                $traefik = "t"
            }
        
            $vmname = "$vmPrefix$traefik$osp$_"
            $resgroup = "$vmName"
        
            # ARM template
            $templateUri = "https://raw.githubusercontent.com/microsoft/nav-arm-templates/$branch/$($_).json"
            
            # Setup parameter array for ARM template
            $Parameters = New-Object -TypeName Hashtable
            $Parameters.Add("vmName", $vmName)
            $Parameters.Add("vmSize", $vmSize)
            $Parameters.Add("OperatingSystem", $operatingSystem)
            $Parameters.Add("accepteula", "Yes")
            $Parameters.Add("remotedesktopaccess", $remotedesktopaccess)
            $Parameters.Add("vmAdminUsername", $username)
            $Parameters.Add("$($tp)AdminUsername", $username)
            $Parameters.Add("licensefileuri", $licensefile)
            $Parameters.Add("adminPassword", (ConvertTo-SecureString -String $password -AsPlainText -Force))
    
            $properties = Get-Variable "$($_)Properties"
            $properties.Value.GetEnumerator() | % {
                $Parameters.Add($_.Name, $_.Value)
            }
    
            $Parameters.Add("contactemailforletsencrypt", "fk@freddy.dk")
            $Parameters.Add("RunWindowsUpdate", "No")
            $Parameters.Add("AddTraefik", $AddTraefik)
            
            # GO!
            $resourceGroup = Get-AzResourceGroup -name $resGroup -ErrorAction Ignore
            if ($resourceGroup) {
                Write-Host "Removing Resource Group $resGroup"
                Remove-AzResourceGroup -Name $resGroup -Force
            }
            $resourceGroup = New-AzResourceGroup -Name $resGroup -Location $resLocation -Force
            $err = $resourceGroup | Test-AzResourceGroupDeployment -TemplateUri $templateUri -TemplateParameterObject $Parameters
            if ($err) {
                $err
                throw "stop"
            }
            $resourceGroup | New-AzResourceGroupDeployment -TemplateUri $templateUri -TemplateParameterObject $Parameters -Name $vmName -ErrorAction Ignore
        }
    }
}

get-date

throw "Run the following in 1 hour"

$oss | ForEach-Object {
    $operatingSystem = $_
    $osp = $operatingSystem[$operatingSystem.Length-1]
    $traefiks | ForEach-Object {
        $AddTraefik = $_
        $traefik = "n"
        if ($AddTraefik -eq "Yes") {
            $traefik = "t"
        }
    
        $jsons | ForEach-Object {
        
            $vmname = "$vmPrefix$traefik$osp$_"
    
            $url = "$($vmName).westeurope.cloudapp.azure.com"
            if ($AddTraefik -eq "Yes") {
                $landingPageUrl = "http://$($url):8180"
            }
            else {
                $landingPageUrl = "http://$url"
            }
        
            $landingPage = Invoke-WebRequest -Uri $landingPageUrl
            $landingPage.Links | Where-Object {$_.href -like “http*”} | ForEach-Object {
        
                if ($_.innerText -eq "Web Client") {
                    $LoginPage = Invoke-WebRequest -Uri $_.href -UseBasicParsing
                    $userNameField = $LoginPage.InputFields | Where-Object { $_.name -eq "Username" }
                    $PasswordField = $LoginPage.InputFields | Where-Object { $_.name -eq "Password" }
                    if ((-not $userNameField) -or (-not $passwordField)) {
                        throw "Web Client login page not found"
                    }
                }
                elseif ($_.innerText -eq "View SOAP Web Services") {
                    $SoapResult = Invoke-WebRequest -Method Get -Uri $_.href.Replace('s//s','s/s') @AuthParam
                    [xml]$xml = $SoapResult.Content
                    $systemService = $xml.discovery.contractRef | Where-Object { $_.ref -like "*systemservice*" }
                    if (-not $systemService) {
                        throw "Soap not exposed correctly"
                    }
                }
                elseif ($_.innerText -eq "View OData Web Services") {
                    $ODataResult = Invoke-RestMethod -Method Get -Uri $_.href @AuthParam
                    if (-not $ODataResult.service.workspace.collection.href -contains "Company") {
                        throw "OData not exposed correctly"
                    }
                }
                elseif ($_.innerText.EndsWith("api/v1.0/companies")) {
                    $ApiResult = Invoke-RestMethod -Method Get -Uri $_.href @AuthParam
                    if (-not $ApiResult.value.name -like "CRONUS*") {
                        throw "API doesn't include CRONUS company"
                    }
        
                }
                elseif ($_.innerText.EndsWith(".vsix")) {
                    Download-File -sourceUrl $_.href -destinationFile "c:\temp\$($_.innerText).vsix"
                }
            }
        }
    }
}

#'ngetbcext','tgetbcext','ngetnavext','tgetnavext' | % {
#
#    $publicDnsName = "$VmPrefix$_.westeurope.cloudapp.azure.com"
#    $selfSigned = "$_".startswith("t")
#    
#    if ($selfSigned) {
#        $sessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck
#    }
#    else {
#        $sessionOption = New-PSSessionOption
#    }
#    
#    Invoke-Command -ComputerName $publicDnsName -Credential $credential -UseSSL -SessionOption $sessionOption -ScriptBlock {
#    
#        $hostname = hostname
#        Write-Output "Hostname : $hostname"
#    
#    }
#}

throw "Next lines removes the VMs"

$oss | ForEach-Object {
    $operatingSystem = $_
    $osp = $operatingSystem[$operatingSystem.Length-1]
    $traefiks | ForEach-Object {
        $AddTraefik = $_
    
        $jsons | % {
        
            $tp = "bc"
            if ("$_".StartsWith('getnav')) {
                $tp = "nav"
            }
        
            $ext = ("$_".EndsWith('ext'))
        
            $traefik = "n"
            if ($AddTraefik -eq "Yes") {
                $traefik = "t"
            }
        
            $vmname = "$vmPrefix$traefik$osp$_"
            $resgroup = "$vmName"
        
            $resourceGroup = Get-AzResourceGroup -name $resGroup -ErrorAction Ignore
            if ($resourceGroup) {
                Write-Host "Removing Resource Group $resGroup"
                Remove-AzResourceGroup -Name $resGroup -Force -AsJob
            }
        }
    }
}
