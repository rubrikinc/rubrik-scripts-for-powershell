#Authenticate to Rubrik cluster
Connect-Rubrik -Server <Rubrik IP>

#Set variables
$SourceSQLHost = 'FOO'
$SourceSQLInstance = 'MSSQLSERVER'
$dbname = 'BAR'

$TargetSQLHost = 'DEST'
$TargetSQLInstance = 'MSSQLSERVER'

#Get database object and last snapshot
$db = Get-RubrikDatabase -Hostname $SourceSQLHost -Instance $SourceSQLInstance -Database $dbname | Get-RubrikDatabase
$lastsnap = Get-RubrikSnapshot -id $db.id | Sort-Object date -Descending | Select-Object -First 1

#Get target instance ID
$targetinstance = (Get-RubrikDatabase -Hostname poc-sql02.rangers.lab -Instance MSSQLSERVER)[0].instanceId

#Run export
Export-RubrikDatabase -id $db.id -targetInstanceId $targetinstance -targetDatabaseName $dbname -finishRecovery -recoveryDateTime $lastsnap.date -MaxDataStreams 4