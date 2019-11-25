<#

.SYNOPSIS

This PowerShell script will perform on demand snapshots of clients in one SLA to another SLA. The intent is to 
archive snapshots on a periodic basis such as Monthly or Yearly using a customer defined schedule.

.DESCRIPTION

This PowerShell script will perform on demand snapshots of clients in one SLA to another SLA. The intent is to 
archive snapshots on a periodic basis such as Monthly or Yearly using a customer defined schedule. This script
works by interrogating a an SLA for its clients and then taking an on demand snapshot of them using a second
SLA. Monthly or Yearly archiving can be accomplished by setting the target SLA to retain a monthly or yearly
snapshot for the period desired. Data can be moved to an archive by setting the target SLA to replicate or 
archive the data. Use the On Brik slider to decide when the data is moved off of the Brik.

Scheduling of the snapshots is done by using a job scheduler to invoke this script at the desired intervals. 
For example if Yearly snapshots are desired on the first day of the year, the job scheduler is set to execute
this script on the first day of the year. 

This script will archive data from one SLA. If archiving from multiple SLAs is required, execute this script
against each SLA. 

.EXAMPLE

.\invoke-archive.ps1 -SLADomains "Source SLA 1","Source SLA 2" -targetSLADomain "Target SLA" -creds .\RubrikCred.xml -rubrikNode 192.168.1.10

.NOTES

To prepare to use this script complete the following steps:

1) Download the Rubrik Powershell module from Github or the Powershell Library.
  a) Install-Module Rubrik
  b) Import-Module Rubrik
  c) Get-Command -Module Rubrik
  d) Get-Command -Module Rubrik *RubrikDatabase*
  e) Get-Help Get-RubrikVM -ShowWindow
  f) Get-Help New-RubrikMount -ShowWindow
  g) Get-Help Get-RubrikRequest -ShowWindow

2) Create a credentials file for the Rubrik Powershell Module with your administrative Rubrik username and password.
  a) $cred = Get-Credential
    i) Enter the Rubrik Administrator credentials to use for this script.
  b) $cred | Export-Clixml C:\temp\RubrikCred.xml -Force
3) Create a target SLA which will capture, retain and archive snapshots using the desired retention.
4) Invoke this script to create on demand snapshots from SLAs.

This script requires:

- Powershell 5.1
- Rubrik PowerShell Module
- Rubrik PowerShell Credentials File

.LINK
https://github.com/rubrik-devops/powershell-scripts/invoke-archive.ps1
https://github.com/rubrikinc/PowerShell-Module

#>

[CmdletBinding()]
param(
  # The Rubrik SLA Policy to take snapshots from
  [Parameter(Mandatory = $True,
    HelpMessage = "Enter one or more source SLA Domains separated by commas.")]
  [array]$SLADomains,

  # The target SLA to use for making the On Demand Snapshot
  [Parameter(Mandatory = $True,
    HelpMessage = "Enter the target SLA Domain.")]
  [string]$targetSLADomain,

  # The credentials file for Rubrik
  [Parameter(Mandatory = $True,
    HelpMessage = "Enter the Rubrik credentials file name.")]
  [string]$creds,

  # The IP address or hostname of a node in the Rubrik cluster.
  [Parameter(Mandatory = $True,
    HelpMessage = "Enter the IP address or hostname of a node in the Rubrik Cluster.")]
  [string]$rubrikNode
)

#Load Rubrik module and connect
Import-Module Rubrik

# Connect to Rubrik cluster
Connect-Rubrik -Server $rubrikNode -Credential (Import-Clixml $creds)

#Set starting parameters
$Snappables = @()

#For each domain, attempt to take on demand snapshot to archival SLA DOMAIN
write-host ("")
Write-Host ("Gathering snappables from SLA Domain $SLA...")
foreach ($SLA in $SLADomains) {
  
  Write-Host (".....Getting Filesets that are not Passthrough...")
  $Snappables += (Get-RubrikFileset -SLA $SLA -PrimaryClusterID local | Where-Object {$_.isPassthrough -eq $false})

  Write-Host (".....Getting SQL Server Databases...")
  $Snappables += Get-RubrikDatabase -SLA $SLA -PrimaryClusterID local
    
  Write-Host (".....Getting Oracle Databases...")
  $Snappables += Get-RubrikOracleDB -SLA $SLA -PrimaryClusterID local

  Write-Host (".....Getting VMWare VMs...")  
  $Snappables += Get-RubrikVM -SLA $SLA -PrimaryClusterID local
  
  Write-Host (".....Getting VMWare VCD VAPPS...")  
  $Snappables += Get-RubrikVApp -SLA $SLA -PrimaryClusterID local

  Write-Host (".....Getting Hyper-V VMs...")  
  $Snappables += Get-RubrikHyperVVM -SLA $SLA -PrimaryClusterID local

  Write-Host (".....Getting Nutanix VMs...")  
  $Snappables += Get-RubrikNutanixVM -SLA $SLA -PrimaryClusterID local
  
  Write-Host (".....Getting Volume Groups...")  
  $Snappables += Get-RubrikVolumeGroup -SLA $SLA -PrimaryClusterID local
    
}
#Loop through each snappable and take an On Demand Snapshot

#renew Rubrik connection in case snapshot took too long
Connect-Rubrik -Server $rubrikNode -Credential (Import-Clixml $creds) | Out-Null
foreach ($Snap in $Snappables) {
  write-host ("Taking snapshot of $($snap.name)...")
  $snap | New-RubrikSnapshot -SLA $targetSLADomain -Confirm:$false 
}
#-------------------------------------------------------------------------------
# Now lets go after managed volumes
# Managed Volumes are not snappables so they need to be handled differently than the above
foreach ($SLA in $SLADomains) {
  $ManagedVolumes += Get-RubrikManagedVolume -SLA $SLA  -PrimaryClusterID local
}
# #renew Rubrik connection in case snapshot took too long
Connect-Rubrik -Server $rubrikNode -Credential (Import-Clixml $creds) | Out-Null
foreach ($MV in $ManagedVolumes) {
  write-host ("Taking snapshot of $($MV.name)...")
  Start-RubrikManagedVolumeSnapshot -id $MV.id
  Stop-RubrikManagedVolumeSnapshot -id $MV.id -SLA $targetSLADomain
}
