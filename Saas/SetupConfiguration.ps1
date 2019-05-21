$SaasSettings = [string]::join(',',@(
    "ODataServicesMaxPageSize=20000"
    "ClientServicesMaxUploadSize=150"
    "ClientServicesMaxItemsInObjectGraph=512"
    "XmlMetadataCacheSize=500"
    "UseFindMinusWhenPopulatingPage=true"
))

if ($customNavSettings -ne "") { 
    $customNavSettings += ",$SaasSettings"
}
else {
    $customNavSettings = $SaasSettings
}

. "C:\RUN\SetupConfiguration.ps1"
