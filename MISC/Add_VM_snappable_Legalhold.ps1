<#
.SYNOPSIS
Add Virtual Machine snappable into legal hold

.DESCRIPTION
This script will get the id for the latest snapshot of a VM set in the $vmName and place it in legalhold 

Change the following parameter:
# Parameters
$RubrikCluster="YOUR cluster DNS or IP Address"
$vmName = "Virtual Machine name that needs to be placed in legal hold"

This script uses a credential file to gain access to the Rubrik Cluster
# get credentials from saved encrypted xml file
$Credxmlpath = "path to *.cred file"
$CredXML = Import-Clixml $Credxmlpath

to create a cred file use the following code
$credential = Get-Credential
Connect-Rubrik -Server $RubrikCluster -Credential $credential
$credential | Export-Clixml -Path "path to *.cred file"

.NOTES
written by Harold Buter for community usage
Twitter: @hbuter
GitHub: hbuter-rubrik
#>

# Import Rubrik Module
import-Module Rubrik

# Parameters
$RubrikCluster="[CLUSTER_DNS_NAME / IP ADDRESS]"
$vmName = "[VM NAME]"

# get credentials from saved encrypted xml file
$Credxmlpath = "[PATH TO CRED FILE]"
$CredXML = Import-Clixml $Credxmlpath

# connect to cluster
Connect-Rubrik -Server $RubrikCluster -Credential $CredXML

# Get Snapshot ID needed for to put in legalhold
$vmSnap = get-rubrikvm $vmName | Get-RubrikSnapshot -Latest
$vmSnapID = $vmSnap.id 
Write-Output "Snap ID is: " $vmSnapID

# create body for restAPI invocation 
$body = @{
    "snapshotId" = $vmSnapID;
    "holdConfig" = @{
     "IsHoldInPlace" = $true;
    }
   }
​
# Add Snapshot to legalhold
Invoke-RubrikRESTCall -Endpoint "legal_hold/snapshot" -Method POST -Body $body


