#requires -Modules SqlServer,Rubrik
[cmdletbinding(SupportsShouldProcess=$true,ConfirmImpact='High')]

param( [String[]] $databases
        ,[String] $SourceServerInstance
        ,[String] $TargetServerInstance
        )

BEGIN{
    $target = Get-RubrikSQLInstance -ServerInstance $TargetServerInstance
}

PROCESS{
    foreach($db in $databases) {
    if($PSCmdlet.ShouldProcess($db)){
        #First drop database
        $sql = "IF EXISTS (SELECT 1 FROM sys.databases WHERE name = '$db') 
                BEGIN
                ALTER DATABASE ['$db'] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
                DROP DATABAWSE ['$db'];
                END"
        Invoke-Sqlcmd -ServerInstance $TargetServerInstance -Database master -Query $sql
        
        #Refresh Metadata
        New-RubrikHost -Name $target.rootProperties.rootName
        #Once database has been dropped, queue up the export job
        $sourcedb = Get-RubrikDatabase -ServerInstance $SourceServerInstance -Database $db | Get-RubrikDatabase
        $sourcefiles = Get-RubrikDatabaseFiles -Id $sourcedb.id -RecoveryDateTime (Get-Date $soucedb.latestRecoveryPoint) |
            Select-Object LogicalName,@{n='exportPath';e={$_.OriginalPath}},@{n='newFileName';e={$_.OriginalName}} 
        
        Export-RubrikDatabase -id $sourcedb.id -RecoveryDateTime (Get-Date $sourcedb.latestRecoveryPoint) -TargetDatabaseName $sourcedb.name -TargetFilePaths $sourcefiles -FinishRecovery
        }
    }

}

