#Requires -Modules Rubrik,SqlServer
[CmdletBinding()]
param(
  #Rubrik Database IDs for export
  [Parameter(ValueFromPipelineByPropertyName = $true)]
  [String[]]$id
  #recovery date time. If not used, latest recovery point will be used
  ,[DateTime]$RecoveryDateTime
  #Target SQL Instance to use for livemounts and backups
  ,[String]$ServerInstance
  #Path local to target instance to write the backup to
  ,[String]$BackupPath
)
Begin{
    #Wait-RubrikRequests used to wait until live mounts are complete
    function Wait-RubrikRequests($reqs) {
        do{
            Start-Sleep -Seconds 15
            $reqs = $reqs | Get-RubrikRequest -Type mssql -ErrorAction SilentlyContinue
        }until(($reqs | Where-Object {@('QUEUED','RUNNING','FINISHING') -contains $_.status} | Measure-Object).Count -eq 0)
    }
    $reqs = @()
    $mounts = @()
    $dbs = $id | ForEach-Object {Get-RubrikDatabase -id $_}
    $TargetInstanceId = (Get-RubrikSQLInstance -ServerInstance $ServerInstance).id
}

Process{
    #Queue up all live mount creation
    foreach($db in $dbs){
    #Set recoverydate time
      if(-not $RecoveryDateTime){$RecoveryDateTimeDB = (Get-Date $db.latestRecoveryPoint)}
      #Create new Live Mount
      $MountName = "$($db.Name)_ExportToBak"
      $mounts += $MountName
      $reqs += New-RubrikDatabaseMount -id $db.id -TargetInstanceId $TargetInstanceId -MountedDatabaseName $MountName -RecoveryDateTime $RecoveryDateTimeDB -Confirm:$false
    }
    
    #Wait for livemounts to complete
    Wait-RubrikRequests -reqs $reqs

    #Once Live Mounts are complete, create backups
    foreach($mount in $mounts){
        #Run backup of live mount to the Backup Path
        #This will be done in the context of the user running the script for SQL authentication
        Backup-SqlDatabase -ServerInstance $ServerInstance -Database $mount -BackupFile $($BackupPath + '\' + $mount + "-$(Get-Date -Format 'yyyyMMddHHmmss')`.bak   ") -CompressionOption On -Initialize

        #once the backup is complete, unmount the database
        Remove-RubrikMount -MountedDatabaseName $mount -Confirm:$false
    }
}

