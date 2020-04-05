# This script contains example on how to upgrade from 14 to 16 and to move full talbes and fields
# This functionality is used to showcase the upgrade, it should not be used to upgrade actual tenants - test the flow and change the script if needed

$global:RootFolderPath = "C:\MigrationUpgradeTest"
$global:ManagementDllsFolder = "C:\Program Files\Microsoft Dynamics 365 Business Central\160\Service"

function Upgrade-TableAndFieldMigrationTo16
(
    [string] $ServerInstanceName = 'BC160',
    [string] $DatabaseMDFFilePath = "$global:RootFolderPath\14-SourceObjects\Demo Database BC (14-0).mdf",
    [string[]] $DestinationAppsForMigrationPaths = @("$global:RootFolderPath\16-FirstStep-TableOnlyBaseAppAndBlankApps\TablesOnly_BaseApplication.app"),
    [string] $DatabaseName = 'TestUpgrade-MoveFields',
    [string] $SystemSymbolsPath = "$global:RootFolderPath\16-FirstStep-TableOnlyBaseAppAndBlankApps\Microsoft_System_16.0.11255.0.app",
    [string] $MicrosoftApplicationAppPath = "$global:RootFolderPath\16-SecondStep-DataMigrationAndDataUpgrade\Microsoft_Application.app",
    [string] $LicensePath = "$global:RootFolderPath\16-DemoLicense\build.flf",
    [string[]] $BlankAppsForUpgradePaths = @("$global:RootFolderPath\16-FirstStep-TableOnlyBaseAppAndBlankApps\BlankExtensions\Microsoft_System Application_7.0.0.0.app","$global:RootFolderPath\16-FirstStep-TableOnlyBaseAppAndBlankApps\BlankExtensions\Microsoft_Base Application_7.0.0.0.app","$global:RootFolderPath\16-FirstStep-TableOnlyBaseAppAndBlankApps\BlankExtensions\ABC_Rewards Extension_7.0.0.0.app"),
    [string[]] $BlankMigrationAppPaths = @("$global:RootFolderPath\16-SecondStep-DataMigrationAndDataUpgrade\MigrationApp-Empty.app"),
    [string[]] $TargetAppsForMigration = @("$global:RootFolderPath\16-SecondStep-DataMigrationAndDataUpgrade\Microsoft_System Application.app","$global:RootFolderPath\16-SecondStep-DataMigrationAndDataUpgrade\Microsoft_Base Application.app","$global:RootFolderPath\16-SecondStep-DataMigrationAndDataUpgrade\ABC_Rewards Extension_8.0.0.0.app"),
    [string[]] $OtherApps = @("C:\MigrationUpgradeTest\16-AfterSecondStep-PublishUpgradeOtherApps\Microsoft__Exclude_APIV1_.app","C:\MigrationUpgradeTest\16-AfterSecondStep-PublishUpgradeOtherApps\Microsoft_PayPal Payments Standard.app")
)
{
    Import-UpgradeScriptDependencies

    # Upgrade to tables only database
    $DestinationAppsForMigrationValue = Get-DestinationAppsForMigrationJson -DestinationAppsForMigrationPaths $DestinationAppsForMigrationPaths
    Upgrade-ToTableOnlyBaseAppAndBlankApps -ServerInstanceName $ServerInstanceName -DatabaseName $DatabaseName -DatabaseMDFFilePath $DatabaseMDFFilePath -DestinationAppsForMigrationPaths $DestinationAppsForMigrationPaths -SystemSymbolsPath $SystemSymbolsPath -DestinationAppsForMigrationValue $DestinationAppsForMigrationValue -BlankAppsForUpgradePaths $BlankAppsForUpgradePaths -LicensePath $LicensePath
    Upgrade-DataMigrationAndDataUpgrade -ServerInstanceName $ServerInstanceName -DestinationAppsForMigrationPaths $DestinationAppsForMigrationPaths -BlankDestinationAppsForMigrationPathsWithMigrationJsonPaths $BlankMigrationAppPaths -TargetAppsForMigration $TargetAppsForMigration -MicrosoftApplicationAppPath $MicrosoftApplicationAppPath
    UpgradeOrInstall-NavApps -AppPaths $OtherApps  -ServerInstanceName $ServerInstanceName
}

