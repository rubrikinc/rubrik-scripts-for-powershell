#run an ondemand snapshot
Get-RubrikDatabase -Hostname poc-sql02 -Database AdventureWorks2014 | 
    New-RubrikSnapshot -SLA 'SQL-Gold'

Get-RubrikRequest -id MSSQL_DB_BACKUP_1474ed3e-1069-44e7-86b9-3d3767677cad_bbf27579-3bc4-471e-b0ae-2cb8f197d978:::0 -Type mssql

$reqs = Get-RubrikDatabase -Hostname poc-sql02 | 
    Where-Object {$_.isRelic -ne 'TRUE' -and @('master','model','msdb') -contains $_.name} |
    ForEach-Object {New-RubrikSnapshot -id $_.id -Inherit -Confirm:$false}

$reqs | Get-RubrikRequest -Type mssql

do {
    Start-Sleep -Seconds 15
    $reqs = $reqs | Get-RubrikRequest -Type mssql
    $reqs | Format-Table id,status,progress,startTime
} until (($reqs | Where-Object {@('QUEUED','RUNNING','FINISHING') -contains $_.status} | Measure-Object).Count -eq 0)

#Create Live Mounts
#Refresh meta data!
New-RubrikHost -Name poc-sql02 -Confirm:$false

$TargetInstance = Get-RubrikSQLInstance -ServerInstance poc-sql02
$db = Get-RubrikDatabase -ServerInstance poc-sql02 -Name 'AdventureWorks2014'|
    Where-Object {$_.isRelic -ne 'TRUE'} |
    Get-RubrikDatabase 

New-RubrikDatabaseMount -id $db.id -TargetInstanceId $TargetInstance.id -MountedDatabaseName 'PowerShell_LiveMount' -RecoveryDateTime (Get-Date $db.latestRecoveryPoint) -Confirm:$false

#Unmount the live mount
Get-RubrikDatabaseMount -MountedDatabaseName 'PowerShell_LiveMount' |
    Remove-RubrikDatabaseMount -Confirm:$false

#Export/restore database
Get-RubrikDatabaseFiles -Id $db.id -RecoveryDateTime $db.latestRecoveryPoint |
    Select-Object logicalName,@{n='exportPath';'e'={$_.originalPath}} |
    ConvertTo-Csv -NoTypeInformation | Out-File C:\temp\ExportMove.csv -force

notepad C:\temp\ExportMove.csv

#Refresh meta data!
New-RubrikHost -Name poc-sql02 -Confirm:$false
Export-RubrikDatabase -Id $db.id -TargetInstanceId $TargetInstance.id -TargetDatabaseName PowerShellExport -RecoveryDateTime $db.latestRecoveryPoint -FinishRecovery -TargetFilePaths (Import-Csv C:\temp\ExportMove.csv)
