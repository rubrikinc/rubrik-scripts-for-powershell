<#
.SYNOPSIS
copy-LMDatabaseFiles is used to detach Live mounted databases and copy the data files (.MDF and .LDF) to a supplied destination folder.

.DESCRIPTION
Based on parameters supplied, copy-LMDatabaseFiles will dettach the LM databases, copy data files to a supplied destination folder and attach back the LB database.

.PARAMETER HostName
SQL Server Host name

.PARAMETER Instance
Instance name of SQL Server. If default instance use MSSQLSQLSERVER. If named instance, use the name of the instance

.PARAMETER RubrikServer
IP address or the name of the Rubrik Server we should connect to

.PARAMETER RubrikCredential
Credential to be used to authenticate to the Rubrik server. 

.PARAMETER destination
Destination folder/share where the files should be copied.

.EXAMPLE
Detach and copy all LM databases
    $RubrikServer = "172.21.8.51"
    $RubrikCredential = (Get-Credential -Message 'Please enter your Rubrik credentials')
    Connect-Rubrik -Server $RubrikServer -Credential $RubrikCredential
    .\copy-LMDatabaseFiles.ps1 -HostName sql1.domain.com `
        -Instance mssqlserver `
        -RubrikServer 172.21.8.51 `
        -Destination "C:\temp\"
        
.EXAMPLE
Detach and copy all LM databases from remote client
    $session = New-PSSession -ComputerName "sql1.domain.com"
    $RubrikCredential = (Get-Credential -Message 'Please enter your Rubrik credentials')

    Invoke-Command -Session $session -ScriptBlock 
    {
        $RubrikServer = "172.21.8.51"
        Connect-Rubrik -Server $RubrikServer -Credential $using:RubrikCredential
        C:\temp\invoke-detachLMdb.ps1 -HostName "sql1.domain.com" -Instance "mssqlserver" -RubrikServer "172.21.8.51" -Destination "C:\temp\"
    } 

.NOTES
Name:               Invoke detach live mounted databases
Created:            09/04/2018
Author:             Marcelo Fernandes
Execution Process:
    Before running this script, you need to connect to the Rubrik cluster, and also ensure SQL Permission for account that will run this script.
        Ex.
        $RubrikServer = "172.21.8.51"
        #$RubrikCredential = (Get-Credential -Message 'Please enter your Rubrik credentials')
        Connect-Rubrik -Server $RubrikServer -Credential $RubrikCredential
#>

param
(
    [Parameter(Mandatory=$true, Position=1)]
    [string]$HostName,
    [Parameter(Mandatory=$true, Position=2)]
    [string]$Instance, 

    [Parameter(Mandatory=$true)]
    [string]$RubrikServer,

    [Parameter(Mandatory=$true)]
    [string]$Destination 
)

BEGIN
{
    #Parse ServerInstance 
    if($Instance.ToUpper() -eq 'MSSQLSERVER')
    {
        $ServerInstance = $Hostname
    }
    else 
    {
        $ServerInstance = "$HostName\$Instance"
    }

    #Get all live mounted databases from Rubrik cluster for supplied SQL Instance
    Write-Verbose ("Getting LM Databases for Instance [$HostName] at Rubrik cluster.")
    $dbs = Get-RubrikDatabase -Hostname $HostName -Instance $Instance | Where-Object {$_.isrelic -ne 'TRUE' -and $_.isLiveMount -eq 'TRUE'}

    if($dbs)
    {
        try{
            Write-Verbose ("Getting LM Databases for Instance [$HostName].")
            $sqlQuery = "SELECT db_name(database_id) as dbName, 
                                detachCMD = 'sp_detach_db @dbname = N'''+db_name(database_id)+''';',
                                attachCMD = 'CREATE DATABASE ['+db_name(database_id)+'] ON ' + STUFF(
                                            (SELECT ',(FILENAME =''' + physical_name +''')' FROM sys.master_files B WHERE b.database_id = a.database_id FOR XML PATH ('')), 1, 1, ''
                                        )+' FOR ATTACH;',
                                physical_name = STUFF(
                                                (SELECT ',' + physical_name FROM sys.master_files B WHERE b.database_id = a.database_id FOR XML PATH ('')), 1, 1, ''
                                            )
                        FROM sys.master_files A WHERE database_id > 4 GROUP BY database_id;"
            $SQLDbs = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database master -Query  $sqlQuery
            
            #Database list to be detached
            $SQLDbs = $SQLDbs | Where-Object {$_.dbName -contains $dbs.name}
        }
        catch{
            Write-Verbose ("Could not connect to SQLServer Instance [$HostName].");
            Write-Error $_
            return
        }   

        try {
            foreach ($sqlDb in $SQLDbs){
                #dettach
                Write-Verbose ("Detaching Database [$($sqlDb.dbName)] from [$ServerInstance].");
                (Invoke-Sqlcmd -ServerInstance $ServerInstance -Database master -Query  $($sqlDb.detachCMD) -WarningAction Ignore);
                
                #copy files
                $arr = $sqldb.physical_name -split ','
                $x=0       
                while($x -ne $arr.count)
                {
                    Write-Verbose ("Copying Database file [$($arr[$x])] to [$destination].");                    
                    Copy-Item –Path $arr[$x] –Destination $destination -Confirm:$False;
                    $x++
                }
                #attach
                Write-Verbose ("Attaching Database [$($sqlDb.dbName)] to [$ServerInstance].");
                (Invoke-Sqlcmd -ServerInstance $ServerInstance -Database master -Query  $($sqlDb.attachCMD) -WarningAction Ignore);
            }
            Write-Host "Process completed" -ForegroundColor Green
        }
        catch {
            Write-Verbose ("Could not detach LM database [$database] at Instance [$HostName].")
            Write-Error $_
            return
        }
    }
    else {
        Write-Error "There are no Live Mounted at [$HostName]"
    }
}