function Upgrade-ToTableOnlyBaseAppAndBlankApps
(
    [string] $ServerInstanceName,
    [string] $DatabaseName,
    [string] $DatabaseMDFFilePath,
    [string] $DestinationAppsForMigrationValue,
    [string] $SystemSymbolsPath,
    [string[]] $DestinationAppsForMigrationPaths,
    [string] $LicensePath,
    [string[]] $BlankAppsForUpgradePaths
)
{
    Import-UpgradeScriptDependencies
    
    Microsoft.Dynamics.Nav.Management\Stop-NAVServerInstance -ServerInstance $ServerInstanceName
    # Restore CAL Database
    Restore-Database -DatabaseName $DatabaseName -DatabaseMDFFilePath $DatabaseMDFFilePath

    # Technical upgrade - System Tables (2 billion range)
    Write-Host "Perform technical upgrade on $DatabaseName"
    Invoke-NAVApplicationDatabaseConversion -DatabaseName $DatabaseName -Force

    Write-Host "Configure server $ServerInstanceName for upgrade"
    Microsoft.Dynamics.Nav.Management\Set-NAVServerConfiguration -ServerInstance $ServerInstanceName -KeyName "DestinationAppsForMigration" -KeyValue ($DestinationAppsForMigrationValue.Replace("`n","").Replace("'r","")) | Out-Null

    # Integraiton table ID is configurable if needed. Default value is 5151. If you are using a different table you can set the property below, requirement is that it must have the same ID, RecordID and TableNo
    Microsoft.Dynamics.Nav.Management\Set-NavServerConfiguration -ServerInstance $ServerInstanceName -KeyName "IntegrationRecordsTableId" -KeyValue "5151"

    # Disable task scheduler
    Microsoft.Dynamics.Nav.Management\Set-NavServerConfiguration -ServerInstance $ServerInstanceName -KeyName "EnableTaskScheduler" -KeyValue false

    Write-Host "Start $ServerInstanceName"
    Microsoft.Dynamics.Nav.Management\Start-NAVServerInstance -ServerInstance $ServerInstanceName

    # Restart the server to free up resources
    Microsoft.Dynamics.Nav.Management\Restart-NAVServerInstance -ServerInstance $ServerInstanceName 

    $availableTenants = Microsoft.Dynamics.Nav.Management\Get-NAVTenant -ServerInstance $ServerInstanceName
    
    # Publish Symbols package
    Publish-NAVApp -ServerInstance $ServerInstanceName -Path $SystemSymbolsPath -PackageType SymbolsOnly -SkipVerification

    # Publish Migraiton Apps
    $DestinationAppsForMigrationPaths | ForEach-Object {
        $appPath = $_
        Write-Host "Publishing app - $appPath"
        Publish-NAVApp -Path $appPath -ServerInstance $ServerInstanceName -PackageType Extension -SkipVerification
    }

    # Restart the server to free up resources
    Microsoft.Dynamics.Nav.Management\Restart-NAVServerInstance -ServerInstance $ServerInstanceName 

    $availableTenants | ForEach-Object {
        $tenantId = $_.Id 
        Write-Host "Synchronizing tenant $tenantId"
        Microsoft.Dynamics.Nav.Management\Sync-NavTenant -ServerInstance $ServerInstanceName -Tenant $tenantId -Force
    }

    Write-Host "Start application upgrade."

    # Sync Migration apps
    # We move tables and generate SystemIds here
    $DestinationAppsForMigrationPaths | ForEach-Object {
        $appPath = $_
        $availableTenants | ForEach-Object {
            $tenantId = $_.Id
            Write-Host "Synchronizing $appPath for tenant $tenantId"
            Sync-NAVApp -Path $appPath -ServerInstance $ServerInstanceName -Tenant $tenantId 
        }
    }

    # Verify if all extensions were moved and metedata is correct
    $availableTenants | ForEach-Object {
        $tenantId = $_.Id
        Test-NAVTenantDatabaseSchema -ServerInstance  $ServerInstanceName -Tenant $tenantId
    }

    # Restart the server to free up resources
    Microsoft.Dynamics.Nav.Management\Restart-NAVServerInstance -ServerInstance $ServerInstanceName 
    
    # No Upgrade will run at this point - Destination app for migrationis empty
    $availableTenants | ForEach-Object {
        # Calling upgrade will install DestinationAppsForMigration during upgrade. OnInstall triggers will not be invoked in this mode.
        $tenantId = $_.Id
        Invoke-DataUpgrade -SkipCompanyInitialization -Tenant $tenantId
    }

    # Publish and Install Blank Apps here. These apps are used so Data Upgrade can be triggered in the next step. App should have version 14 (earlier that target).
    $BlankAppsForUpgradePaths | ForEach-Object {
        $appPath = $_
        Write-Host "Publishing app - $appPath"
        Publish-NAVApp -Path $appPath -ServerInstance $ServerInstanceName -PackageType Extension -SkipVerification
    }

    $BlankAppsForUpgradePaths | ForEach-Object {
        $appPath = $_
        $availableTenants | ForEach-Object {
            $tenantId = $_.Id
            Write-Host "Synchronizing $appPath for tenant $tenantId"
            Sync-NAVApp -Path $appPath -ServerInstance $ServerInstanceName -Tenant $tenantId 
        }
    }

    $BlankAppsForUpgradePaths | ForEach-Object {
        $appPath = $_
        $availableTenants | ForEach-Object {
            $tenantId = $_.Id
            Write-Host "Installing app - $appPath"
            Install-NAVApp -Path $appPath -ServerInstance $ServerInstanceName -Tenant $tenantId 
        }
    }

    
    # Import new license and restart server
    $FullServerName = 'MicrosoftDynamicsNavServer$' + $ServerInstanceName
    Import-NAVServerLicense $FullServerName -LicenseData ([Byte[]]$(Get-Content -Path $LicensePath -Encoding Byte)) -Database NavDatabase
        
    $availableTenants | ForEach-Object {
        $tenantId = $_.Id
        Import-NAVServerLicense $FullServerName -LicenseData ([Byte[]]$(Get-Content -Path $LicensePath -Encoding Byte)) -Database Tenant -Tenant $tenantId
    }
    
}

