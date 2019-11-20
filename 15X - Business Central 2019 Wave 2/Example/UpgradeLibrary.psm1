# This script contains commands to upgrade and test upgrade of the tenant
# The file will be released on the Docker and DVD. Functions need to be able to work with tooling that is released on the DVD 
# This functionality is used to test the upgrade, it should not be used to upgrade actual tenants

function Run-ConversionUpgradeFrom14
(
    [string] $ServerInstanceName,
    [string] $DatabaseName,
    [string] $DatabaseMDFFilePath,
    [string] $DestinationAppsForMigrationValue = (Get-DefaultDestinationAppsForMigration),
    [string] $SystemSymbolsPath,
    [string[]] $DestinationAppsForMigrationPaths,
    [string[]] $ThirdPartyApps,
    [switch] $SkipCompanyInitialization
)
{
    Import-UpgradeScriptDependencies

    # Restore CAL Database
    Restore-Database -DatabaseName $DatabaseName -DatabaseMDFFilePath $DatabaseMDFFilePath

    # Technical upgrade - System Tables (2 billion range)
    Write-Host "Perform technical upgrade on $DatabaseName"
    Invoke-NAVApplicationDatabaseConversion -DatabaseName $DatabaseName -Force

    Write-Host "Configure server $ServerInstanceName for upgrade"
    Microsoft.Dynamics.Nav.Management\Set-NAVServerConfiguration -ServerInstance $ServerInstanceName -KeyName "DestinationAppsForMigration" -KeyValue ($DestinationAppsForMigrationValue.Replace("`n","").Replace("'r","")) | Out-Null
    Microsoft.Dynamics.Nav.Management\Set-NavServerConfiguration -ServerInstance $ServerInstanceName -KeyName "EnableTaskScheduler" -KeyValue $false | Out-Null

    # Integraiton table ID is configurable if needed. Default value is 5151. If you are using a different table you can set the property below, requirement is that it must have the same ID, RecordID and TableNo
    Microsoft.Dynamics.Nav.Management\Set-NavServerConfiguration -ServerInstance $ServerInstanceName -KeyName "IntegrationRecordsTableId" -KeyValue "5151"

    # Disable task scheduler
    Microsoft.Dynamics.Nav.Management\Set-NavServerConfiguration -ServerInstance $ServerInstanceName -KeyName "EnableTaskScheduler" -KeyValue false

    Write-Host "Start $ServerInstanceName"
    Microsoft.Dynamics.Nav.Management\Start-NAVServerInstance -ServerInstance $ServerInstanceName
    
    # Publish Symbols package
    Publish-NAVApp -ServerInstance $ServerInstanceName -Path $SystemSymbolsPath -PackageType SymbolsOnly -SkipVerification

    # Publish Migraiton Apps
    foreach($appPath in $DestinationAppsForMigrationPaths)
    {
        Write-Host "Publishing app - $appPath"
        Publish-NAVApp -Path $appPath -ServerInstance $ServerInstanceName -PackageType Extension -SkipVerification
    }

    # Restart the server to free up resources
    Microsoft.Dynamics.Nav.Management\Restart-NAVServerInstance -ServerInstance $ServerInstanceName 

    $availableTenants = Microsoft.Dynamics.Nav.Management\Get-NAVTenant -ServerInstance $ServerInstanceName

    # Synchronize all tenants
    foreach($tenant in $availableTenants)
    {
        Write-Host "Synchronizing tenant $($tenant.Id)"
        Microsoft.Dynamics.Nav.Management\Sync-NavTenant -ServerInstance $ServerInstanceName -Tenant $tenant.Id -Force
    }

    Write-Host "Start application upgrade."

    # Sync Migration apps
    # We move tables and generate SystemIds here
    foreach($appPath in $DestinationAppsForMigrationPaths)
    {
        foreach($tenant in $availableTenants)
        {
            Write-Host "Synchronizing $appPath for tenant $($tenant.Id)"
            Sync-NAVApp -Path $appPath -ServerInstance $ServerInstanceName -Tenant $tenant.Id 
        }
    }

    # Verify if all extensions were moved and metedata is correct
    foreach($tenant in $availableTenants)
    {
        Test-NAVTenantDatabaseSchema -ServerInstance  $ServerInstanceName -Tenant $tenant.Id
    }

    # Invoke Data upgrade
    # This cmdlet will automatically install and upgrade all of the extensions listed in DestinationAppsForMigration
    foreach($tenant in $availableTenants)
    {
        # Calling upgrade will install DestinationAppsForMigration during upgrade. OnInstall triggers will not be invoked in this mode.
        Invoke-DataUpgrade -SkipCompanyInitialization:$SkipCompanyInitialization -Tenant $tenant.Id
    }


    #Publish and upgrade other extensions
    foreach($appPath in $ThirdPartyApps)
    {
        Write-Host "Publishing app - $appPath"
        Publish-NAVApp -Path $appPath -ServerInstance $ServerInstanceName -PackageType Extension -SkipVerification
    }

    # Sync all third party extensions
    foreach($appPath in $ThirdPartyApps)
    {
        foreach($tenant in $availableTenants)
        {
            Write-Host "Synchronizing $appPath for tenant $($tenant.Id)"
            Sync-NAVApp -Path $appPath -ServerInstance $ServerInstanceName -Tenant $tenant.Id 
        }
    }
    
    # Upgrade all third party extensions
    foreach($appPath in $ThirdPartyApps)
    {
        foreach($tenant in $availableTenants)
        {
            Write-Host "Upgrading $appPath for tenant $($tenant.Id)"
            Start-NAVAppDataUpgrade -Path $appPath -ServerInstance $ServerInstanceName -Tenant $tenant.Id -Force
        }
    }

    # Enable task scheduler
    Microsoft.Dynamics.Nav.Management\Set-NavServerConfiguration -ServerInstance $ServerInstanceName -KeyName "EnableTaskScheduler" -KeyValue true

    # Restart server so settings are in place
    Microsoft.Dynamics.Nav.Management\Restart-NAVServerInstance -ServerInstance $ServerInstanceName 
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
    foreach($tenant in $availableTenants)
    {
        Get-NAVAppInfo -ServerInstance $ServerInstanceName -Tenant $tenant.Id | % { Uninstall-NAVApp -ServerInstance $ServerInstanceName -Name $_.Name -Version $_.Version -Tenant $tenant.Id -Force}
    }

    Get-NAVAppInfo -ServerInstance $ServerInstanceName | % { Unpublish-NAVApp -ServerInstance $ServerInstanceName -Name $_.Name -Version $_.Version }

    Get-NAVAppInfo -ServerInstance $ServerInstanceName -SymbolsOnly | % { Unpublish-NAVApp -ServerInstance $ServerInstanceName -Name $_.Name -Version $_.Version }

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

function Get-DestinationAppsForMigration()
{
    return '[{"appId":"63ca2fa4-4f03-4f2b-a480-172fef340d3f", "name":"System Application","publisher": "Microsoft"},{"appId":"437dbf0e-84ff-417a-965d-ed2bb9650972", "name":"Base Application", "publisher": "Microsoft"},{"appId": "d6953f02-7fd2-412f-983d-bf6866fc738c","name": "MyApp","publisher": "Freddy"}]'
}

function Get-TestDesinationAppsForMigration()
{
    return '[{"appId":"63ca2fa4-4f03-4f2b-a480-172fef340d3f","name":"System Application","publisher": "Microsoft"}, { "appId":"437dbf0e-84ff-417a-965d-ed2bb9650972", "name":"Base Application", "publisher": "Microsoft"}, { "appId": "d6953f02-7fd2-412f-983d-bf6866fc738c", "name": "MyApp", "publisher": "Freddy" }, {"appId":"d0e99b97-089b-449f-a0f5-a2ab994dbfd7",  "name":"Tests-Upgrade",  "publisher": "Microsoft"},{ "appId":"dd0be2ea-f733-4d65-bb34-a28f4624fb14", "name":"Library Assert", "publisher": "Microsoft"} ]'
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