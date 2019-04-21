<#
      .SYNOPSIS
      Allows users to easily to mount VMDKs from a Rubrik snapshot to another VM.
      Example below is for Kroll.
     
      .DESCRIPTION
      This script will set up a Kroll OnTrack recovery by using Rubrik to mount one or all VMDKs of a specific snapshot 
      to the Kroll OnTrack server. 
      This process makes use of the Rubrik PowerShell Module (https://github.com/rubrikinc/PowerShell-Module).
      Due to the nature of some of the disk mounting operations, the script also needs to be run in an elevated
      (Administrator) session. 
      Depending on the security context, the user might need to provide credentials for Rubrik.
      Please review the parameters below for more information.
      
      .NOTES
      Written by Pierre Flammer for community use
      Twitter: @PierreFlammer
      
      .PARAMETER
      -ATTENTION: Names have to match the names configured in Rubrik!!!
      SourceVM: Name of the Source VM (in this example Exchange VM)
      TargetVM: Name of the Target VM (in this example with Kroll OnTrack installed)
            
      .EXAMPLE
      .\VMDKRecovery.ps1 -TargetVM 'DEMO-KROLL2' -SourceVM 'DEMO-EXCH10-1' -RubrikCluster 172.17.28.15 
    
      .\VMDKRecovery.ps1 -TargetVM 'DEMO-KROLL2' -SourceVM 'DEMO-EXCH10-1' -RubrikCluster 172.17.28.15 -AllDisks -VLAN 50

  #>

#Requires -Modules Rubrik
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
     [string]$SourceVM
    ,[parameter(Mandatory=$true)]
     [string]$TargetVM
    ,[parameter(Mandatory=$false)]
     [Switch]$AllDisks
    ,[parameter(Mandatory=$true)]
     [string]$RubrikCluster
    ,[parameter(Mandatory=$false)]
     [int]$VLAN
    ,[pscredential]$RubrikCred=(Get-Credential -Message "Please enter your Rubrik credential:")
)
$ErrorActionPreference = 'Stop'

#connect to the Rubrik cluster
Connect-Rubrik -Server $RubrikCluster -Credential $RubrikCred | Out-Null
$reqdate = Read-Host 'Enter desired snapshot date (yyyy-mm-dd)' 

#Collect Snaps from selected date
$snaps = Get-RubrikVM -Name $SourceVM | Get-RubrikSnapshot | Where-Object {((get-date $_.date).Date -eq $reqdate)} | Sort-Object Date -Descending | Select-Object 

#Exit if no snapshots where found
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

#Get options for mount operation
$mode = 0
if ($PSBoundParameters.ContainsKey('VLAN')) {
    $mode += 1
}
if ($PSBoundParameters.ContainsKey('AllDisks')) {
    $mode += 2
}

#Mount Volumes to Kroll/Target Server from selected Snapshot
switch ($mode) {
    0{$result = New-RubrikVMDKMount -TargetVM $TargetVM -snapshotid $snaps[$selection].id}
    1{$result = New-RubrikVMDKMount -TargetVM $TargetVM -snapshotid $snaps[$selection].id -VLAN $VLAN}
    2{$result = New-RubrikVMDKMount -TargetVM $TargetVM -snapshotid $snaps[$selection].id -AllDisks}
    3{$result = New-RubrikVMDKMount -TargetVM $TargetVM -snapshotid $snaps[$selection].id -VLAN $VLAN -AllDisks}
}


#Output asking to cleanup after themselves
"`n--------------------------------" | Out-Host
"The VMDKs will be mounted on the TargetVM now." | Out-Host
"After you are done restoring, close Kroll Software and enter remove." | Out-Host
"This will clean up the created VMDK mounts." | Out-Host
"" | Out-Host

do {
  $input = Read-Host "To remove the created mounts enter ""remove"" now"
} until ($input -eq "remove")

#remove mounts from TargetHost to KrollServer
$TargetVMID = Get-RubrikVM -name $TargetVM
#$SourceVMID = Get-RubrikVM -name $SourceVM
Get-RubrikMount | Where-Object {$_.mountedVmId -eq $TargetVMID.id} | Remove-RubrikMount
