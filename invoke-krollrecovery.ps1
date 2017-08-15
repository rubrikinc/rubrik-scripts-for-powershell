
<#
      .SYNOPSIS
      Allows users to setup a Kroll recovery Rubrik.

      .DESCRIPTION
      This script will set up a Kroll OnTrack recovery by using Rubrik to create a VM Live Mount and then move
      the VMDKs from the the Live Mount to the Kroll OnTrack server. This process makes use of both the Rubrik
      PowerShell Module (https://github.com/rubrikinc/PowerShell-Module) and VMWare's PowerCLI (https://www.vmware.com/support/developer/PowerCLI/).
      Due to the nature of some of the disk mounting operations, the script also needs to be run in an elevated
      (Administrator) session. 

      Depending on the security context, the user might need to provide credentials for both Rubrik and VCenter.
      Please review the parameters below for more information.

      Once the script execution completes, there will be a notification for cleanup. Run the provided command in the output
      to cleanup the operation once the recovery work is done.

      .NOTES
      Written by Mike Fal for community use
      Twitter: @Mike_Fal
      GitHub: MikeFal

      .EXAMPLE
      .\KrollRecovery.ps1 -KrollServer 'DEMO-KROLL2' -ExchangeServer 'DEMO-EXCH10-1' -RubrikCluster 172.17.28.15 -VCenter demovcsa.rubrik.demo

      Execute the KrollRecovery script remotely.
      
      .EXAMPLE
      .\KrollRecovery.ps1 -ExchangeServer 'DEMO-EXCH10-1' -RubrikCluster 172.17.28.15 -VCenter demovcsa.rubrik.demo

      Execute the KrollRecovery script locally.
      
      .LINK
      https://github.com/rubrikinc/PowerShell-Module
      https://www.vmware.com/support/developer/PowerCLI/
  #>

#Requires -Modules Rubrik,VMware.VimAutomation.Core
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess = $true,ConfirmImpact = 'High')]
param(
     [string]$KrollServer = $env:COMPUTERNAME
    ,[parameter(Mandatory=$true)]
     [string]$TargetServer
    ,[parameter(Mandatory=$true)]
     [string]$RubrikCluster
    ,[parameter(Mandatory=$true)]
     [string]$VCenter
    ,[pscredential]$RubrikCred=(Get-Credential -Message "Please enter your Rubrik credential:")
    ,[pscredential]$VCenterCred
    ,[array]$DiskIDstoExclude

)

#Connect to the VCenter
if(-not $global:DefaultVIServers){
    if(-not $VCenterCred){$VCenterCred = Get-Credential -Message "Please enter your VCenter credential:" }
    Connect-VIServer -Server $VCenter -Credential $VCenterCred -Force | Out-Null
}


#connect to the Rubrik cluster
Connect-Rubrik -Server $RubrikCluster -Credential $RubrikCred | Out-Null

#Collect Snaps from the last 24 hours
$snaps = Get-RubrikVM -Name $TargetServer | Get-RubrikSnapshot | Where-Object {$_.date -gt (Get-Date).AddDays(-1)} | Sort-Object Date -Descending | Select-Object -First 10

#Choose snap to use
"Please select a snapshot to use:" | Out-Host
"--------------------------------" | Out-Host
$Snaps  | ForEach-Object -Begin {$i=0} -Process {"SnapID $i - $($_.Date)";$i++}
$selection = Read-Host 'Enter ID of selected snapshot'

#Move VMDKs from LiveMount of target to KROLL Server
$result = Move-RubrikMountVMDK -SourceVM $TargetServer -TargetVM $KrollServer -Date $snaps[$selection].date  -ExcludeDisk $DiskIDstoExclude -confirm:$false

#Output asking to cleanup after themselves
"`n--------------------------------" | Out-Host
"Once you have completed your work, please run the cleanup command: `n$($result.Example)" | Out-Host

#Perform disk cleanup on offline and read only disks
if($env:COMPUTERNAME -eq $KrollServer){
    Get-Disk | Where-Object {$_.IsOffline -eq $true} | Set-Disk -IsOffline $false;get-disk | Where-Object {$_.IsReadOnly -eq $true} | Set-Disk -IsReadOnly $false
} else {
    Invoke-Command -ComputerName $KrollServer -ScriptBlock {Get-Disk | Where-Object {$_.IsOffline -eq $true} | Set-Disk -IsOffline $false;get-disk | Where-Object {$_.IsReadOnly -eq $true} | Set-Disk -IsReadOnly $false}
}
