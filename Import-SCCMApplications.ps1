$ErrorActionPreference = "Stop"


#######################################################################
#
#   Step 1 - You MUST change these values to match your environment.
#
#######################################################################
$SCCMSiteCode = "PR1"   # SCCM Site code you are importing TO
$ProviderMachineName = "SCCM-01"   # Machine name of the SCCM server that has the SMS Provider service installed.
$RootAppContentDestinationPath = "\\server\NewSource"   # The root folder where you want Application content to be migrated TO
$RootAppInfoSourcePath = "\\server\share\AppInfo"       # Where Application (meta data) will be searched for to import
$RootAppContentSourcePath = "\\server\share\Content"    # Where Application content will be copied from (to the $RootAppContentDestinationPath path above)

#######################################################################
#
#   Step 2 - OPTIONAL: Change these if you desire.
#
#######################################################################
$LogFilePath = "$($env:USERPROFILE)\Desktop\SCCMAppMigration-Import.log"    # Where this script will log to
$AppsToProcessCsvPath = "$(Split-Path $MyInvocation.MyCommand.Path)\ToProcess.csv"    # The list of SCCM Applications that will be searched for and imported, as well as the import configuration.
$ApplicationFolderInSCCM = "Application"   # Control where the imported Applications are placed inside the SCCM Console. Default is the root of 'Applications'. Example placement into a subfolder: "Application\SubFolder1\SubFolder2". Note 1: The subfolders must already exist. Note 2: The root folder is "Application", not "ApplicationS" (plural)
$DistributionPointGroupName = ""   #Provide the DP Group name that all imported Applications should be distributed to. Leave this blank if you don't want the script to distribute content.


Function AppExistsInSCCM($ApplicationName)
{
    $App = $null
    $App = Get-CMApplication -Name $ApplicationName -Fast

    if ($App -eq $null)
    {
        return $false
    }
    else
    {
        return $true
    }
}

Function AppCSVDataIsValid($AppCSV)
{
    if ([string]::IsNullOrWhiteSpace($AppCSV.SourceAppName) -or
        [string]::IsNullOrWhiteSpace($AppCSV.DestinationAppName) -or
        [string]::IsNullOrWhiteSpace($AppCSV.FolderManufacturer) -or
        [string]::IsNullOrWhiteSpace($AppCSV.FolderAppName) -or
        [string]::IsNullOrWhiteSpace($AppCSV.FolderAppVersion) -or
        [string]::IsNullOrWhiteSpace($AppCSV.FolderAppName)
    )
    {
        return $false
    }
    else
    {
        return $true
    }
}

Function DistributeApplication($ApplicationName)
{
    Start-CMContentDistribution -ApplicationName $ApplicationName -DistributionPointGroupName $DistributionPointGroupName
}


# Import the ConfigurationManager.psd1 module 
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" 
}

