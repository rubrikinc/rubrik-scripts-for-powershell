#requires -modules Rubrik

# https://build.rubrik.com
# https://www.rubrik.com/blog/get-started-rubrik-powershell-module/
# https://github.com/rubrikinc/rubrik-sdk-for-powershell
# https://github.com/rubrikinc/rubrik-scripts-for-powershell

<#
.SYNOPSIS
Exports a VM snapshot to a standalone ESXi host that is not managed by vCenter
.DESCRIPTION
The Export-RubrikVMStandalone cmdlet is used export a VM snapshot to a standalone ESXi host
The standalone ESXi host cannot be managed by vCenter
.NOTES
Written by Steven Tong for community usage
GitHub: stevenctong

You can use a Rubrik credential file for authentication
Default $rubrikCred = './rubrik_cred.xml'
To create one: Get-Credential | Export-CliXml -Path ./rubrik_cred.xml

.EXAMPLE
Export-RubrikVMSnapshot
This will prompt for all variables

.EXAMPLE
Export-RubrikVMSnapshot -rubrikServer <rubrik_host> -user <rubrik_user> -password <rubrik_pw> -vm <VM_name> -esxihost <esxi_host> -esxiuser <esxi_user> -esxipassword <esxi_password>
Export a VM from the Rubrik cluster to the ESXi host. The last 25 snapshots will be displayed and one can be selected. Datastores on the ESXi host will be displayed and one can be selected.

.EXAMPLE
Export-RubrikVMSnapshot -rubrikServer <rubrik_host> -user <rubrik_user> -password <rubrik_pw> -vm <VM_name> -esxihost <esxi_host> -esxiuser <esxi_user> -esxipassword <esxi_password> -latest "yes"
Exports the latest snapshot. Datastores on the ESXi host will be displayed and one can be selected.

.EXAMPLE
Export-RubrikVMSnapshot -rubrikServer <rubrik_host> -user <rubrik_user> -password <rubrik_pw> -vm <VM_name> -esxihost <esxi_host> -esxiuser <esxi_user> -esxipassword <esxi_password> -esxidatastore <esxi_datastore> -latest "yes"
Exports the latest snapshot to the datastore specified. Use as a "one liner."
#>

param (
  [CmdletBinding()]

  # Rubrik cluster hostname or IP address
  [Parameter(Mandatory=$true)]
  [string]$rubrikServer,

  # Rubrik username if not using credential file
  [Parameter(Mandatory=$false)]
  [string]$user = $null,

  # Rubrik password if not using credential file
  [Parameter(Mandatory=$false)]
  [string]$password = $null,

  # VM name to restore
  [Parameter(Mandatory=$true, HelpMessage="VM Name to Restore")]
  [string]$vm,

  # Set to "yes" if you want the latest snapshots exported
  [Parameter(Mandatory=$false, HelpMessage="Set -latest to yes if you want to export the most recent snapshot")]
  [string]$latest = "no",

  # Provide a target standalone ESXi host that's unmanaged by vCenter
  [Parameter(Mandatory=$true)]
  [string]$esxiHost,

  # ESXi username
  [Parameter(Mandatory=$true)]
  [string]$esxiUser,

  # ESXi password
  [Parameter(Mandatory=$true)]
  [string]$esxiPassword,

  # ESXi datastore to restore to
  [Parameter(Mandatory=$false)]
  [string]$esxiDatastore = $null,

  # True or false whether to power on (default=$false)
  [Parameter(Mandatory=$false)]
  [bool]$powerOn = $false,

  # Use to provide a Snapshot ID to recover from - use "Get-RubrikSnapshot" to find
  [Parameter(Mandatory=$false)]
  [string]$snapshotID = $null
)

# Create a Rubrik credential file by using the following:
# Get-Credential | Export-CliXml -Path ./rubrik_cred.xml
# The created credential file can only be used by the person that created it

$rubrikCred = "rubrik_cred.xml"

Import-Module Rubrik

# If no credential file and no Rubrik username/password provided then exit
if (((Test-Path $rubrikCred) -eq $false) -and (!$user) -and (!$password)) {
    Write-Host ""
    Write-Host "No credential file found ($rubrikCred), please provide Rubrik credentials"

    $credential = Get-Credential
    Connect-Rubrik -Server $rubrikServer -Credential $credential
}
# Else if user is provided use the username and password
elseif ($user) {
    if ($password) {
        $password = ConvertTo-SecureString $password -AsPlainText -Force

        Connect-Rubrik -Server $rubrikServer -Username $user -Password $password
    }
    # If username provided but not password, prompt for password
    else {
        $credential = Get-Credential -Username $user

        Connect-Rubrik -Server $rubrikServer -Credential $credential
    }
}
# Else if credential file is found then use it
elseif (Test-Path $rubrikCred) {

    # Import Credential file
    $credential  = Import-Clixml -Path $rubrikCred

    Connect-Rubrik -Server $rubrikServer -Credential $credential
}

# Get VM details and exit if no VM found
$vmInfo = Get-RubrikVM $vm | Select-Object "id", "effectiveSlaDomainName"

if ($vmInfo.id -eq $null) {
    Write-Error "`nNo VM found by name $vm"
    break
}

