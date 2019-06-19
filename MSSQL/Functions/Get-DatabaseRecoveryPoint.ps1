function Get-DatabaseRecoveryPoint{
    param(
        [PSObject]$RubrikDatabase,
        [String]$RestoreTime
    )
    switch -Wildcard ($RestoreTime){
        "latest" {
            $LastRecoveryPoint = (Get-RubrikDatabase -id $RubrikDatabase.ID).latestRecoveryPoint
            $RecoveryDateTime = Get-date -Date $LastRecoveryPoint
        }
        "last full" {
            $RubrikSnapshot = Get-RubrikSnapshot -id $RubrikDatabase.id | Sort-Object date -Descending | Select-object -First 1
            $RecoveryDateTime = $RubrikSnapshot.date
        }
        default {
            $RawRestoreDate = (get-date -Date $RestoreTime)
            Write-Verbose ("RawRestoreDate is: $RawRestoreDate")
            $Now = Get-Date
            if ($RawRestoreDate -ge $Now){$RecoveryDateTime = $RawRestoreDate.AddDays(-1)} 
            else{$RecoveryDateTime = $RawRestoreDate}
        }
    }
    return $RecoveryDateTime
}