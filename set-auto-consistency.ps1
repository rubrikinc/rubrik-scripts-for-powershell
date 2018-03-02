# This code will bulk modify set consistence to unknown (Auto)
# for Virtual Machines that are currently set to CRASH_CONSISTENT

# Set Snapshot Consistency for VM(s) to VALUES:
# UNKNOWN
# INCONSISTENT
# CRASH_CONSISTENT
# FILE_SYSTEM_CONSISTENT
# VSS_CONSISTENT
# APP_CONSISTENT



$vms = Get-RubrikVM devops-vra 

foreach($vm in $vms){
  if($vm.effectiveSlaDomainName -ne 'Unprotected'){
    Write-Host "$($vm.name) "
    Write-Host "  Consistency - $($vm.snapshotConsistencyMandate)"
    if($vm.snapshotConsistencyMandate -eq "CRASH_CONSISTENT"){
      Write-Host "  Setting Auto Consistency"
      Set-RubrikVM -id $vm.id -SnapConsistency 'UNKNOWN' -confirm:0  | out-null
    }
  }
}

