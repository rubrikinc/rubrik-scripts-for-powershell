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
    [Parameter(Mandatory = $true, HelpMessage = "Size of RVC data disks to add.",
        ParameterSetName = "Command Line")]
    [string] $RVCDataDiskSize,

    [Parameter(Mandatory = $true, HelpMessage = "RVC Data Disk Type to Add.",
        ParameterSetName = "Command Line")]
    [ValidateSet("EagerZeroedThick", "Thick", "Thin")]
    [string] $RVCDataDiskType = 'EagerZeroedThick',
    
    [Parameter(Mandatory = $true, HelpMessage = "The Data Network to attach RVC to.",
        ParameterSetName = "Command Line")]
    [string] $RVCDataNetwork,

    [Parameter(Mandatory = $true, HelpMessage = "The Management Network to attach RVC to.",
        ParameterSetName = "Command Line")] 
    [string] $RVCManagementNetwork,

    [Parameter(Mandatory = $true, HelpMessage = "Name of the Rubrik Virtual Cluster. Nodes will be named by adding a dash and increasing number will be appended during deployment.",
        ParameterSetName = "Command Line")]
    [string] $RVCName,

    [Parameter(Mandatory = $true, HelpMessage = "Number of RVC Nodes to deploy.",
        ParameterSetName = "Command Line")]
    [int] $RVCNumNodes = 4,

    [Parameter(Mandatory = $true, HelpMessage = "Number of data disks to add to each node.",
        ParameterSetName = "Command Line")]
    [int] $RVCNumDataDisks = 6,

    [Parameter(Mandatory = $true, HelpMessage = "The disk mode with which RVC will be deployed.",
        ParameterSetName = "Command Line")]
    [ValidateSet("EagerZeroedThick", "Thick", "Thin")]
    [string] $RVCOSDataDiskType = 'EagerZeroedThick',
    
    [Parameter(Mandatory = $true, HelpMessage = "The OVA file to deploy RVC from.",
        ParameterSetName = "Command Line")]
    [string] $RVCOVAFile,

    [Parameter(Mandatory = $true, HelpMessage = "The VMware cluster in which to deploy RVC.",
        ParameterSetName = "Command Line")]
    [string] $VMwareCluster,

    [Parameter(Mandatory = $true, HelpMessage = "Credentials file for vCenter.",
        ParameterSetName = "Command Line")]
    [string] $VMwareCredentialFile,    
    
    [Parameter(Mandatory = $true, HelpMessage = "The VMware data center in which to deploy RVC.",
        ParameterSetName = "Command Line")]
    [string] $VMwareDataCenter,

    [Parameter(Mandatory = $true, HelpMessage = "The VMware datastore on which RVC will be deployed.",
        ParameterSetName = "Command Line")]
    [string] $VMwareDataStore,

    [Parameter(Mandatory = $true, HelpMessage = "Hostname of the vCenter server.",
        ParameterSetName = "Command Line")]
    [string] $VMwareVCenter,

    [Parameter(Mandatory = $true, HelpMessage = "The VMware VM folder in which RVC will be deployed.",
        ParameterSetName = "Command Line")] 
    [string] $VMwareVMFolder,
    
    [Parameter(Mandatory = $true, HelpMessage = "Configuration file with parameters.",
        ParameterSetName = "Config File")]
    [string] $ConfigFile,

    [Parameter(Mandatory = $false, HelpMessage = "Remove CPU Reservation.")]
    [switch] $RemoveCPUReservation = $false

)

if ($ConfigFile) {
    . $ConfigFile
}

Import-Module VMware.VimAutomation.Core

$VMwareCreds = Import-CliXml -Path $VMwareCredentialFile
Connect-VIServer $VMwareVCenter -Credential $VMwareCreds
# $myDataCenter = Get-Datacenter -Name $VMwareDataCenter
# $myCluster = Get-Cluster -Name $VMwareCluster
# $myVMHosts = $myCluster | Get-VMHost
# $myVMHost = $myVMHosts | Select-Object -First 1
# $myDatastore = Get-Datastore -Name $DataStore
# $myVMFolder = Get-Folder -Name $VMFolder

for ($myRVCNum = 1; $myRVCNum -le $RVCNumNodes; $myRVCNum++) {

    $myRVCName = "$RVCName-$myRVCNum"
    # $ovfConfig = Get-OvfConfiguration $ovaFile
    # $ovfConfig.NetworkMapping.Management_Network.Value = $ManagementNetwork
    # $ovfConfig.NetworkMapping.Data_Network.Value = $DataNetwork
    # Import-VApp -Source $OVAFile `
    #     -VMHost $myVMHost `
    #     -Name $myRVCName `
    #     -Datastore $myDatastore `
    #     -DiskStorageFormat $DiskMode `
    #     -InventoryLocation $myVMFolder `
    #     -Location $myCluster `
    #     -OvfConfiguration $ovfConfig
    $myVMwareUsername = $VMwareCreds.UserName
    $myVMwarePassword = $VMwareCreds.GetNetworkCredential().password
    ovftool --acceptAllEulas --powerOffTarget --noSSLVerify --allowExtraConfig `
        --diskMode=$RVCOSDiskType `
        --name=$myRVCName `
        --datastore=$VMwareDataStore `
        --vmFolder="$VMwareVMFolder" `
        --net:"Management Network"="$RVCManagementNetwork" `
        --net:"Data Network"="$RVCDataNetwork" `
        $RVCOVAFile `
        "vi://${myVMwareUsername}:${myVMwarePassword}@${VMwareVCenter}/${VMwareDataCenter}/host/${VMwareCluster}"
    $myVM = Get-VM $myRVCName
    for ($myRVCDiskNum = 1; $myRVCDiskNum -le $RVCNumDataDisks; $myRVCDiskNum++) {
        $myVM | New-HardDisk -CapacityGB $RVCDataDiskSize -StorageFormat $RVCDataDiskType 
    }
    switch ( $true ) {
        $RemoveCPUReservation {
            $myVM | Get-VMResourceConfiguration | Set-VMResourceConfiguration -CpuReservationMhz 0
        }
    }
    $myVM | Start-VM
}

# Bootstrap cluster
# Set Cluster Location
# Add vCenter
# Register with Polaris