function Upgrade-DataMigrationAndDataUpgrade
(
    [string] $ServerInstanceName,
    [string[]] $DestinationAppsForMigrationPaths,
    [switch] $SkipCompanyInitialization,
    [string[]] $BlankDestinationAppsForMigrationPathsWithMigrationJsonPaths,
    [string[]] $TargetAppsForMigration,
    [string] $MicrosoftApplicationAppPath
)
{
    Import-UpgradeScriptDependencies
    $availableTenants = Microsoft.Dynamics.Nav.Management\Get-NAVTenant -ServerInstance $ServerInstanceName   

    # Unpublish and unistall the previous Tables Only app to remove metadata. Data will be kept - you have to specify -DoNotSaveData switch to delete data.
    $DestinationAppsForMigrationPaths | ForEach-Object {
        $appPath = $_
        $appInfo = Get-NavAppInfo -Path $appPath
        $availableTenants | ForEach-Object {
            $tenantId = $_.Id
            Write-Host "Uninstalling app - $appInfo.Name"
            Uninstall-NAVApp -ServerInstance $ServerInstanceName -Name $appInfo.Name -Version $appInfo.Version -Tenant $tenantId -Force
        }

        Write-Host "Unpublishing app - $appInfo.Name"
        Unpublish-NAVApp -ServerInstance $ServerInstanceName -Name $appInfo.Name -Version $appInfo.Version
    }

    # Publish new version of the apps that were uninstalled above. These are empty and have Migration.json, ID is the same as above, version is higher so we can upgrade.
    $BlankDestinationAppsForMigrationPathsWithMigrationJsonPaths | ForEach-Object {
        $appPath = $_
        Write-Host "Publishing app - $appPath"
        Publish-NAVApp -Path $appPath -ServerInstance $ServerInstanceName -PackageType Extension -SkipVerification
    }
   
    # Publish and Sync Target apps
    $TargetAppsForMigration | ForEach-Object {
        $appPath = $_
        Write-Host "Publishing app - $appPath"
        Publish-NAVApp -Path $appPath -ServerInstance $ServerInstanceName -PackageType Extension -SkipVerification        
    }

    $TargetAppsForMigration | ForEach-Object {
        $appPath = $_
        $availableTenants | ForEach-Object {
            $tenantId = $_.Id
            Write-Host "Synchronizing $appPath for tenant $($tenantId)"
            Sync-NAVApp -Path $appPath -ServerInstance $ServerInstanceName -Tenant $tenantId
        }
    }

    # Sync the Empty apps last
    # Must be synced last
    # If target apps have not taken over all fields or tables destructive changes will be detected
    $BlankDestinationAppsForMigrationPathsWithMigrationJsonPaths | ForEach-Object {
        $appPath = $_
        $availableTenants | ForEach-Object {
            $tenantId = $_.Id
            Write-Host "Synchronizing $appPath for tenant $($tenantId)"
            Sync-NAVApp -Path $appPath -ServerInstance $ServerInstanceName -Tenant $tenantId 
        }
    }
    
    # Upgrade Target Apps for migration
    $TargetAppsForMigration | ForEach-Object {
        $appPath = $_
        $availableTenants | ForEach-Object {
            $tenantId = $_.Id
            Write-Host "Synchronizing $appPath for tenant $($tenantId)"
            Start-NAVAppDataUpgrade -Path $appPath -ServerInstance $ServerInstanceName -Tenant $tenantId
        }
    }

    # Application Application must be published after BaseApp and SystemApp
    Publish-NAVApp -Path $MicrosoftApplicationAppPath -ServerInstance $ServerInstanceName -PackageType Extension -SkipVerification  
    $availableTenants | ForEach-Object {
        $tenantId = $_.Id
        Write-Host "Synchronizing $MicrosoftApplicationAppPath for tenant $($tenantId)"
        Sync-NAVApp -Path $MicrosoftApplicationAppPath -ServerInstance $ServerInstanceName -Tenant $tenantId 
    }

    # Upgrade the Empty apps - no code will be executed, needed so we can uninstall
    $BlankDestinationAppsForMigrationPathsWithMigrationJsonPaths | ForEach-Object {
        $appPath = $_
        $availableTenants | ForEach-Object {
            $tenantId = $_.Id
            Write-Host "Synchronizing $appPath for tenant $($tenantId)"
            Start-NAVAppDataUpgrade -Path $appPath -ServerInstance $ServerInstanceName -Tenant $tenantId
        }
    }

    # Install Application Application
    $availableTenants | ForEach-Object {
        $tenantId = $_.Id
        Write-Host "Synchronizing $MicrosoftApplicationAppPath for tenant $($tenantId)"
        Install-NAVApp -Path $MicrosoftApplicationAppPath -ServerInstance $ServerInstanceName -Tenant $tenantId 
    }

    # Call company initialization here
    if(-not $SkipCompanyInitialization)
    {
        $availableTenants | ForEach-Object {
            $tenantId = $_.Id
            Invoke-DataUpgrade -Tenant $tenantId
        }
    }
}

