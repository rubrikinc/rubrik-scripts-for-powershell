# Script will compare instances to see what database can be exported, and submit the requests
# .\sql-export-instance.ps1 -srcHost [hostname in rubrik] -srcInst MSSQLSERVER -dstHost [hostname in rubrik] -dstInst MSSQLSERVER

Param(
  [String]$srcHost,
  [String]$srcInst,
  [String]$dstHost,
  [String]$dstInst
  )

Write-Host "Exporting databases available from $($srcHost):$($srcInst) to $($dstHost):$($dstInst)"

Write-Host -nonewline "   *   Is this what you want to do?  (Y to continue, any other key to abort)"
$confirm= read-host
if ( $confirm -ne "Y" ) { exit }

$fromInstance = Get-RubrikDatabase -Host $srcHost -Instance $srcInst
$toInstance = Get-RubrikDatabase -Host $dstHost -Instance $dstInst

# Figure out what's on the target already, and what can be exported to it from the source
$dbsAtTarget = @()
$dbsNotAtTarget = @()
foreach($sourceInstance in $fromInstance){
   foreach ($targetInstance in $toInstance){
      $targetInstanceId = $targetInstance.instanceId
      if ( ( $sourceInstance.name -eq $targetInstance.name ) ) {
         $dbsAtTarget += $targetInstance.name
      }
      else {
         if ( $dbsNotAtTarget -notcontains $sourceInstance.name ) {
            $dbsNotAtTarget += $sourceInstance.name
         }
      }
   }
}

# This is the list of what can be exported
$dbsNotAtTarget = $dbsNotAtTarget |Where-Object { $dbsAtTarget -notcontains $_ }

# Make sure we have the destination SQL Instance ID
Write-Host "Exporting to $($targetInstanceId)"

# Now we can iterate through the requested exports and take action
foreach ($sourceInstance in $fromInstance){
   if ( $dbsNotAtTarget -notcontains $sourceInstance.name ) {
      continue
   }

   # Getting the database details on the last recovery point
   $details = Get-RubrikDatabase -id $sourceInstance.id

   # Let's convert the latest restore point timestamp to Epoch (UTC) with Milliseconds for the Export Request
   $timestampMs = (Get-Date (Get-Date -Date ([DateTime]::Parse($details.latestRecoveryPoint)).ToUniversalTime()) -UFormat %s) + "000"

   Write-Host "*    Exporting $($sourceInstance.name) ($($sourceInstance.id)"
   Write-Host "     Latest Recovery Point is $($details.latestRecoveryPoint) - $($timestampMs)"

   $finishRecovery = "false"
   $maxDataStreams = 4
   $targetDatabaseName = $sourceInstance.name

# Send the call
   $exportCall = Export-RubrikDatabase -id $sourceInstance.id `
                                       -targetInstanceId $targetInstanceId `
                                       -targetDatabaseName $targetDatabaseName `
                                       -finishRecovery `
                                       -maxDataStreams $maxDataStreams `
                                       -timestampMs $timestampMs `
	                               -confirm:$false



}
