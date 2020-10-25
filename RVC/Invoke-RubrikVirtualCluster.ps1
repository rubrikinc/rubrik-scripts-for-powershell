<#
    .SYNOPSIS
        Will deploy a 4 node Rubrik Virtual Cluster on VMware

    .DESCRIPTION
        Will deploy a Rubrik Virtual Cluster on VMware.
        This script requires that PowerCLI be installed and is in the users path.

    .PARAMETER JobFile
        None

    .INPUTS
        Required to updated the following parameters:
            $Username - This will be a vCD Admin User
            $Password - This will be a vCD Admin User Password
            $vCDHost - The address of the vCD Cell you want to export the metadata for

    .OUTPUTS
        None
    .EXAMPLE
        Creating credentials file: 
            $cred = Get-Credential
            $cred | Export-Clixml C:\temp\VMwareCred.xml -Force

        Deploying RVC:
        ./Invoke-RubrikVirtualCluster.ps1 options

    .LINK
        None

    .NOTES
        Name:       Deploy Rubrik Virtual Cluster (RVC)
        Created:    October 23, 2020
        Author:     Damani Norman

#>

#Requires -Modules VMware.VimAutomation.Core

param
(
    [Parameter(Mandatory = $true, HelpMessage = "The disk mode with which RVC will be deployed.")]
    [ValidateSet("EagerZeroedThick", "Thick", "Thin")]
    [string] $DiskMode = 'EagerZeroedThick',
    
    [Parameter(Mandatory = $true, HelpMessage = "The VMware datastore on which RVC will be deployed.")]
    [string] $DataStore,

    [Parameter(Mandatory = $true, HelpMessage = "The VMware VM folder in which RVC will be deployed.")] 
    [string] $VMFolder,

    [Parameter(Mandatory = $true, HelpMessage = "The Data Network to attach RVC to.")]
    [string] $DataNetwork,
    
    [Parameter(Mandatory = $true, HelpMessage = "The Management Network to attach RVC to.")] 
    [string] $ManagementNetwork,
    
    [Parameter(Mandatory = $true, HelpMessage = "The prefix to use for each of the node names. A dash and increasing number will be appended during deployment.")]
    [string] $NodeNamePrefix,

    [Parameter(Mandatory = $true, HelpMessage = "The VMware data center in which to deploy RVC.")]
    [string] $VMwareDataCenter,

    [Parameter(Mandatory = $true, HelpMessage = "The VMware cluster in which to deploy RVC.")]
    [string] $VMwareCluster,

    [Parameter(Mandatory = $true, HelpMessage = "The OVA file to deploy RVC from.")]
    [string] $OVAFile,

    [Parameter(Mandatory = $true, HelpMessage = "Credentials file for vCenter. ")]
    [string] $VMwareCredentialFile,    
    
    [Parameter(Mandatory = $true, HelpMessage = "Hostname of the vCenter server. ")]
    [string] $VCenter,

    [Parameter(Mandatory = $true, HelpMessage = "Data Disk Type to Add.")]
    [ValidateSet("EagerZeroedThick", "Thick", "Thin")]
    [string] $DataDiskType = 'EagerZeroedThick',

    [Parameter(Mandatory = $true, HelpMessage = "Size of data disks to add.")]
    [string] $DataDiskSize,
    
    [Parameter(Mandatory = $true, HelpMessage = "Number of data disks to add to each node.")]
    [int] $NumDataDisks = 6,

    [Parameter(Mandatory = $true, HelpMessage = "Number of RVC Nodes to deploy.")]
    [int] $NumRVCNodes = 4,

    [Parameter(Mandatory = $false, HelpMessage = "Remove CPU Reservation.")]
    [switch] $RemoveCPUReservation = $false

)

Import-Module VMware.VimAutomation.Core

$VMwareCreds = Import-CliXml -Path $VMwareCredentialFile
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore
Connect-VIServer $VCenter -Credential $VMwareCreds
# $myDataCenter = Get-Datacenter -Name $VMwareDataCenter
$myCluster = Get-Cluster -Name $VMwareCluster
$myVMHosts = $myCluster | Get-VMHost
$myVMHost = $myVMHosts | Select-Object -First 1
$myDatastore = Get-Datastore -Name $DataStore
$myVMFolder = Get-Folder -Name $VMFolder

for ($myRVCNum = 1; $myRVCNum -le $NumRVCNodes; $myRVCNum++) {

    $ovfConfig = Get-OvfConfiguration $ovaFile
    $ovfConfig.NetworkMapping.Management_Network.Value = $ManagementNetwork
    $ovfConfig.NetworkMapping.Data_Network.Value = $DataNetwork
    $myRVCName = "$NodeNamePrefix-$myRVCNum"
    Import-VApp -Source $OVAFile `
        -VMHost $myVMHost `
        -Name $myRVCName `
        -Datastore $myDatastore `
        -DiskStorageFormat $DiskMode `
        -InventoryLocation $myVMFolder `
        -Location $myCluster `
        -OvfConfiguration $ovfConfig
    $myVM = Get-VM $myRVCName
    for ($myRVCDiskNum = 1; $myRVCDiskNum -le $NumDataDisks; $myRVCDiskNum++) {
        $myVM | New-HardDisk -CapacityGB $DataDiskSize -StorageFormat $DataDiskType 
    }
    switch ( $true ) {
        $RemoveCPUReservation {
            $myVM | Get-VMResourceConfiguration | Set-VMResourceConfiguration -CpuReservationMhz 0
        }
    }
    $myVM | Start-VM
}