function UpgradeOrInstall-NavApps
(
    [string[]] $AppPaths,
    [string] $ServerInstanceName
)
{
    $availableTenants = Microsoft.Dynamics.Nav.Management\Get-NAVTenant -ServerInstance $ServerInstanceName
    $AppPaths | ForEach-Object {
        $appPath = $_
        Write-Host "Publishing app - $appPath"
        Publish-NAVApp -Path $appPath -ServerInstance $ServerInstanceName -PackageType Extension -SkipVerification
    }

    $AppPaths | ForEach-Object {
        $appPath = $_
        $availableTenants | ForEach-Object {
            $tenantId = $_.Id
            Write-Host "Synchronizing $appPath for tenant $tenantId"
            Sync-NAVApp -Path $appPath -ServerInstance $ServerInstanceName -Tenant $tenantId 
        }
    }
    
    $AppPaths | ForEach-Object {
        $appPath = $_
        $availableTenants | ForEach-Object {
            $tenantId = $_.Id
	        $appInfo = Get-NavAppInfo -Path $appPath
            $appTenantInfo = Get-NavAppInfo -Name $appInfo.Name -ServerInstance $ServerInstanceName -Tenant $tenantId -TenantSpecificProperties
            
            if($appTenantInfo.NeedsUpgrade -or $appTenantInfo.ExtensionDataVersion.Major -lt $appTenantInfo.Version.Major)
	        {
                Write-Host "Upgrading app - $appPath"
            	Start-NAVAppDataUpgrade -Path $appPath -ServerInstance $ServerInstanceName -Tenant $tenantId -Force
            }
            else
            { 
                if(-not $appTenantInfo.IsInstalled)
                {
                    Write-Host "Installing app - $appPath"
            	    Install-NAVApp -Path $appPath -ServerInstance $ServerInstanceName -Tenant $tenantId 
                }
            }
        }
    }
}

