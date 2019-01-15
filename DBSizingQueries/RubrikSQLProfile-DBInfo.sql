/**********************************************************
Rubrik SQL Server profile queries.
DBInfo
*********************************************************/
	IF OBJECT_ID('tempdb.dbo.##enterprise_features') IS NOT NULL
  	DROP TABLE ##enterprise_features
 
	CREATE TABLE ##enterprise_features
	(
		ServerName	SYSNAME,
		dbid		SYSNAME,
		dbname       SYSNAME,
		feature_name VARCHAR(100),
		feature_id   INT
	)
		EXEC sp_msforeachdb
	N' USE [?] 
--	IF (SELECT COUNT(*) FROM sys.dm_db_persisted_sku_features) > 0 
--	BEGIN 
	INSERT INTO ##enterprise_features 
		SELECT @@SERVERNAME, dbid=DB_ID(), dbname=DB_NAME(),feature_name,feature_id 
		FROM sys.dm_db_persisted_sku_features 
--	END ';

WITH LogBackupInfo 
AS
(
    SELECT database_name
	    ,AVG(DATEDIFF(ss,backup_start_date,backup_finish_date)/1.0) as AverageLogBackupTime
	    ,SUM(backup_size/1024.0/1024.0) as LogBackupTotalMB
    FROM msdb.dbo.backupset
    WHERE type = 'l'
	    and backup_finish_date > dateadd(dd,-7,GETDATE())
    GROUP BY database_name
),
FullBackupInfo 
AS
(
    SELECT database_name
	    ,AVG(backup_size/1024.0/1024.0) as AverageBackupSizeMB
	    ,AVG(DATEDIFF(ss,backup_start_date,backup_finish_date)/1.0) as AverageBackupTime
    FROM msdb.dbo.backupset
    WHERE type = 'd'
    GROUP BY database_name
),
LogBackupInterval
AS
(
  SELECT database_name
	    ,backup_start_date
	    , LAG(backup_start_date, 1, backup_start_date) OVER (PARTITION BY database_name ORDER BY backup_start_date) AS PreviousBackupStartDate
        , DATEDIFF(mi, LAG(backup_start_date, 1, backup_start_date) OVER (PARTITION BY database_name ORDER BY backup_start_date), backup_start_date) as BackupInterval
    FROM msdb.dbo.backupset
    WHERE type = 'l'
	    and backup_start_date > dateadd(dd,-7,GETDATE())
),
EnterpriseFeatures
AS
(
	SELECT dbName as 'DatabaseName'
		,[ChangeCapture]
		,[ColumnStoreIndex]
		,[Compression]
		,[MultipleFSContainers]
		,[InMemoryOLTP]
		,[Partitioning]
		,[TransparentDataEncryption]
	FROM 
	(SELECT dbname, feature_name FROM   ##enterprise_features) e
	PIVOT
	( COUNT(feature_name) for feature_name IN ([ChangeCapture], [ColumnStoreIndex], [Compression], [MultipleFSContainers],[InMemoryOLTP],[Partitioning],[TransparentDataEncryption]) )
	AS PVT
)
SELECT
	@@SERVERNAME as ServerName
    ,SERVERPROPERTY('ProductVersion') as SQLVersion
	,db.name
	,db.recovery_model_desc
	,isnull(lbi.LogBackupTotalMB,0) as SevenDayLogBackupMB
	,isnull(fbi.AverageBackupSizeMB,0) as AverageFullMB
	,isnull(fbi.AverageBackupTime,0) as AverageFullTimeSec
	,isnull(lbi.AverageLogBackupTime,0) as AverageLogTimeSec
	,sum(mf.size/128.0) as DBTotalSizeMB
    ,AVG(lbii.BackupInterval) as AverageLogBackupInterval
	,isnull(ef.ChangeCapture,0) as ChangeCapture
	,isnull(ef.ColumnStoreIndex,0) as ColumnStoreIndex
	,isnull(ef.[Compression],0) as Compression
	,isnull(ef.[MultipleFSContainers],0) as FILESTREAM
	,isnull(ef.[InMemoryOLTP], 0) as InMemoryOLTP
	,isnull(ef.[Partitioning],0) as Partitioning
	,isnull(ef.[TransparentDataEncryption],0) as TransparentDataEncryption
FROM sys.databases db
JOIN sys.master_files mf ON db.database_id = mf.database_id
LEFT OUTER JOIN LogBackupInfo lbi ON db.name = lbi.database_name
LEFT OUTER JOIN FullBackupInfo fbi ON db.name = fbi.database_name
LEFT OUTER JOIN LogBackupInterval lbii ON db.name = lbii.database_name
LEFT OUTER JOIN EnterpriseFeatures ef ON db.name = ef.DatabaseName
WHERE db.database_id != 2
 --   AND lbii.PreviousBackupStartDate <> '1900-01-01 00:00:00.000'
GROUP BY db.name
	,db.recovery_model_desc
	,isnull(lbi.LogBackupTotalMB,0)
	,isnull(fbi.AverageBackupSizeMB,0)
	,isnull(fbi.AverageBackupTime,0)
	,isnull(lbi.AverageLogBackupTime,0)
	,isnull(ef.ChangeCapture,0)
	,isnull(ef.[ColumnStoreIndex],0)
	,isnull(ef.[Compression],0)
	,isnull(ef.[MultipleFSContainers],0)
	,isnull(ef.[InMemoryOLTP],0)
	,isnull(ef.[Partitioning],0)
	,isnull(ef.[TransparentDataEncryption],0)
ORDER BY name
