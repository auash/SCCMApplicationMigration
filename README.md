# SCCMApplicationMigration
PowerShell scripts that perform SCCM Application exports and imports with better handling of content than the built-in functions.

See [https://asherjebbink.medium.com/sccm-application-migration-with-better-content-handling-cb7309a083e0](https://asherjebbink.medium.com/sccm-application-migration-with-better-content-handling-cb7309a083e0) for information about why this repo exists.


# Usage
1. Download/clone the entire repo.
2. Open `ToProcess.csv` and provide values for the Application(s) you want to export and the import configuration

### Exporting
1. Open `Export-SCCMApplications.ps1` in a text editor and provide values for the following variables at the top of the script:
   - `$SCCMSiteCode` - the 3 character Site Code you will be exporting **from**
   - `$ProviderMachineName` - Machine name of the SCCM server that has the SMS Provider service installed which you are exporting **from**
2. Optionally, you can modify the other variables under `Step 2` in the script
3. Execute the `Export-SCCMApplications.ps1` script using an account that has sufficient permissions to perform exports on the SCCM Site.
4. Review the log file at `\Desktop\SCCMAppMigration-Export.log`

### Importing
1. Copy/move the entire `SCCMApplicationMigration` folder used during the *export* to a location that can be accessed by your *destination* SCCM Site Server
2. Create a share of the `SCCMApplicationMigration` folder so that it can be accessed via a UNC path. 
   - Example: \\\\destination-server\SCCMApplicationMigration
4. Open `Import-SCCMApplications.ps1` in a text editor and provide values for the following variables at the top of the script:
   - `$SCCMSiteCode` - the 3 character Site Code you will be importing **to**
   - `$ProviderMachineName` - Machine name of the SCCM server that has the SMS Provider service installed which you are importing **to**
   - `$RootAppContentDestinationPath` - the path where the imported Application content will be copied to.
     - Example value: \\\\destination-server\source$\
   - `$RootAppInfoSourcePath` - UNC path to the exported `AppInfo` folder. Must be a UNC path. 
     - Example value: \\\\destination-server\SCCMApplicationMigration\AppInfo
   - `$RootAppContentSourcePath` - UNC path to the exported `Content` folder. Must be a UNC path. 
     - Example value: \\\\destination-server\SCCMApplicationMigration\Content
5. Optionally, you can modify the other variables under `Step 2` in the script
6. Execute the `Import-SCCMApplications.ps1` script using an account that has sufficient permissions to perform imports on the SCCM Site and can write the content files to the `RootAppContentDestinationPath` location
7. Review the log file at `\Desktop\SCCMAppMigration-Import.log`

# Notes
- If the destination Application name already exists, then the Application won't be re-imported. It will be skipped.
- Application dependencies are not migrated. The *Export* script will write to log the Applications that had dependencies.