function PublishAndInstall-TestRunnerApp
(
    [string] $TestRunnerAppPath,
    [string] $ServerInstanceName
)
{
    Publish-NAVApp -Path $TestRunnerAppPath -ServerInstance $ServerInstanceName -PackageType Extension -SkipVerification
    Sync-NavApp -Name "Test Runner" -ServerInstance $ServerInstanceName 
    Install-NAVApp -Name "Test Runner" -ServerInstance $ServerInstanceName 
}

function Prepare-DatabaseForUpgrade
(
    [string] $ServerInstanceName
)
{
    Import-UpgradeScriptDependencies

    $availableTenants = Microsoft.Dynamics.Nav.Management\Get-NAVTenant -ServerInstance $ServerInstanceName
    $availableTenants | ForEach-Object {
        $tenantId = $_.Id
        Get-NAVAppInfo -ServerInstance $ServerInstanceName -Tenant $tenantId | ForEach-Object { Uninstall-NAVApp -ServerInstance $ServerInstanceName -Name $_.Name -Version $_.Version -Tenant $tenantId -Force}
    }

    Get-NAVAppInfo -ServerInstance $ServerInstanceName | ForEach-Object { Unpublish-NAVApp -ServerInstance $ServerInstanceName -Name $_.Name -Version $_.Version }

    Get-NAVAppInfo -ServerInstance $ServerInstanceName -SymbolsOnly | ForEach-Object { Unpublish-NAVApp -ServerInstance $ServerInstanceName -Name $_.Name -Version $_.Version }

    Microsoft.Dynamics.Nav.Management\Stop-NAVServerInstance -ServerInstance $ServerInstanceName
}

function Import-UpgradeScriptDependencies
(
    [string] $ManagementDllsFolder = "$global:ManagementDllsFolder"
)
{
    Import-Module (Join-Path $ManagementDllsFolder "Microsoft.Dynamics.Nav.Management.dll")
    Import-Module (Join-Path $ManagementDllsFolder "Microsoft.Dynamics.Nav.Apps.Management.dll")
}

