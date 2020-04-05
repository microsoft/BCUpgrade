Import Development license in the DemoDatabase before continuing

If you would like to build the database, restore 14 database, upload proper license and run  :
# Update to match your installation path
$global:ManagementDllsFolder = "C:\Program Files\Microsoft Dynamics 365 Business Central\140\Service"
Prepare-DatabaseForUpgrade

Database should be placed into 14-SourceObjects
16 License should be uploaded to 16-DemoLicense

Code is in UpgradeScript.psm1
To start the test run Upgrade-TableAndFieldMigrationTo16
