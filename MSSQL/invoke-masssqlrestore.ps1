#Requires -Modules Rubrik, SqlServer
param([Parameter(Mandatory=$true)]
      [string[]]$databases
     ,[Parameter(Mandatory=$true)]
      [string]$SourceInstance
     ,[Parameter(Mandatory=$true)]
      [String]$TargetInstance
     ,[string]$TargetDataFilePath
     ,[string]$TargetLogFilePath
     ,[Switch]$Replace
     )

$sql_temp = "IF EXISTS (SELECT 1 FROM sys.databases WHERE name='<DBNAME>')
BEGIN
ALTER DATABASE [<DBNAME>] SET OFFLINE WITH ROLLBACK IMMEDIATE;
ALTER DATABASE [<DBNAME>] SET ONLINE;
DROP DATABASE [<DBNAME>];
END"     
$Target = Get-RubrikSQLInstance -ServerInstance $TargetInstance
$dbs = Get-RubrikDatabase -ServerInstance $SourceInstance |
       Where-Object {$databases -contains $_.name -and $_.isRelic -ne 'TRUE' -and $_.isLiveMount -ne 'TRUE'} |
       Get-RubrikDatabase
$reqs = @()

foreach($db in $dbs){
    if($Replace){
        $sql = $sql_temp.Replace('<DBNAME>',$db.name)
        Invoke-Sqlcmd -ServerInstance $TargetInstance -Database master -Query $sql
        New-RubrikHost -Name $TargetInstance -Confirm:$false | Out-Null
    }
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