function Get-DestinationAppsForMigrationJson
(
    [string[]] $DestinationAppsForMigrationPaths
)
{
    $destinationAppsForMigration = @()
    $DestinationAppsForMigrationPaths | ForEach-Object {
        if ($_) {
            Write-Host "Destination App $_"
            $info = Get-NavAppInfo -Path "$_"
            $destinationAppsForMigration += @([ordered]@{ "appId" = $info.AppId.Value; "name" = $info.Name; "publisher" = $info.Publisher; "version" = $info.Version; })
        }
    }

    [string] $destinationAppsForMigrationJson =  $destinationAppsForMigration | ConvertTo-Json -Depth 99 -Compress
    if(! $destinationAppsForMigrationJson.StartsWith('['))
    {
        $destinationAppsForMigrationJson = "[" + $destinationAppsForMigrationJson
    }

    if(! $destinationAppsForMigrationJson.EndsWith(']'))
    {
        $destinationAppsForMigrationJson = $destinationAppsForMigrationJson + "]"
    }

    return $destinationAppsForMigrationJson
}

function Run-ALTestsAndVerifyResults
(
    [string] $ServerInstanceName,
    [string] $TestResultsFolder,
    [string] $WebClientUrl,
    [string] $ALTestRunnerScript,
    [string] $DisabledTestsPath,
    [string] $ExtensionId
)
{
    Microsoft.Dynamics.Nav.Management\Restart-NAVServerInstance -ServerInstance $ServerInstanceName
  
    Write-Host "Importing AL Test Runner from $ALTestRunnerScript"
    Import-Module $ALTestRunnerScript 

    if(Test-Path $TestResultsFolder)
    {
        Remove-Item $TestResultsFolder -Force -Recurse
    }

    New-Item $testResultsFolder -ItemType Directory
    $testResultFilePath = Join-Path $testResultsFolder "Tests-$ExtensionId.xml"
    $disabledTests = Get-DisabledAlTests -DisabledTestsPath $DisabledTestsPath
    Run-AlTests -ResultsFilePath $testResultFilePath -ServiceUrl $WebClientUrl -ExtensionId $ExtensionId -DisabledTests $disabledTests -AutorizationType Windows
    
    Invoke-ALTestResultVerification -TestResultsFolder $testResultsFolder  
}

function Restore-Database
(
    [string] $DatabaseName,
    [string] $DatabaseMDFFilePath
)
{
    $backupMDFFile = $DatabaseMDFFilePath + " - Backup"

    if(Test-DatabaseExists $DatabaseName)
    {
        Remove-BCDatabase $DatabaseName -Force
    }
    
    if(-not (Test-Path($backupMDFFile)))
    {
        # Create backup if does not exist
        Copy-Item -Path $DatabaseMDFFilePath -Destination $backupMDFFile
    }
    else
    {
        # Set from backup to avoid locks, removing the database can delete the file
        Copy-Item -Path $backupMDFFile -Destination $DatabaseMDFFilePath
    }

    Restore-MDFFile -DatabaseMdfFile $DatabaseMDFFilePath -DatabaseName $DatabaseName
    Microsoft.Dynamics.Nav.Management\Stop-NAVServerInstance -ServerInstance  $ServerInstanceName
    Microsoft.Dynamics.Nav.Management\Set-NAVServerConfiguration -ServerInstance $ServerInstanceName -KeyName "DatabaseName" -KeyValue $DatabaseName | Out-Null
}

function Publish-OtherExtensions
(
    [string[]] $Extensions
)
{

}

function Test-DatabaseExists(
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName
)
{
    $sqlCommandText = @"
        USE MASTER
        SELECT '1' FROM SYS.DATABASES WHERE NAME = '$DatabaseName'
        GO
"@

    return ((Run-SqlCommandWithOutput -Command $sqlCommandText) -ne $null)
}


