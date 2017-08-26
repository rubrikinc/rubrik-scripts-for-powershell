#Requires -Modules Rubrik
#Parameterized Script Values 

param([string]$SourceSQLHost
      ,[string]$SourceSQLInstance
      ,[string]$SourceDBName
      ,[string]$TargetSQLHost
      ,[string]$TargetSQLInstance
      ,[string]$TargetDBName
      ,[string]$DBFileConfig
      ,[datetime]$RecoveryDateTime)

#Load File list
$files = Get-Content $DBFileConfig | ConvertFrom-Csv

#Get export info
$db = Get-RubrikDatabase -Hostname $SourceSQLHost -Instance $SourceSQLInstance -Database $SourceDBName | Get-RubrikDatabase
$TargetInstanceID = (Get-RubrikDatabase -Hostname $TargetSQLHost -Instance $TargetSQLInstance)[0].instanceId
if($RecoveryDateTime){
 $RecoveryPoint = $RecoveryDateTime.ToUniversalTime('yyyy-MM-ddTHH:mm:ssZ') 
} else {
    $snaps = $db | Get-RubrikSnapshot | Sort-Object date -Descending| Select-Object -First 10
    "Please select a snapshot to use:" | Out-Host
    "--------------------------------" | Out-Host
    $Snaps  | ForEach-Object -Begin {$i=0} -Process {"SnapID $i - $(Get-Date $_.Date -Format 'MMM dd, yyyy HH:mm:ss')";$i++}
    $selection = Read-Host 'Enter ID of selected snapshot'
    $RecoveryPoint = Get-Date $snaps[$selection].date
}

Export-RubrikDatabase -id $db.id -targetInstanceId $TargetInstanceID -targetDatabaseName $TargetDBName -TargetFilePaths $files -MaxDataStreams 8 `
            -finishRecovery -recoveryDateTime $RecoveryPoint