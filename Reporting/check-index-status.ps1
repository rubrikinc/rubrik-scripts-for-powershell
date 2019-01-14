#
# Name:     check-index-status.ps1
# Author:   Tim Hynes
# Use case: Checks for unindexed snapshots for the given VM name
#
param (
  [String]$vm
)
Import-Module Rubrik
$rubrik_node = 'rubrik.demo.com'
$rubrik_user = 'admin'
$rubrik_pass = 'notapass!'
Connect-Rubrik –Server $rubrik_node -Username $rubrik_user -Password $(ConvertTo-SecureString -String $rubrik_pass -AsPlainText -Force) | Out-Null
Write-Output $("Checking snapshots for VM: "+$vm)
$vm_obj = Get-RubrikVM $vm –PrimaryClusterId local
if ($vm_obj -eq $null) {
    throw 'VM not found'
} elseif ($vm_obj.count -gt 1) {
    throw 'More than one VM found'
}
$unindexed_snaps =  $vm_obj | get-rubriksnapshot | ? {$_.indexState -ne 1}
if ($unindexed_snaps -ne $null) {
    Write-Output 'The following unindexed snapshots were found:'
    $unindexed_snaps | select @{N='Date';E={[datetime]$_.date}},id
} else {
    Write-Output 'No unindexed snapshots were found:'
}
Disconnect-rubrik -Confirm:$false