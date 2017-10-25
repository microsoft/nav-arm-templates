. "C:\Run\SetupNavUsers.ps1"

if ($DatabaseName.StartsWith("Financials")) {
    if (!($securePassword)) {
        # old version of the generic nav container
        $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
    }

    Write-Host "Creating Users and Entitlements"
    # CSPAdmin might have been created as admin of container
    if (!(Get-NavServerUser 'NAV' | Where-Object { $_.UserName -eq 'CSPADMIN' })) {
        # Add CSPADMIN user as a NAV user and assign SUPER permission set
        New-NAVServerUser 'NAV' -UserName 'CSPADMIN' -Password $securePassword -FullName 'CSP Administrator'
        New-NAVServerUserPermissionSet 'NAV' –UserName 'CSPADMIN' -PermissionSetId 'SUPER'
    }
    
    # Add FIN user as a NAV user and assign to the D365 BUS FULL ACCESS permission set
    New-NAVServerUser 'NAV' -UserName 'FIN' -Password $securePassword -FullName 'Financials User'
    New-NAVServerUserPermissionSet 'NAV' –UserName 'FIN' -PermissionSetId 'D365 BUS FULL ACCESS'
    New-NAVServerUserPermissionSet 'NAV' –UserName 'FIN' -PermissionSetId 'LOCAL'
    
    # Add ACCT user as a NAV user and assign to the D365 BUS FULL ACCESS permission set
    New-NAVServerUser 'NAV' -UserName 'ACCT' -Password $securePassword -FullName 'Accountant user'
    New-NAVServerUserPermissionSet 'NAV' –UserName 'ACCT' -PermissionSetId 'D365 BUS FULL ACCESS'
    New-NAVServerUserPermissionSet 'NAV' –UserName 'ACCT' -PermissionSetId 'LOCAL'
    
    # Assign the user to the preview entitlements
    Invoke-Sqlcmd -Server "$DatabaseServer\$DatabaseInstance" -Query "declare @SID uniqueidentifier
    SELECT @SID = [User Security ID] FROM [$DatabaseName].[dbo].[User] where [User Name]= 'CSPADMIN'
    INSERT INTO [$DatabaseName].[dbo].[Membership Entitlement] VALUES (DEFAULT, 2, @SID, 'APPS RANGE', 'NAV_DELEGATED_ADMIN',1), (DEFAULT, 2, @SID, 'DYNAMICS EXTENSIONS', 'NAV_DELEGATED_ADMIN',1), (DEFAULT, 2, @SID, 'DELEGATED_ADMIN', 'NAV_DELEGATED_ADMIN',1);"
    
    # Assign the FIN user to the Dyn365 Financials Business entitlements
    Invoke-Sqlcmd -Server "$DatabaseServer\$DatabaseInstance" -Query "declare @SID2 uniqueidentifier
    SELECT @SID2 = [User Security ID] FROM [$DatabaseName].[dbo].[User] where [User Name]= 'FIN'
    INSERT INTO [$DatabaseName].[dbo].[Membership Entitlement] VALUES (DEFAULT, 2, @SID2, 'APPS RANGE', 'DYN365_FINANCIALS_BUSINESS',1), (DEFAULT, 2, @SID2, 'DYNAMICS EXTENSIONS', 'DYN365_FINANCIALS_BUSINESS',1), (DEFAULT, 2, @SID2, 'DFIN_BUSINESS', 'DYN365_FINANCIALS_BUSINESS',1);"
    
    # Assign the ACCT user to the DYN365_FINANCIALS_ACCOUNTANT entitlements
    Invoke-Sqlcmd -Server "$DatabaseServer\$DatabaseInstance" -Query "declare @SID2 uniqueidentifier
    SELECT @SID2 = [User Security ID] FROM [$DatabaseName].[dbo].[User] where [User Name]= 'ACCT'
    INSERT INTO [$DatabaseName].[dbo].[Membership Entitlement] VALUES (DEFAULT, 2, @SID2, 'APPS RANGE', 'DYN365_FINANCIALS_ACCOUNTANT',1), (DEFAULT, 2, @SID2, 'DYNAMICS EXTENSIONS', 'DYN365_FINANCIALS_ACCOUNTANT',1), (DEFAULT, 2, @SID2, 'DFIN_ACCOUNTANT', 'DYN365_FINANCIALS_ACCOUNTANT',1);"
}
    