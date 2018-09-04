#Requires -Modules Rubrik
param([Parameter(Mandatory=$true)]
      [string[]]$databases
     ,[Parameter(Mandatory=$true)]
      [string]$SourceInstance
     ,[Parameter(Mandatory=$true)]
      [String]$TargetInstance
     ,[string]$TargetDataFilePath
     ,[string]$TargetLogFilePath
     )

$Target = Get-RubrikSQLInstance -ServerInstance $TargetInstance
$dbs = Get-RubrikDatabase -ServerInstance $SourceInstance |
       Where-Object {$databases -contains $_.name -and $_.isRelic -ne 'TRUE' -and $_.isLiveMount -ne 'TRUE'} |
       Get-RubrikDatabase
$reqs = @()

foreach($db in $dbs){
    $reqs += Export-RubrikDatabase -Id $db.id `
                          -RecoveryDateTime (Get-Date $db.latestRecoveryPoint) `
                          -FinishRecovery `
                          -TargetInstanceId $Target.id `
                          -TargetDataFilePath $TargetDataFilePath `
                          -TargetLogFilePath $TargetLogFilePath `
                          -TargetDatabaseName $db.name `
                          -Confirm:$false                         
}

return $reqs