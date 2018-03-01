param([switch]$pause)

# This code will bulk modify Blackout Mode for all VMs that are NOT Unprotected
# You must execute Connect-Rubrik in order to secure a connection to the Rubrik
# cluster, then run the command as stated.
# 
# This will put all VM Snaps into Blackout Mode (Paused)
# set-toggle-vm-blackout.ps1 -Pause:$true
#
# This will put all VM Snaps into (Active)
# set-toggle-vm-blackout.ps1 -Pause:$false


$vms = Get-RubrikVM 

foreach($vm in $vms){
  if($vm.effectiveSlaDomainName -ne 'Unprotected'){
    $detail = Get-RubrikVM -id $vm.id
    Write-Host "$($detail.name)"
    if($detail.blackoutWindowStatus.isSnappableBlackoutActive){
      $paused="True"
      Write-Host " SLA - $($detail.effectiveSlaDomainName)"
      Write-Host " Paused - $($paused)"
      if(!$pause){
        Write-Host " Resuming Backup"
        Set-RubrikVM -id $detail.id -PauseBackups:0 -confirm:0 | out-null
      }
    }
    else{
      $paused="False"
      Write-Host " SLA - $($detail.effectiveSlaDomainName)"
      Write-Host " Paused - $($paused)"
      if($pause){
        Write-Host " Pausing Backup"
        Set-RubrikVM -id $detail.id -PauseBackups:1 -confirm:0 | out-null 
      }
    }
  }
}

