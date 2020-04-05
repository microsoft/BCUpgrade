Import Development license in the DemoDatabase before continuing

If you would like to build the database, restore 14 database, upload proper license and run Prepare-DatabaseForUpgrade

Database should be placed into 14-SourceObjects
16 License should be uploaded to 16-DemoLicense

Code is in UpgradeScript.psm1
To start the test run Upgrade-TableAndFieldMigrationTo16