function Remove-BCDatabase
(
    [string] $DatabaseName
)
{
    Run-SqlCommandWithOutput -Command "DROP DATABASE [$DatabaseName]"
}

function Run-SqlCommandWithOutput
(
    [string]$Command, 
    [int] $CommandTimeout = 0
)
{
    [string]$Server = "."
    
    # Wait for SQL Service Running
    $SQLService = Get-Service "MSSQLSERVER"

    if (!$SQLService)
    {
        throw "No MSSQLSERVER service found"
    }
    if ($SQLService.Status -notin 'Running','StartPending')
    {
        $SQLService.Start()
    }
    $SQLService.WaitForStatus('Running','00:05:00')

    $Options = @{}
    if ($CommandTimeout)
    {
        $Options["QueryTimeout"] = $CommandTimeout
    }

    Write-Host "Executing SQL query ($Server): ""$Command""" -Debug
    Invoke-Sqlcmd -ServerInstance $Server -Query $Command @Options
}

function Restore-MDFFile
(
    [string] $DatabaseName,
    [string] $DatabaseMdfFile
)
{
  $sqlscript = "CREATE DATABASE [$DatabaseName] ON (FILENAME= N'$DatabaseMdfFile')FOR ATTACH;"
  Run-SqlCommandWithOutput -Command $sqlscript 
  Add-DbOwner -DatabaseName $DatabaseName -Owner "NT AUTHORITY\NETWORK SERVICE" -DatabaseServer "."
}

function Add-DbOwner
(
    [string]$DatabaseName,
    [string]$DatabaseServer,
    [string]$Owner,
    [string]$Password
)
{
    if (-Not $Password)
    {
        $CreateLoginSql = "CREATE LOGIN [$Owner] FROM WINDOWS;"
    }
    else
    {
        $CreateLoginSql = "CREATE LOGIN [$Owner] WITH PASSWORD = '$Password'; ELSE ALTER LOGIN [$Owner] WITH PASSWORD = '$Password';"
    }

    #Permissions required by server lock and deadlock monitoring
    $createServerLoginCommand = @"
        USE [master];
        IF NOT EXISTS (SELECT 1 FROM master.dbo.syslogins WHERE name = '$Owner')
            $CreateLoginSql

        GRANT VIEW SERVER STATE TO [$Owner];
        GRANT ALTER ANY EVENT SESSION TO [$Owner]
"@

    Run-SqlCommandWithOutput -Command $createServerLoginCommand -Server $DatabaseServer

    $createUserCommand = @"
        USE [$DatabaseName];
        IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$Owner')
            CREATE USER [$Owner] FOR LOGIN [$Owner] WITH DEFAULT_SCHEMA=[dbo]
"@
    Run-SqlCommandWithOutput -Command $createUserCommand -Server $DatabaseServer
    Run-SqlCommandWithOutput -Command "USE [$DatabaseName]; EXEC sp_addrolemember 'db_owner', '$Owner'" -Server $DatabaseServer
}

function Invoke-ScriptBlock
(
    [parameter(Mandatory, Position=0)]
    [ScriptBlock] $ScriptBlock,
    [object[]] $ArgumentList = @()
)
{
    $job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList

    $returnValue = Receive-Job -Job $job -Wait
    if ($job.State -eq "Failed")
    {
        throw $job.ChildJobs[0].JobStateInfo.Reason
    }

    return $returnValue
}