# Connect to the site's drive if it is not already present
if((Get-PSDrive -Name $SCCMSiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SCCMSiteCode -PSProvider CMSite -Root $ProviderMachineName
}

# Set the current location to be the site code.
Set-Location "$($SCCMSiteCode):\"

Import-Module ActiveDirectory

Start-Transcript -Path $LogFilePath -Append

cd "$($env:SystemDrive)\"
Write-Output "Reading CSV for apps to process..."
$CSVApps = Import-Csv -Path $AppsToProcessCsvPath
cd "$($SCCMSiteCode):\$($ApplicationFolderInSCCM)"

Write-Output "Read $($CSVApps.Count) apps from CSV file"

foreach ($CSVApp in $CSVApps)
{
    Write-Output ""
    
    # Validate the CSV provided for this app is complete before continuing
    if (-not (AppCSVDataIsValid -AppCSV $CSVApp))
    {
        Write-Output "ERROR: the CSV has incomplete details for the following Application: '$($CSVApp.SourceAppName)'. It has NOT been migrated."
        continue;
    }

    Write-Output "Processing $($CSVApp.SourceAppName)"

    # Check if the App already exists in SCCM. If it does, skip it.
    if (AppExistsInSCCM -ApplicationName $CSVApp.DestinationAppName)
    {
        Write-Output "ERROR: '$($CSVApp.DestinationAppName)' already exists in the destination SCCM. Not migrating again."
        continue
    }

    # Check that the app export file exists
    $AppInfoToImport = $null
    $AppInfoToImport = Join-Path -Path $RootAppInfoSourcePath -ChildPath "$($CSVApp.SourceAppName)\$($CSVApp.SourceAppName).zip"

    if (-not (Test-path "FileSystem::$AppInfoToImport"))
    {
        Write-Output "ERROR: The AppInfo file for $($CSVApp.SourceAppName) was expected at '$($AppInfoToImport)' but couldn't be found. Application skipped."
        continue
    }

    #Import the app
    Write-Output "Importing '$AppInfoToImport'"
    Import-CMApplication -FilePath $AppInfoToImport
    Write-Output "Import done."

    if ($ApplicationFolderInSCCM -ne "Application")
    {
        #App is imported to root Application location. Move it to the desired spot.
        Write-Output "Moving the Application to the right spot in the Console..."
        Get-CMApplication -Name $CSVApp.SourceAppName -Fast | Move-CMObject -FolderPath "$($SCCMSiteCode):\$($ApplicationFolderInSCCM)"
        Write-Output "Move done."
    }

    #rename if needed
    if ($CSVApp.SourceAppName -ne $CSVApp.DestinationAppName)
    {
        Write-Output "Renaming the Application to '$($CSVApp.DestinationAppName)'..."
        Get-CMApplication -Name $CSVApp.SourceAppName -Fast | Set-CMApplication -NewName $CSVApp.DestinationAppName
        Write-Output "Rename done."
    }
    

    #Check if there is content to copy
    $ExpectedContentSourcePath = $null
    $ExpectedContentSourcePath = Join-Path -Path $RootAppContentSourcePath -ChildPath ("$($CSVApp.FolderManufacturer)\$($CSVApp.FolderAppName)\$($CSVApp.FolderAppVersion)")

    if (Test-Path -Path "FileSystem::$ExpectedContentSourcePath")
    {
        # Content exists for this app
        $DestinationContentPath = $null
        $DestinationContentPath = Join-Path -Path $RootAppContentDestinationPath -ChildPath ("$($CSVApp.FolderManufacturer)\$($CSVApp.FolderAppName)\$($CSVApp.FolderAppVersion)")

        Write-Output "Creating the folders in the following path if any don't exist: '$DestinationContentPath'"
        New-Item -Path "FileSystem::$DestinationContentPath" -ItemType Directory -Force | Out-Null

        #Copy files
        Write-Output "Copying files from '$ExpectedContentSourcePath' to '$DestinationContentPath'"
        Copy-Item -Path "FileSystem::$ExpectedContentSourcePath\*" -Destination "FileSystem::$DestinationContentPath" -Recurse -Force
        Write-Output "Finished copying"


        #Update each Deployment Type's Content Location
        $DTs = @(Get-CMApplication -Name $CSVApp.DestinationAppName | Get-CMDeploymentType)

        foreach ($DT in $DTs)
        {
            $DTPath = $null
            $DTPath = Join-Path -Path $DestinationContentPath -ChildPath $DT.LocalizedDisplayName
            Write-Output "Setting Deployment Type '$($DT.LocalizedDisplayName)' content path to '$DTPath'"

            if ($DT.Technology -eq "MSI")
            {
                Set-CMMsiDeploymentType -ApplicationName $CSVApp.DestinationAppName -DeploymentTypeName $DT.LocalizedDisplayName -ContentLocation $DTPath
            }
            elseif ($DT.Technology -eq "Script")
            {
                Set-CMScriptDeploymentType -ApplicationName $CSVApp.DestinationAppName -DeploymentTypeName $DT.LocalizedDisplayName -ContentLocation $DTPath
            }
            else
            {
                Write-Output "ERROR: One of the Deployment Types on Application '$($CSVApp.DestinationAppName)' is not 'Script' or 'MSI'. This migration script is only able to handle Script and MSI deployment types. You'll need to fix this app (migrate the content) manually"
                continue
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($DistributionPointGroupName))
        {
            #Distribute content to DPs
            Write-Output "Distributing Application content to predefined DPs..."
            DistributeApplication -ApplicationName $CSVApp.DestinationAppName
            Write-Output "Distribution started."
        }
    }
    else
    {
        Write-Output "No content found to transfer for $($CSVApp.SourceAppName)"
    }
}

Stop-Transcript