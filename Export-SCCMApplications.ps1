$ErrorActionPreference = "Stop"


#######################################################################
#
#   Step 1 - You MUST change these values to match your environment.
#
#######################################################################
$SCCMSiteCode = "PR1"   # SCCM Site code you are exporting FROM
$ProviderMachineName = "SCCM-01"   # Machine name of the SCCM server that has the SMS Provider service installed.


#######################################################################
#
#   Step 2 - OPTIONAL: Change these if you desire.
#
#######################################################################
$LogFilePath = "$($env:USERPROFILE)\Desktop\SCCMAppMigration-Export.log"    # Where this script will log to
$AppsToProcessCsvPath = "$(Split-Path $MyInvocation.MyCommand.Path)\ToProcess.csv"    # The list of SCCM Applications that will be searched for and exported, as well as the export configuration.
$RootAppInfoExportPath = "$(Split-Path $MyInvocation.MyCommand.Path)\AppInfo"       # Where Application exports will be saved to (meta data only, no content)
$RootAppContentExportPath = "$(Split-Path $MyInvocation.MyCommand.Path)\Content"    # Where Application content will be copied to




Function ApplicationHasDependencies($ApplicationName)
{
    $AppDeploymentInfo = $null
    $AppDeploymentInfo = Get-CMDeploymentType -ApplicationName $ApplicationName

    if ($AppDeploymentInfo.NumberOfDependedDTs -gt 0)
    {
        return $true
    }
    else
    {
        return $false
    }
}

Function Display-AppsWithDependencies([string[]]$ApplicationNames)
{
    Write-Output ""
    foreach ($Application in $ApplicationNames)
    {
        Write-Output "Warning: '$Application' has dependencies which will need to have their CONTENT fixed manually. The dependent apps will be created in the destination SCCM (when you run the Import script) but the content needs to be migrated and fixed manually."
    }
}

Function AppCSVDataIsValid($AppCSV)
{
    if ([string]::IsNullOrWhiteSpace($AppCSV.SourceAppName) -or
        [string]::IsNullOrWhiteSpace($AppCSV.DestinationAppName) -or
        [string]::IsNullOrWhiteSpace($AppCSV.FolderManufacturer) -or
        [string]::IsNullOrWhiteSpace($AppCSV.FolderAppName) -or
        [string]::IsNullOrWhiteSpace($AppCSV.FolderAppVersion)
    )
    {
        return $false
    }
    else
    {
        return $true
    }
}

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

Function AppHasSCCMContent($ApplicationName)
{
    return (Get-CMApplication -Name $ApplicationName -Fast).HasContent
}

Function ExportAppContent($ApplicationName, $DestinationPath)
{
    $App = $null
    $App = Get-CMApplication -Name $ApplicationName
    [xml]$Xml = $null
    [xml]$Xml = $App.SDMPackageXML

    if ($Xml.AppMgmtDigest.DeploymentType.Count -eq 0)
    {
        Write-Output "No Deployment Types found. No content to transfer."
        return
    }

    foreach ($DT in $Xml.AppMgmtDigest.DeploymentType)
    {
        #Create a folder for each DT, with the DisplayName as the folder name
        Write-Output "Creating the content folder for Deployment Type '$($DT.Title.'#text')'"
        $DTContentPath = Join-Path -Path $DestinationPath -ChildPath $DT.Title.'#text'
        New-Item -Path "FileSystem::$DTContentPath" -ItemType Directory -Force | Out-Null

        #Copy files
        Write-Output "Copying files from '$($DT.Installer.Contents.Content.Location)' to '$DTContentPath'"
        Copy-Item -Path "FileSystem::$($DT.Installer.Contents.Content.Location)\*" -Destination "FileSystem::$DTContentPath" -Recurse -Force

        Write-Output "Finished copying"
    }

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


Start-Transcript -Path $LogFilePath -Append

cd "$($env:SystemDrive)\"
Write-Output "Reading CSV for apps to process..."
$CSVApps = Import-Csv -Path $AppsToProcessCsvPath
cd "$($SCCMSiteCode):\"

Write-Output "Read $($CSVApps.Count) apps from CSV file"

$AppsThatHaveDependencies = @() #This gets output at the end of the script

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

    $AppInfoExportPath = $null
    $AppContentExportPath = $null

    $AppInfoExportPath = Join-Path -Path $RootAppInfoExportPath -ChildPath $CSVApp.SourceAppName
    $AppContentExportPath = Join-Path -Path $RootAppContentExportPath -ChildPath ("$($CSVApp.FolderManufacturer)\$($CSVApp.FolderAppName)\$($CSVApp.FolderAppVersion)")


    # Check if this app has already been processed by this script previously by checking for the App Info and App Content folders
    if (Test-Path "FileSystem::$AppInfoExportPath")
    {
        Write-Output "ERROR: the path used to store this Application's information already exists ('$AppInfoExportPath'). This indicates this application has already been migrated, so it will be skipped."
        continue;
    }

    if (Test-Path "FileSystem::$AppContentExportPath")
    {
        Write-Output "ERROR: the path used to store this Application's content already exists ('$AppContentExportPath'). This indicates this application has already been migrated, so it will be skipped."
        continue;
    }


    Write-Output "Creating the App Info export folder '$AppInfoExportPath'"
    New-Item -Path "FileSystem::$AppInfoExportPath" -ItemType Directory -Force | Out-Null


    # Confirm the app exists in the Source SCCM
    if (-not (AppExistsInSCCM -ApplicationName $CSVApp.SourceAppName))
    {
        Write-Output "ERROR: $($CSVApp.SourceAppName) couldn't be found in SCCM. Skipping this application."
        continue;
    }

    # Check if the app has dependencies and add it to the list if it does
    if (ApplicationHasDependencies -ApplicationName $CSVApp.SourceAppName)
    {
        $AppsThatHaveDependencies += $CSVApp.SourceAppName
    }

    # Export the App (no content exported)
    Write-Output "Exporting the app meta data..."
    $ExportPath = Join-Path -Path $AppInfoExportPath -ChildPath "$($CSVApp.SourceAppName).zip"
    Export-CMApplication -Name $CSVApp.SourceAppName -Path $ExportPath -OmitContent -Comment "Exported by automation script on $((Get-Date).ToLocalTime())"
    
    if (-not (Test-Path "FileSystem::$ExportPath"))
    {
        Write-Output "ERROR: The export process did not throw an error, however, the file that is expected to exist after an export ('$ExportPath') does not exist. The export must have failed silently. Application not migrated."
        continue;
    }
    else
    {
        Write-Output "Metadata export finished."
    }


    # Content handling

    # Check if the app has content
    if (AppHasSCCMContent -ApplicationName $CSVApp.SourceAppName)
    {
        # Create the content destination folder structure
        Write-Output "Creating the App Content export folder '$AppContentExportPath'"
        New-Item -Path "FileSystem::$AppContentExportPath" -ItemType Directory -Force | Out-Null

        # Copy content 
        ExportAppContent -ApplicationName $CSVApp.SourceAppName -DestinationPath $AppContentExportPath
    }
    else
    {
        Write-Output "Application doesn't have content."
    }


}


Display-AppsWithDependencies -ApplicationNames $AppsThatHaveDependencies

Stop-Transcript