# Get snapshot details for the VM and exit if no snapshots found
$snapshots = Get-RubrikSnapshot -id $vmInfo.id | Select-Object "date", "id", "slaName"

if ($snapshots -eq $null) {
    Write-Error "`nNo snapshots found on $vm with SLA $($vmInfo.effectiveSlaDomainName)"
    break
}

if (!$snapshotID) {
    # List out last 25 snapshots if exporting from latest snapshot was not selected
    if ($latest -notlike "yes") {
        Write-Host "`nMost recent snapshots for VM $vm (up to 25)"
        Write-Host " #   Date                 ID                                    SLA Name"
        Write-Host "---  ----                 --                                    --------"

        # Gets up to 25 of the most recent snapshots
        if ($snapshots.count -gt 25) {
            $count = 25
        }
        else {
            $count = $snapshots.count
        }

        for ($i = 0; $i -lt $count; $i++) {
            Write-Host "[$i]  $($snapshots[$i].date)  $($snapshots[$i].id)  $($snapshots[$i].slaName)"
        }

        Write-Host ""

        # Prompt to choose one of the snapshots, default [0]
        do {
            try {
                $numOk = $true
                [int]$snapshotNum = Read-Host -Prompt "Choose a snapshot to restore from above [0]"
            }
            catch {
                $numOk = $false
            }
        }
        until (($snapshotNum -ge 0 -and $snapshotNum -lt $count -and $numOk))

        # Snapshot ID to restore selected from the user in the array
        $snapshotID = $snapshots[$snapshotNum].id
        $snapshotDate = $snapshots[$snapshotNum].date
        Write-Host "`n$snapshotNum selected to restore snapshot from $snapshotDate"
    }
    else {
        # Snapshot ID to restore the latest is in position 0 in the array
        $snapshotID = $snapshots[0].id
        $snapshotDate = $snapshots[0].date
        Write-Host "`nRestoring latest snapshot from $snapshotDate)"
    }
}

# Create Json as PSObject with ESXi host info and retrieve datastore list
$esxiDatastoresJson = New-Object PSObject
$esxiDatastoresJson | Add-Member -MemberType NoteProperty -Name "ip" -Value $esxiHost
$esxiDatastoresJson | Add-Member -MemberType NoteProperty -Name "username" -Value $esxiUser
$esxiDatastoresJson | Add-Member -MemberType NoteProperty -Name "password" -Value $esxiPassword

    $esxiDatastores = Invoke-RubrikRESTCall -Method "Post" -Api "internal" -Body $esxiDatastoresJson -Endpoint "vmware/standalone_host/datastore"

# If no ESXi datastore was provided then list datastores found on ESXi host
if (!$esxiDatastore) {
    Write-Host "`nNo ESXi datastore target provided for host $esxiHost, please select target datastore"

    Write-Host "`n #   Datastore"
    Write-Host "---  ---------"

    for ($i = 0; $i -lt $esxiDatastores.data.count; $i++) {
        Write-Host "[$i]  $($esxiDatastores.data[$i].name)"
    }

    Write-Host ""

    # Prompt to choose one of the datastores, default [0]
    do {
        try {
            $numOk = $true
            [int]$datastoreNum = Read-Host -Prompt "Choose a datastore to export to from above [0]"
        }
        catch {
            $numOk = $false
        }
    }
    until (($datastoreNum -ge 0 -and $datastoreNum -lt ($esxiDatastores.data.count) -and $numOk))

    $esxiDatastore = $esxiDatastores.data[$datastoreNum].name
}
# Else if a datastore was provided, check to see if it exists on the ESXi host, if not exit
else {
    if (!($esxiDatastores.data.name -contains $esxiDatastore)) {
        Write-Error "`nDatastore $esxiDatastore not found on $esxiHost"
        break
    }
}

# Create Json as PSObject with VM Export info
$exportJson = New-Object PSObject

$exportJson | Add-Member -MemberType NoteProperty -Name "vmName" -Value $vm
$exportJson | Add-Member -MemberType NoteProperty -Name "disableNetwork" -Value $true
$exportJson | Add-Member -MemberType NoteProperty -Name "removeNetworkDevices" -Value $true
$exportJson | Add-Member -MemberType NoteProperty -Name "powerOn" -Value $powerOn
$exportJson | Add-Member -MemberType NoteProperty -Name "keepMacAddresses" -Value $true
$exportJson | Add-Member -MemberType NoteProperty -Name "hostIpAddress" -Value $esxiHost
$exportJson | Add-Member -MemberType NoteProperty -Name "datastoreName" -Value $esxiDatastore
$exportJson | Add-Member -MemberType NoteProperty -Name "hostUsername" -Value $esxiUser
$exportJson | Add-Member -MemberType NoteProperty -Name "hostPassword" -Value $esxiPassword

Write-Host ""
Write-Host "Exporting VM:   $vm"
Write-Host "Snapshot date:  $snapshotDate"
Write-Host "To ESXi host:   $esxiHost"
Write-Host "On datastore:   $esxiDatastore"
Write-Host ""

$result = Invoke-RubrikRESTCall -Method "Post" -Api "internal" -Body $exportJson -Endpoint "vmware/vm/snapshot/$snapshotID/standalone_esx_host_export" -verbose

Disconnect-Rubrik -Confirm:$false
