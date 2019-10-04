<#
      .SYNOPSIS
      Allows users to easily to mount volumes from a backup to another server.
      Example below is for Kroll.
      .DESCRIPTION
      This script will set up a Kroll OnTrack recovery by using Rubrik to mount Windows Volumes of a specific snaphsot to the Kroll OnTrack server. 
      This process makes use of the Rubrik PowerShell Module (https://github.com/rubrikinc/PowerShell-Module).
      Due to the nature of some of the disk mounting operations, the script also needs to be run in an elevated
      (Administrator) session. 
      Depending on the security context, the user might need to provide credentials for Rubrik.
      Please review the parameters below for more information.
      The volumes are mountedn in c:\rubrik-mounts\Drive-<driveletter>
      If the folder c:\rubrik-mounts is not empty the script will exit.
      This is necessary, because if a folder with the same name already exists, the mount option will fail.
      
      .NOTES
      Written by Pierre Flammer for community use (thanks to Mike Fal!)
      Twitter: @PierreFlammer
      
      .PARAMETER
      -ATTENTION: Names have to match the names configured in Rubrik!!!
      KrollServer: Name of the Kroll Server. Needs to have RBS installed.
      -TargetServer: The name of the Server that is being backed up with 
      Rubrik and contains the volumes we want to mount.
      
      .EXAMPLE
      .\VolumeRecovery.ps1 -KrollServer 'DEMO-KROLL2' -TargetServer 'DEMO-EXCH10-1' -RubrikCluster 172.17.28.15 
      Execute the Recovery script remotely.
      
      .EXAMPLE
      .\VolumeRecovery.ps1 -TargetServer 'DEMO-EXCH10-1' -RubrikCluster 172.17.28.15 
      Execute the Recovery script locally.
      .EXAMPLE
      .\VolumeRecovery.ps1 -TargetServer 'DEMO-EXCH10-1' -RubrikCluster 172.17.28.15 -DrivesToExclude C,D
      Execute the script locally and but don't mount Drive C & D from TargetServer
  #>

#Requires -Modules Rubrik
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess = $true,ConfirmImpact = 'High')]
param(
     [string]$KrollServer = $env:COMPUTERNAME
    ,[parameter(Mandatory=$true)]
     [string]$TargetServer
    ,[parameter(Mandatory=$true)]
     [string]$RubrikCluster
    ,[pscredential]$RubrikCred=(Get-Credential -Message "Please enter your Rubrik credential:")
    ,[array]$DrivestoExclude

)
$ErrorActionPreference = 'Stop'

#It is necessary that the folder  c:\rubrik-mounts\ is empty.
#If a matching folder still exists from a previous mount, the mount will fail.
$directoryInfo = Get-ChildItem c:\rubrik-mounts\ | Measure-Object
if ($directoryInfo.count -ne 0) {
    "`n--------------------------------" | Out-Host
    "The Folder c:\rubrik-mounts\ is not empty." | Out-Host
    "To avoid error during the mount, please delete all the content in this folder and execute the script again." | Out-Host
    "`n--------------------------------" | Out-Host
    Exit
}

#connect to the Rubrik cluster
Connect-Rubrik -Server $RubrikCluster -Credential $RubrikCred | Out-Null
$reqdate = Read-Host 'Enter desired snapshot date (yyyy-mm-dd)' 

#Collect Snaps from the last 24 hours
#Want a date range, show backups between 
#$snaps = Get-RubrikVolumeGroup -Name $TargetServer | Get-RubrikSnapshot | Where-Object {((get-date $_.date).Date -eq $reqdate)} | Sort-Object Date -Descending | Select-Object 
$snaps = Get-RubrikVolumeGroup | Where hostname -eq $TargetServer | Get-RubrikSnapshot | Where-Object {((get-date $_.date).Date -eq $reqdate)} | Sort-Object Date -Descending | Select-Object 

#Exit if now snapshots where found
if (-not ($snaps)) {
    "`n--------------------------------" | Out-Host
    "The specified parameters did not return any snapshots that can be used." | Out-Host    
    "Please doublecheck the TargetServer and the date you selected." | Out-Host    
    "`n--------------------------------" | Out-Host
    Exit
}

#Choose snap to use
"Please select a snapshot to use:" | Out-Host
"--------------------------------" | Out-Host
$Snaps  | ForEach-Object -Begin {$i=0} -Process {"SnapID $i - $(get-date $_.Date)";$i++}
$selection = Read-Host 'Enter ID of selected snapshot'

#Mount all Volumes to Kroll/Target Server from selected Snapshot
$result = New-RubrikVolumeGroupMount -TargetHost $KrollServer -VolumeGroupSnapshot $snaps[$selection] -ExcludeDrives $DrivestoExclude -Confirm:$false

#Mount is in process
"`n--------------------------------" | Out-Host
$directoryInfo = Get-ChildItem c:\rubrik-mounts\ | Measure-Object
while ($directoryInfo.count -eq 0) {
    start-sleep 3
    "The mount was initialized. Please wait..." | Out-Host
    $directoryInfo = Get-ChildItem c:\rubrik-mounts\ | Measure-Object
}

#Output asking to cleanup after themselves
"`n--------------------------------" | Out-Host
"The Volume Group was mounted on Host " + $TargetServer | Out-Host
"After you are done restoring, close Kroll Software and enter remove." | Out-Host
"This will clean up the created volume group mounts" | Out-Host

do {
  $input = Read-Host "To remove the created mounts enter ""remove"" now"
} until ($input -eq "remove")

#remove mounts from TargetHost to KrollServer
Get-RubrikVolumeGroupMount -source_host $TargetServer | Where-Object {$_.targetHostName -eq $KrollServer} | Remove-RubrikVolumeGroupMount -Confirm:$false
