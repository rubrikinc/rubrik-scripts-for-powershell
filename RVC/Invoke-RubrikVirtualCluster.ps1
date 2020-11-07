<#
    .SYNOPSIS
        Deploys a Rubrik Virtual Cluster on VMware and adds data disks

    .DESCRIPTION
        This script deploy a Rubrik Virtual Cluster on VMware. It will also add the data disks to the cluster in VMware.
        This script requires that PowerCLI be installed and is in the users path.
        This script requires that OVFTool be installed in the users path. 

    .PARAMETER RVCDataDiskSize
        Size of RVC data disks to add. 

    .PARAMETER RVCDataDiskType
        RVC Data Disk Type to Add. The officially supported type is EagerZeroedThick. Thick and Thin can only be used for testing.

    .PARAMETER RVCDataNetwork
        The Data Network to attach RVC to. This is the name of the network or switch port in VMware.

    .PARAMETER RVCManagementNetwork
        The Management Network to attach RVC to. This is the name of the network or switch port in VMware.

    .PARAMETER RVCName
        Name of the Rubrik Virtual Cluster. Nodes will be named by adding a dash and increasing number will be appended during deployment.

    .PARAMETER RVCNumNodes
        Number of RVC Nodes to deploy.

    .PARAMETER RVCNumDataDisks
        Number of data disks to add to each node.

    .PARAMETER RVCOSDataDiskType
        The disk mode with which RVC will be deployed. The officially supported type is EagerZeroedThick. Thick and Thin can only be used for testing.
    
    .PARAMETER RVCOVAFile
        The OVA file to deploy RVC from.

    .PARAMETER VMwareCluster
        The VMware cluster in which to deploy RVC.

    .PARAMETER VMwareCredentialFile
        Credentials file for vCenter.
        Use the following commands to create a credentials file:

            $cred = Get-Credential
            $cred | Export-Clixml C:\temp\VMwareCred.xml -Force
    
    .PARAMETER VMwareDataCenter
        The VMware data center in which to deploy RVC.

    .PARAMETER VMwareDataStore
        The VMware datastore on which RVC will be deployed.

    .PARAMETER VMwareVCenter
        Hostname of the vCenter server.

    .PARAMETER VMwareVMFolder
        The VMware VM folder in which RVC will be deployed.
    
    .PARAMETER ConfigFile
        Configuration file with parameters.

    .PARAMETER RemoveCPUReservation
        (Experimental) Remove CPU Reservation.

    .INPUTS
        None
    .OUTPUTS
        None
    .EXAMPLE
        $cred = Get-Credential
        PS > $cred | Export-Clixml C:\temp\VMwareCred.xml -Force

    .EXAMPLE
        ./Invoke-RubrikVirtualCluster.ps1 -ConfigFile ./Sample-Invoke-RubrikVirtualClusterConfig.ps1
    
    .EXAMPLE
        ./Invoke-RubrikVirtualCluster.ps1 -RVCDataDiskSize 6144 -RVCDataDiskType "EagerZeroedThick" -RVCDataNetwork "myFastDataNetwork" -RVCManagementNetwork "myAwesomeManagementNetwork" -RVCName "myCoolClusterName" -RVCNumNodes 4 -RVCNumDataDisks 6 -RVCOSDiskType "EagerZeroedThick" -RVCOVAFile "rubrik-vc-vr6412-esx-5.3.0-123456.ova" -VMwareCluster "myNiceVMwareCluster" -VMwareCredentialFile "myFantasticVCenterCreds.xml" -VMwareDataCenter "myLovelyVMwareDataCenter" -VMwareDataStore "myBigDataStore" -VMwareVCenter "myFantasticVCenter" -VMwareVMFolder "myStupendousVMFolderDir/myGreatVMFolderName"

    .LINK
        https://github.com/rubrikinc/rubrik-scripts-for-powershell
    .LINK
        https://www.vmware.com/support/developer/PowerCLI/
    .LINK
        https://code.vmware.com/web/tool/4.4.0/ovf

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
    [String] $VMwareCredentialFile,    
    
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

    [Parameter(Mandatory = $false, HelpMessage = "(Experimental) Remove CPU Reservation.")]
    [switch] $RemoveCPUReservation = $false

)

if ($ConfigFile) {
    . $ConfigFile
}

if ($null -eq (Get-Command "ovftool.exe" -ErrorAction SilentlyContinue) -And $null -eq (Get-Command "ovftool" -ErrorAction SilentlyContinue)) { 
    Write-Host "Unable to find ovftool in your PATH."
    Write-Host "Verify that ovftool is installed."
    exit 1
}

if ($null -eq (Get-Command "Connect-VIServer" -ErrorAction SilentlyContinue)) { 
    Write-Host "Unable to find Connect-VIServer in your PATH"
    Write-Host "Make sure that PowerCLI is installed."
    exit 1
}

Import-Module VMware.VimAutomation.Core

$VMwareCreds = Import-CliXml -Path $VMwareCredentialFile
Connect-VIServer $VMwareVCenter -Credential $VMwareCreds

for ($myRVCNum = 1; $myRVCNum -le $RVCNumNodes; $myRVCNum++) {

    $myRVCName = "$RVCName-$myRVCNum"
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