function Invoke-DataUpgrade
(
    [switch] $SkipCompanyInitialization,
    [string] $TenantId
)
{
  # We will collect information about all errors at once thanks to -ContinueOnError switch
  Start-NAVDataUpgrade -FunctionExecutionMode Serial -ServerInstance $ServerInstanceName -SkipCompanyInitialization:$SkipCompanyInitialization -Tenant $TenantId -SkipAppVersionCheck -ErrorAction Stop -Force

  # Wait for Upgrade Process to complete
  Get-NAVDataUpgrade -ServerInstance $ServerInstanceName -Tenant $TenantId -Progress -ErrorAction Stop

  # Make sure that Upgrade Process completed successfully.
  $errors = Get-NAVDataUpgrade -ServerInstance $ServerInstanceName -Tenant $TenantId -ErrorOnly -ErrorAction Stop

  if (!$errors)
  {
    # no errors detected - process has been completed successfully
    Write-Host "Data upgrade completed succesfully for $TenantId."
    return;
  }

  # Stop the suspended process - we won't resume in here
  Stop-NAVDataUpgrade -ServerInstance $ServerInstanceName -Tenant $TenantId -Force -ErrorAction Stop

  $errorMessage = "Errors occured during Data Upgrade Process: " + [System.Environment]::NewLine
  foreach ($nextErrorRecord in $errors)
  {
    $errorMessage += ("Codeunit ID: " + $nextErrorRecord.CodeunitId + ", Function: " + $nextErrorRecord.FunctionName + ", Error: " + $nextErrorRecord.Error + [System.Environment]::NewLine)
  }

  Write-Error $errorMessage
}

function Invoke-ALTestResultVerification
(
    [string] $TestResultsFolder = $(throw "Missing argument TestResultsFolder")
)
{
    $failedTestList = New-Object System.Collections.ArrayList
    $testsExecuted = $false
    [array]$testResultFiles = Get-ChildItem -Path $TestResultsFolder -Filter "*.xml" | Foreach { "$($_.FullName)" }

    if($testResultFiles.Length -eq 0)
    {
        throw "No test results were found"
    }

    foreach($resultFile in $testResultFiles)
    {
        [xml]$xmlDoc = Get-Content "$resultFile"
        [array]$failedTests = $xmlDoc.assemblies.assembly.collection.ChildNodes | Where-Object {$_.result -eq 'Fail'}
        if($failedTests)
        {
            $testsExecuted = $true
            foreach($failedTest in $failedTests)
            {
                $failedTestObject = @{
                    name = $failedTest.name;
                    method = $failedTest.method;
                    time = $failedTest.time;
                    message = $failedTest.failure.message;
                    stackTrace = $failedTest.failure.'stack-trace';
                }

                $failedTestList.Add($failedTestObject) > $null
            }
        }

         [array]$otherTests = $xmlDoc.assemblies.assembly.collection.ChildNodes | Where-Object {$_.result -ne 'Fail'}
         if($otherTests.Length -gt 0)
         {
            $testsExecuted = $true
         }
    }

    if($failedTestList.Count -gt 0) 
    {
        Write-Log "Failed tests:"
        $testsFailed = ""
        foreach($failedTest in $failedTestList)
        {
            $testsFailed += "Name: " + $failedTest.name + [environment]::NewLine
            $testsFailed += "Method: " + $failedTest.method + [environment]::NewLine
            $testsFailed += "Time: " + $failedTest.time + [environment]::NewLine
            $testsFailed += "Message: " + [environment]::NewLine + $failedTest.message + [environment]::NewLine
            $testsFailed += "StackTrace: "+ [environment]::NewLine + $failedTest.stackTrace + [environment]::NewLine  + [environment]::NewLine
        }

        Write-Log $testsFailed
        throw "Test execution failed due to the failing tests, see the list of the failed tests above."
    }

    if(-not $testsExecuted)
    {
        throw "No test codeunits were executed"
    }
}

function Get-DisabledAlTests
(
    [string] $DisabledTestsPath
)
{
    $DisabledTests = @()
    if(Test-Path $DisabledTestsPath)
    {
        $DisabledTests = Get-Content $DisabledTestsPath | ConvertFrom-Json
    }

    return $DisabledTests
}

Export-ModuleMember -Function *-*