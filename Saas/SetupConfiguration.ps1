. "C:\RUN\SetupConfiguration.ps1"

$SaasSettings = @{
    "ODataServicesMaxPageSize" = "20000"
    "ClientServicesMaxUploadSize" = "150"
    "ClientServicesMaxItemsInObjectGraph" = "512"
}

$SaasSettings.Keys | % {
    $setting = $customConfig.SelectSingleNode("//appSettings/add[@key='$_']")
    if ($setting) {
        Write-Host "Setting $_ to $($SaasSettings[$_])"
        $setting.Value = $SaasSettings[$_]
    }
    else {
        Write-Host "Ignoring setting $_"
    }
}

$CustomConfig.Save($CustomConfigFile)
