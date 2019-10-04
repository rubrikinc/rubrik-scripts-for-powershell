<#
This script builds on the previous Storage Policy to SLA Protection by allowing you the user to select what Storage Policy to associate with a SLA.
Instead of needing to know what SLAs and Storage Policies are in your environment, it will query the vCenter and Rubrik machine for you. 
In addition to this, I added the capability to capture two different credentials and allowed you to specify the vCenter and Rubrik cluster name realtime.
This script will continue to grow as I think up of new capabilities to add to it. At the end the script gives you a short summary of what VMs are 
still unprotected. 
#>

[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic') | Out-Null

$vcenter = [Microsoft.VisualBasic.Interaction]::InputBox("Please enter your vCenter Server name", "vCenter Prompt")
$vcreds=Get-Credential -Message "Please enter your vCenter Credentials"

$rubrikcluster = [Microsoft.VisualBasic.Interaction]::InputBox("Please enter your Rubrik cluster name or IP", "Rubrik Cluster Prompt")
$rcreds=Get-Credential -Message "Please enter your Rubrik Credentials"

$null = VMware.VimAutomation.Core\Connect-VIServer -Server $vcenter -Credential $vcreds
$null = Connect-Rubrik -Server $rubrikcluster -Credential $rcreds


get-rubriksla | select-object name,id | out-gridview -PassThru -Title 'Please select an awesome SLA to assign to your VM' | 
foreach-object {
    $Sla = $_
    Get-SpbmStoragePolicy | Select-Object -Property Name | out-gridview -Title 'Select Storage Policy to assign "$($sla.name)" to...' -PassThru | 
    ForEach-Object {
        Get-SpbmStoragePolicy -Name $_.Name | Get-SpbmEntityConfiguration -VMsOnly | 
            ForEach-Object {
            $Null = Get-RubrikVM -Name $_.Name | Protect-RubrikVM -SLAID $Sla.Id -Confirm:$false
        }
    }
}
Write-Output "These VMs are still unprotected and have no SLA assigned"
Get-RubrikVM -SLAAssignment Unassigned | Format-Table Name