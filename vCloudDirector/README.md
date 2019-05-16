### vCD Metadata Scripts

This folder provides 2 scripts to allow the backing up of vApp Metadata which runs on a Management VM as part of pre-script activity within Rubrik.

## Config

Drop both scripts into a folder in a known location of the management VM
Create a new folder called `Exports` in the same directory as both scripts
Browse to the VM in Rubrik
Click on the Elipses in the top right and select `Configure Pre/Post Scripts`
In the `Pre-Backup Script`, add the path to the `backup_vcd_vapp_metadata.ps1` script e.g. `C:\Scripts\backup_vcd_vapp_metadata.ps1`
Set a timeout window, suggested 30-180 seconds depending on amount of metadata
Apply the Pre-Script

Once this VM is backed up, we will now store the current Metadata across the vCD Cell.

## Restore

Since we have backed up the metadata, we can restore the CSV from anypoint by either file level recovery for the date, or browsing the `Exports` folder.
Run the `restore_vcd_vapp_metadata.ps1` script which will prompt a file open wizard; browse and select the CSV file to restore from
It will now prompt for which metadata you want to restore, following the commands on-screen.