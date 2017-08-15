/**********************************************************
Rubrik SQL Server profile queries.
FileInfo
*********************************************************/

select
	@@SERVERNAME as ServerName
	,database_id
	,file_id
	,type_desc
	,size/128.0 as DBFileSizeMB
from
	sys.master_files;

