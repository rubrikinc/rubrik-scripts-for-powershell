<#
.NOTES

Author: Joe Harlan (Rubrik)
Development Platform: 
    Operating System: macOS 12.0.1 (Monterey)
    PowerShell: 7.2.0 (Homebrew installed)
    PowerCLI: 12.4.1 (Install-Module -Name VMware.PowerCLI)
        VMware Common PowerCLI Component 12.4 build 18627061
        VMware Cis Core PowerCLI Component PowerCLI Component 12.4 build 18627057
        VMware VimAutomation VICore Commands PowerCLI Component PowerCLI Component 12.4 build 18627056

.SYNOPSIS

Used to remove from vCenter inventory, and optionally delete from disk,
any VM's renamed as 'Deprecated_*' after an AppFlows failover event is
completed.

.DESCRIPTION

After launching a real Failover event where both source and target site
Rubrik clusters and vSphere environments were still online, AppFlows
renames the VM's in the source site as 'deprecated'. This script may be
used to remove them after the fact and reduce the burden of doing so.

.PARAMETER VIServer
[REQUIRED] vCenter instance managing the source site.

.PARAMETER Delete
[OPTIONAL] In addition to removing from vCenter inventory, this option 
will also delete the deprecated VM's files from disk.
!!USE WITH CAUTION!!

.PARAMETER IgnoreVICert
[OPTIONAL] Used to ignore vCenter Server certificate warnings/errors 
upon connection.  Great for lab environments, not ideal for production.

.INPUTS

None; pipes not supported

.OUTPUTS

None; pipes not supported

.EXAMPLE

PS > .\AF-Failover-Cleanup.ps1 -VIServer vcsa.rubrik.lab

.EXAMPLE

PS > .\AF-Failover-Cleanup.ps1 -VIServer vcsa.rubrik.lab -IgnoreVICert -Delete

This script will remove all VMs renamed as Deprecated after an AppFlows failover event.

You will be prompted to provide credentials for a vCenter account with sufficient privileges. 

Specify Credential
Please specify server credential
User: joe.harlan.adm@rubrik.lab
Password for user joe.harlan.adm@rubrik.lab: **********

Name                 PowerState Num CPUs MemoryGB
----                 ---------- -------- --------
Deprecated_Server01  PoweredOff 2        8.000
Deprecated_Server02  PoweredOff 2        8.000
Deprecated_Server03  PoweredOff 2        8.000

Please confirm you wish to continue with the removal of the above listed VMs (yes or no): yes

The VMs will now be removed...please be patient as this is run synchronously.
Perform operation?
Performing operation 'Removing VM from inventory.' on VM 'Deprecated_Server01'
[Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Yes"): A
                                                                                                                        
Disconnecting from vCenter at vcsa.rubrik.lab

#>

param (
    [string]$VIServer,
    [parameter(Mandatory=$false)]
    [switch]$Delete,
    [parameter(Mandatory=$false)]
    [switch]$IgnoreVICert
)

Clear-Host

$usage = "./AF-Failover-Cleanup.ps1 -VIServer <vCenter IP or FQDN> [-IgnoreVICert] [-Delete]"

# Check to make sure a vCenter Server is included in the parameters
if ( !$PSBoundParameters.ContainsKey('VIServer') ) {
    write-host `n"Missing Required Parameter '-VIServer <vCenter IP or FQDN>'."`n -ForegroundColor Red
    write-host `n   "Usage: $usage" `n -ForegroundColor Green
    exit
}


Write-Host `n"This script will remove all VMs renamed as Deprecated after an AppFlows failover event."`n -ForegroundColor Cyan
Write-Host "You will be prompted to provide credentials for a vCenter account with sufficient privileges."`n -ForegroundColor Cyan

# Connect to vCenter before starting
function Connect-vCenter {
    if ($IgnoreVICert) {
        Connect-VIServer $VIServer -Force | Out-Null
    } else {
        Connect-VIServer $VIServer | Out-Null
    }
}

# Disconnect from vCenter when finished
function Disconnect-vCenter {
    Write-Host `n"Disconnecting from vCenter at $VIServer"`n -ForeGroundColor Cyan
    Disconnect-VIServer $VIServer -Force -Confirm:$false
}

# Find all VMs with names that start with 'Deprecated_*' in the connected vCenter environment.
function Get-DepVMs {
    Get-VM -Name Deprecated_*
}

# Connect now and get a list of deprecated VMs
Connect-vCenter
$depVMs = Get-DepVMs

# Give the user a chance to review the list of VMs to remove and decide whether they want to proceed.
function Remove-DepVMs {
    $areyousure = read-host `n"Please confirm you wish to continue with the removal of the above listed VMs (yes or no)"

    switch ($areyousure) `
    {
        'yes' {
            write-host `n"The VMs will now be removed...please be patient as this is run synchronously." -ForeGroundColor Green
            if ($Force) {
                Remove-VM -VM $depVMs -DeletePermanently
            } else {
                Remove-VM -VM $depVMs
            }
        }

        'no' {
            write-host `n"Exiting without removing any VMs"`n -ForeGroundColor Yellow
            Disconnect-vCenter
        }

        default {
            write-host `n"You may only answer 'yes' or 'no', please try again."`n -ForeGroundColor Red
            Remove-DepVMs
        }
    }
}

# If there are deprecated VMs present and the user agrees, then remove them; else, disconnect and exit.
if ($null -ne $depVMs) {
    $depVMs
    Remove-DepVMs
    Disconnect-vCenter
} else {
    Write-Host `n"No Deprecated VMs have been located in this environment."`n -ForegroundColor Yellow
    Disconnect-vCenter
    Exit-PSHostProcess
}
