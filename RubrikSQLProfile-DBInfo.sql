/**********************************************************
Rubrik SQL Server profile queries.
DBInfo
*********************************************************/

WITH LogBackupInfo AS(
select
	database_name
	,sum(backup_size/1024.0/1024.0) as LogBackupTotalMB
from
	msdb.dbo.backupset
where 
	type = 'l'
	and backup_finish_date > dateadd(dd,-7,GETDATE())
group by database_name),
FullBackupInfo AS(
select
	database_name
	,AVG(backup_size/1024.0/1024.0) as AverageBackupSizeMB
	,AVG(DATEDIFF(ss,backup_start_date,backup_finish_date)/1.0) as AverageBackupTime
from
	msdb.dbo.backupset
where
	type = 'd'
group by database_name)
SELECT
	@@SERVERNAME as ServerName
    ,SERVERPROPERTY('ProductVersion') as SQLVersion
	,db.database_id
	,db.recovery_model_desc
	,isnull(lbi.LogBackupTotalMB,0) as LogBackupMB
	,isnull(fbi.AverageBackupSizeMB,0) as AverageFullMB
	,isnull(fbi.AverageBackupTime,0) as AverageFullTimeSec
	,sum(mf.size/128.0) as DBTotalSizeMB
from sys.databases db
	join sys.master_files mf on db.database_id = mf.database_id
	left join LogBackupInfo lbi on db.name = lbi.database_name
	left join FullBackupInfo fbi on db.name = fbi.database_name
group by 
	db.database_id
	,db.recovery_model_desc
	,isnull(lbi.LogBackupTotalMB,0)
	,isnull(fbi.AverageBackupSizeMB,0)
	,isnull(fbi.AverageBackupTime,0);