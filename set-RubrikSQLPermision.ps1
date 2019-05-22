<#
.SYNOPSIS
Grant right permission on SQL Server instances to RBS Service Account

.DESCRIPTION
Script will grant SQL permission to RBS Service Account. 

.PARAMETER ServerInstance
SQL Server to grant the Rubrik Backup Service SQL Permissions

.PARAMETER RBSServiceAccount
Windows service account for RBS

.PARAMETER RestrictedSQLPermission
Will grant the most restricted permission, without this option the sysadmin will be granted
The sysadmin is required for SQL 2008, AlwaysOn AG and for environments using VDI for T-Log backups

.EXAMPLE
.\set-RubrikSQLPermision.ps1 -ServerInstance "mf-sql17-test","mf-sqlxp" -RBSServiceAccount "RANGERS\svc_rubrik" -RestrictedSQLPermission -Verbose

.NOTES
    Name:       Grant right permission on SQL Server instances to RBS Service Account
    Created:    22/05/2019
    Author:     Marcelo Fernandes
   
#>

param (
        [Parameter(Mandatory=$true,Position=0)]
        #SQL Server Instance name. If default instance, then just use the server name, if a named instance, use either 
        #Server\Instance or Server, port                    
        [string[]] $ServerInstance,
        [Parameter(Mandatory=$true, Position=2)]
        [string]$RBSServiceAccount,
        [switch]$RestrictedSQLPermission
    )
BEGIN
{
    import-module sqlserver
    if($RestrictedSQLPermission){
        $Query = "
        IF NOT EXISTS (SELECT name  FROM master.sys.server_principals WHERE name = '$RBSServiceAccount')
        BEGIN
            CREATE LOGIN [$RBSServiceAccount] FROM WINDOWS WITH DEFAULT_DATABASE=[master]
        END
        GO
        sp_msforeachdb 'USE ?;
            IF USER_ID(''$RBSServiceAccount'') IS NULL
            BEGIN
                CREATE USER [$RBSServiceAccount] FOR LOGIN [$RBSServiceAccount]
            END            
            ALTER ROLE [db_backupoperator] ADD MEMBER [$RBSServiceAccount];
            IF (db_name() not in (''master'',''tempdb'',''msdb''))
            BEGIN
                ALTER ROLE [db_denydatareader] ADD MEMBER [$RBSServiceAccount]
            END
            '
        GO
        USE [master]
        GO
        ALTER SERVER ROLE [dbcreator] ADD MEMBER [$RBSServiceAccount]
        GO
        GRANT ALTER ANY DATABASE TO [$RBSServiceAccount]
        GO
        GRANT VIEW ANY DEFINITION TO [$RBSServiceAccount]
        GO
        GRANT VIEW SERVER STATE TO [$RBSServiceAccount]
        GO
    "
    }else {
        $Query = "ALTER SERVER ROLE [sysadmin] ADD MEMBER [$RBSServiceAccount]"
    }

    foreach($server in $ServerInstance){
        Write-Verbose "Granting SQL Permission on [$server] to [$RBSServiceAccount]"
        Write-Verbose $Query
        try {
           Invoke-Sqlcmd -ServerInstance $server -Database master -Query $Query    
        }
        catch {
            throw $_
        }        
    }    
}