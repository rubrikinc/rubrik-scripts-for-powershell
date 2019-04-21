# This small powershell command looks for the following Storage Policies in your VMware environment and then assigns
# the VM that has that policy an SLA based off of that. The example I used below Gold Storage = Gold SLA and so on. 
# This can be modified to whatever you environment requires. I have suppressed output to keep it clean. I finally
# finish up with a command to inform the admin of the machines that have no SLA protection applied yet. 

$Credential=Get-Credential
$null = Connect-VIServer -Server vCenter1.lab.local -Credential $Credential 
$null = Connect-Rubrik -Server rubrik01.lab.local -Credential $Credential 


Get-SpbmStoragePolicy -Name 'Gold' |
Get-SpbmEntityConfiguration -VMsOnly | ForEach-Object {
   $null = Get-RubrikVM $_.Name | Protect-RubrikVM -SLA Gold -Confirm:$false
}

Get-SpbmStoragePolicy -Name 'Silver' |
Get-SpbmEntityConfiguration -VMsOnly | ForEach-Object {
   $null = Get-RubrikVM $_.Name | Protect-RubrikVM -SLA Silver -Confirm:$false
}

Get-SpbmStoragePolicy -Name 'Bronze' |
Get-SpbmEntityConfiguration -VMsOnly | ForEach-Object {
   $null = Get-RubrikVM $_.Name | Protect-RubrikVM -SLA Bronze -Confirm:$false
}

Write-Output "These VMs are still unprotected and have no SLA assigned or their Storage Policies were not covered by this script"
Get-RubrikVM -SLAAssignment Unassigned | Format-Table Name