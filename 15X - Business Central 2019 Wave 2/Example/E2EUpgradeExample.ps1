param(
    [string] $RootFolder = "C:\UpgradeExample",
    [string] $ServerRootFolder = "C:\Program Files\Microsoft Dynamics 365 Business Central\150\Service",
    [string] $ServerInstanceName = "BC150",
    [string] $DatabaseName = "Demo-Upgrade-To15",
    [string] $WebClientUrl = "http://localhost:8080/$ServerInstanceName/"
)

Import-Module "$RootFolder\UpgradeLibrary.psm1" -Force

# Installation to management dlls 
$global:ManagementDllsFolder = $ServerRootFolder

#C/AL Database to upgarde
$calDatabasePath = "$RootFolder\14\14DatabasePreparedForUpgrade.mdf"

# System symbols - get it from AL Development Enviroment installation folder - e.g. C:\Program Files (x86)\Microsoft Dynamics 365 Business Central\150\AL Development Environment
$systemSymbolsPath = "$RootFolder\15\SystemSymbols\System.app"

# Destination apps for migration
$systemAppPackage = "$RootFolder\15\DestinationAppsForMigration\Microsoft_System Application_15.1.37793.0.app"
$baseAppPackage = "$RootFolder\15\DestinationAppsForMigration\Microsoft_Customized Base Application_15.1.37793.0.app"
$freddyApp = "$RootFolder\15\DestinationAppsForMigration\Freddy_MyApp_1.0.0.0.app"

# Apps used to test upgrade, will track changes done during upgrade
$libraryAssert = "$RootFolder\15\DestinationAppsForMigration\Microsoft_Library Assert.app"
$upgTestPackage = "$RootFolder\15\DestinationAppsForMigration\Microsoft_Tests-Upgrade.app"

# Order matters, we need to follow dependencies          
$destinationAppsForMigrationPaths = @($systemAppPackage, $baseAppPackage, $freddyApp, $libraryAssert, $upgTestPackage)
$thirdPartyExtensionPaths = Get-ChildItem "$RootFolder\15\ThirdPartyApps" | % { $_.FullName }

Run-ConversionUpgradeFrom14 -ServerInstanceName $ServerInstanceName -DatabaseName $DatabaseName -DatabaseMDFFilePath $calDatabasePath -DestinationAppsForMigrationValue (Get-TestDesinationAppsForMigration) -SystemSymbolsPath $systemSymbolsPath -DestinationAppsForMigrationPaths $destinationAppsForMigrationPaths -ThirdPartyApps $thirdPartyExtensionPaths

$AlTestRunnerScriptPath = "$RootFolder\15\Test\TestRunner\ALTestRunner.psm1"
$DisabledTestsPath = "$RootFolder\15\Test\TestRunner\DisabledTests.json"

$TestResultsFolder = "$RootFolder\TestResults"

PublishAndInstall-TestRunnerApp -TestRunnerAppPath "$RootFolder\15\Test\TestRunner\Microsoft_Test Runner.app" -ServerInstanceName $ServerInstanceName

# Run upgrade tests
$upgradeTestsExtensionId = "d0e99b97-089b-449f-a0f5-a2ab994dbfd7"
Run-ALTestsAndVerifyResults -ExtensionId $upgradeTestsExtensionId -ServerInstanceName $ServerInstanceName -TestResultsFolder $TestResultsFolder -WebClientUrl $WebClientUrl -ALTestRunnerScript $AlTestRunnerScriptPath -DisabledTestsPath $DisabledTestsPath 
