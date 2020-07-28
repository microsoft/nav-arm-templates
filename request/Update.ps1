Param(
    [string]   $fob = "",
    [string[]] $symbols = "",
    [string[]] $apps = ""
)

$sessionParam = @{ "session" = (Get-NavContainerSession -containerName navserver -silent) }
$Path = "c:\ProgramData\BcContainerHelper"

Write-Host "Downloading .fob"
$fobFile = Join-Path $Path $fob
Get-AzureStorageBlobContent -Context $storageContext -Container $queuename -Blob $fob -Destination $fobFile -Force | Out-Null

Write-Host "Downloading symbols"
$symbols | % {
    $symbolsFile = Join-Path $Path $_
    Get-AzureStorageBlobContent -Context $storageContext -Container $queuename -Blob $_ -Destination $symbolsFile -Force | Out-Null
}

Write-Host "Downloading and uninstalling apps"
$installedApps = @()
$apps | % {
    $appFile = Join-Path $Path $_
    Get-AzureStorageBlobContent -Context $storageContext -Container $queuename -Blob $_ -Destination $appFile -Force | Out-Null
    $installedApps += Invoke-Command @sessionParam -ScriptBlock { Param($appFile)
        $installedApp = @()
        $appSpec = Get-NavAppInfo -Path $appFile 
        Get-NAVAppInfo -ServerInstance NAV -Id $appSpec.AppId | % {
            $installedApp += @{ "Name" = $_.Name; "Publisher" = $_.Publisher; "Version" = $_.Version }
            Write-Host "Uninstalling app $($_.Name)"
            Uninstall-NAVApp -ServerInstance NAV -Publisher $_.Publisher -Name $_.Name -Version $_.Version
            Unpublish-NAVApp -ServerInstance NAV -Publisher $_.Publisher -Name $_.Name -Version $_.Version
        }
        $installedApp
    } -ArgumentList $appFile

}

Invoke-Command @sessionParam -ScriptBlock { Param($fobFile)

    $serviceTierFolder = (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service").FullName
    $customConfigFile = Join-Path $serviceTierFolder "CustomSettings.config"
    [xml]$customConfig = [System.IO.File]::ReadAllText($customConfigFile)
    $databaseServer = $customConfig.SelectSingleNode("//appSettings/add[@key='DatabaseServer']").Value
    $databaseInstance = $customConfig.SelectSingleNode("//appSettings/add[@key='DatabaseInstance']").Value
    $databaseName = $customConfig.SelectSingleNode("//appSettings/add[@key='DatabaseName']").Value
    $managementServicesPort = $customConfig.SelectSingleNode("//appSettings/add[@key='ManagementServicesPort']").Value
    if ($databaseInstance) { $databaseServer += "\$databaseInstance" }
    $enableSymbolLoadingKey = $customConfig.SelectSingleNode("//appSettings/add[@key='EnableSymbolLoadingAtServerStartup']")

    Write-Host "Importing .fob"
    Import-NAVApplicationObject -Path $fobFile `
                                -DatabaseName $databaseName `
                                -DatabaseServer $databaseServer `
                                -ImportAction Overwrite `
                                -SynchronizeSchemaChanges "Force" `
                                -NavServerName localhost `
                                -NavServerInstance NAV `
                                -NavServerManagementPort "$managementServicesPort" `
                                -Confirm:$false

} -ArgumentList $fobFile

Write-Host "Publishing Symbols"
$symbols | % {
    $symbolsFile = Join-Path $Path $_

    Invoke-Command @sessionParam -ScriptBlock { Param($symbolsFile)
        $appSpec = Get-NavAppInfo -Path $symbolsFile
        if ($appSpec) {
            Write-Host "Unpublishing Symbols for $($appSpec.Name)"
            Unpublish-NAVApp -ServerInstance NAV -Publisher $appSpec.Publisher -Name $appSpec.Name
        }
        Write-Host "Publishing Symbols for $($appSpec.Name)"
        Publish-NavApp -ServerInstance NAV -Path $symbolsFile -SkipVerification -PackageType SymbolsOnly
    } -ArgumentList $symbolsFile

}

Invoke-Command @sessionParam -ScriptBlock {

    Write-Host "Synchronizing Database"
    Sync-NavTenant -ServerInstance NAV -Force

}

Write-Host "Publishing and Installing apps"
$apps | % {
    $appFile = Join-Path $Path $_

    Invoke-Command @sessionParam -ScriptBlock { Param($appFile, $installedApps)
        $appSpec = Get-NavAppInfo -Path $appFile
        Write-Host "Publishing $appFile"
        Publish-NavApp -ServerInstance NAV -Path $appFile -SkipVerification
        Write-Host "Synchronizing App"
        Sync-NavApp -ServerInstance NAV -Name $appSpec.Name -Publisher $appSpec.Publisher -Version $appSpec.Version -Mode Add -WarningAction SilentlyContinue
        
        $installedApp = $installedApps | Where-Object { $appSpec.Name -eq $_.Name -and $appSpec.Publisher -eq $_.Publisher }
        if (!($installedApp)) {
            Write-Host "Installing App $($appSpec.Name)"
            Install-NavApp -ServerInstance NAV -Name $appSpec.Name -Publisher $appSpec.Publisher -Version $appSpec.Version
        } elseif ($installedApp.version -eq $appSpec.Version) {
            Write-Host "Reinstalling App $($appSpec.Name)"
            Install-NavApp -ServerInstance NAV -Name $appSpec.Name -Publisher $appSpec.Publisher -Version $appSpec.Version
        } else {
            Write-Host "Upgrading App $($appSpec.Name)"
            Start-NAVAppDataUpgrade -ServerInstance NAV -Publisher $appSpec.Publisher -Name $appSpec.Name -Version $appSpec.Version
        }
    } -ArgumentList $appFile, $installedApps

}

Write-Host "Done"
