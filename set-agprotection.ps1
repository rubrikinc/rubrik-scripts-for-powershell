#requires -module Rubrik,SQLPS
param([parameter(Mandatory=$true)]
    [string]$RubrikServer
    ,[parameter(Mandatory=$true)]
    [pscredential]$RubrikCred
    ,[parameter(Mandatory=$true)]
    [string]$AGListener
    ,[parameter(Mandatory=$true)]
    [string]$SLAName
    ,[parameter(Mandatory=$true)]
    [ValidateSet('PRIMARY','SECONDARY')]
    [string]$role
    ,[int]$LogFreqMinutes = 15
    ,[int]$LogRetentionDays = 7
)

#Connect to the Rubrik cluster
Connect-Rubrik -Server $RubrikServer -Credential $RubrikCred -ErrorAction Stop

#SQL Query to get all nodes assigned to a specific role. This assumes there are only 2 nodes in the AG.
$sql = "select 
	d.name
	,ar.replica_server_name
	,ars.role_desc
from 
	sys.databases d
	join sys.dm_hadr_database_replica_states drs on d.database_id = drs.database_id
	join sys.availability_replicas ar on drs.replica_id = ar.replica_id
	join sys.dm_hadr_availability_replica_states ars on drs.replica_id = ars.replica_id
where
    ars.role_desc = '$role'"

$results = Invoke-Sqlcmd -ServerInstance $AGListener -Database tempdb -Query $sql

#Get the SLAID and create array for DBs to reassign
$SLAID = Get-RubrikSLA -Name $SLAName
$dbs = @()

#Get a collection of the Rubrik database objects that live on the replica node desire for protection
foreach($r in $results){
    $dbs += Get-RubrikDatabase -Instance MSSQLSERVER -Name $r.name | 
        Where-Object {$_.isrelic -ne 'True' -and $_.rootProperties.rootName -like "$($r.replica_server_name)`*"}
}

#Set protection on the Rubrik database objects
$dbs | Set-RubrikDatabase -SLAID $SLAID.id -LogBackupFrequencyInSeconds ($LogFreqMinutes * 60) -LogRetentionHours ($LogRetentionDays * 24) -Confirm:$false