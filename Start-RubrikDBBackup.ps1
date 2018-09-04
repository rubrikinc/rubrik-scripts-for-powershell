<#
.SYNOPSIS
Start-RubrikDBBackup is used to run full backups against a set of databases on an instance of SQL

.DESCRIPTION
Based on parameters supplied, Start-RubrikDBBackup will be used to backup All databases, all User databases, all system 
databases, a list of specific databases. This script will kick off an async request in Rubrik for a new snapshot of each 
database. The script will then wait for all databases to complete, and return back an object with each database and their 
respective success/failure status. One thing to note, we will not backup databases that are offline or not in a read_write status

.PARAMETER HostName
SQL Server Host name

.PARAMETER Instance
Instance name of SQL Server. If default instance use MSSQLSQLSERVER. If named instance, use the name of the instance

.PARAMETER AllDatabases
Switch to denote that all databases should be backed up

.PARAMETER UserDatabases
Switch to denote that all user databases should be backed up. These will be any database that is not master, model, msdb, tempdb

.PARAMETER SystemDatabases
Switch to denote that all system database should be backed up. This will backup master, model, and msdb. Tempdb is always excluded
as this database cannot be backed up inside of SQL Server

.PARAMETER ExclusionList
A comma separated list of databases that should be excluded from the backup process. To be used as part of AllDatabases or UserDatabases

.PARAMETER DatabaseList
A comma separated list of databases that will be backed up.

.PARAMETER RubrikServer
IP address or the name of the Rubrik Server we should connect to

.PARAMETER RubrikCredentialFile
Full path and file name of the credential file to be used to authenticate to the Rubrik server. 

.PARAMETER SLAName
Name of the SLA Domain to be applied to this backup. If no SLAName is provided, then we will use the current assigned
SLA Domain on the database

.EXAMPLE
Backup all databases
.\Start-RubrikDBBackup.ps1 -HostName sql1.domain.com `
    -instance mssqlserver `
    -AllDatabases `
    -RubrikServer 172.21.8.51 `
    -RubrikCredentialFile "C:\temp\Rubrik.credential"

.EXAMPLE
Backup all user databases
.\Start-RubrikDBBackup.ps1 -HostName sql1.domain.com `
    -instance mssqlserver `
    -UserDatabases `
    -RubrikServer 172.21.8.51 `
    -RubrikCredentialFile "C:\temp\Rubrik.credential"

.EXAMPLE
Backup all system databases
.\Start-RubrikDBBackup.ps1 -HostName sql1.domain.com `
    -instance mssqlserver `
    -SystemDatabases `
    -RubrikServer 172.21.8.51 `
    -RubrikCredentialFile "C:\temp\Rubrik.credential"

.EXAMPLE
Backup a selection of databases
.\Start-RubrikDBBackup.ps1 -HostName sql1.domain.com `
    -instance mssqlserver `
    -DatabaseList DB1, DB2 `
    -RubrikServer 172.21.8.51 `
    -RubrikCredentialFile "C:\temp\Rubrik.credential"

.EXAMPLE
Exclude databases from a backup job
.\Start-RubrikDBBackup.ps1 -HostName sql1.domain.com `
    -instance mssqlserver `
    -AllDatabases `
    -ExclusionList db1, db2 `
    -RubrikServer 172.21.8.51 `
    -RubrikCredentialFile "C:\temp\Rubrik.credential"

.\Start-RubrikDBBackup.ps1 -HostName sql1.domain.com `
    -instance mssqlserver `
    -UserDatabases `
    -ExclusionList db1, db2 `
    -RubrikServer 172.21.8.51 `
    -RubrikCredentialFile "C:\temp\Rubrik.credential"

.EXAMPLE
Backup databases with a specific SLA Domain
.\Start-RubrikDBBackup.ps1 -HostName sql1.domain.com `
    -instance mssqlserver `
    -AllDatabases `
    -ExclusionList db1, db2 `
    -RubrikServer 172.21.8.51 `
    -RubrikCredentialFile "C:\temp\Rubrik.credential" `
    -SLAName "Gold"

.NOTES
Name:               Start Rubrik Database Backup
Created:            05/23/2018
Author:             Chris Lumnah
Execution Process:
    Before running this script, you need to create a credential file so that you can securly log into the Rubrik 
    Cluster. To do so run the below command via Powershell
    $Credential = Get-Credential
    $Credential | Export-CliXml -Path .\rubrik.Cred"
            
    The above will ask for a user name and password and them store them in an encrypted xml file.
#>

param
(
    [Parameter(Mandatory=$true, Position=1)]
    [string]$HostName,
    [Parameter(Mandatory=$true, Position=2)]
    [string]$Instance, 

    [Parameter(Mandatory=$true,ParameterSetName='AllDatabases')]
    [switch]$AllDatabases,
    
    [Parameter(Mandatory=$true,ParameterSetName='UserDatabases')]
    [switch]$UserDatabases,
    
    [Parameter(Mandatory=$true,ParameterSetName='SystemDatabases')]
    [switch]$SystemDatabases,
    
    [Parameter(Mandatory=$false, ParameterSetName='AllDatabases')]
    [Parameter(Mandatory=$false, ParameterSetName='UserDatabases')]
    [string[]]$ExclusionList,

    [Parameter(ParameterSetName='DatabaseList')]
    [string[]]$DatabaseList,

    [Parameter(Mandatory=$true)]
    [string]$RubrikServer,

    [Parameter(Mandatory=$true)]
    [string]$RubrikCredentialFile,

    [Parameter(Mandatory=$false)]
    [string]$SLAName 
)

BEGIN
{
    import-module sqlserver
    import-module Rubrik
    $RubrikCredential = Import-CliXml -Path $RubrikCredentialFile
    
    #Create comma separated lists that has each value enclosed in single quotes. This will get used later in TSQL Statements
    for ($i=0; $i -lt $ExclusionList.Count; $i++) {
        $ExclusionList[$i] = "'" + $ExclusionList[$i] + "'"
    }
    $ExclusionList = $ExclusionList -join ","

    for ($i=0; $i -lt $DatabaseList.Count; $i++) {
        $DatabaseList[$i] = "'" + $DatabaseList[$i] + "'"
    }
    $DatabaseList = $DatabaseList -join ","

    switch ($true)
    {
        {$AllDatabases}     {$Query = "select name `nfrom master.sys.databases `nwhere name not in ('tempdb') `nand DATABASEPROPERTYEX(name, 'STATUS') = 'ONLINE' `nand DATABASEPROPERTYEX(NAME, 'Updateability') = 'READ_WRITE'"}
        {$UserDatabases}    {$Query = "select name `nfrom master.sys.databases `nwhere name not in ('master','model','msdb','tempdb') `nand DATABASEPROPERTYEX(name, 'STATUS') = 'ONLINE' `nand DATABASEPROPERTYEX(NAME, 'Updateability') = 'READ_WRITE'"}
        {$SystemDatabases}  {$Query = "select name `nfrom master.sys.databases `nwhere name in ('master','model','msdb') `nand DATABASEPROPERTYEX(name, 'STATUS') = 'ONLINE' `nand DATABASEPROPERTYEX(NAME, 'Updateability') = 'READ_WRITE'"}
        {$DatabaseList}     {$Query = "select name `nfrom master.sys.databases `nwhere name in ($DatabaseList) `nand DATABASEPROPERTYEX(name, 'STATUS') = 'ONLINE' `nand DATABASEPROPERTYEX(NAME, 'Updateability') = 'READ_WRITE'"}
        {$ExclusionList}        
        {
            switch ($true) 
            {
                {$AllDatabases}   {$Query = "select name `nfrom master.sys.databases `nwhere name not in ('tempdb',$ExclusionList) `nand DATABASEPROPERTYEX(name, 'STATUS') = 'ONLINE' `nand DATABASEPROPERTYEX(NAME, 'Updateability') = 'READ_WRITE'"}
                {$UserDatabases}  {$Query = "select name `nfrom master.sys.databases `nwhere name not in ('master','model','msdb','tempdb',$ExclusionLIst) `nand DATABASEPROPERTYEX(name, 'STATUS') = 'ONLINE' `nand DATABASEPROPERTYEX(NAME, 'Updateability') = 'READ_WRITE'"}
            }
        }
    }

    #Since Rubrik and SQL Server expect a different format for a server and host, here we put the host and instance together
    #based on traditional SQL expectations. We created a new variable called $ServerInstance which is expected by INVOKE-SQLCMD.
    if($Instance.ToUpper() -eq 'MSSQLSERVER')
    {
        $ServerInstance = $Hostname
    }
    else 
    {
        $ServerInstance = "$HostName\$Instance"
    }

    Write-Host "Gathering all databases based on selection used..."
    $Results = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database master -Query $Query 

    [System.Collections.ArrayList] $DatabasesToBeBackedUp=@()
    foreach ($Record in $Results)
    {
        $db = New-Object PSObject
        $db | Add-Member -type NoteProperty -name HostName -Value $HostName
        $db | Add-Member -type NoteProperty -name Instance -Value $Instance
        $db | Add-Member -type NoteProperty -name Name -Value $Record.name
        $db | Add-Member -type NoteProperty -name RubrikRequestID -Value ""
        $db | Add-Member -type NoteProperty -name RubrikRequestStatus -Value ""
        $db | Add-Member -type NoteProperty -name RubrikRequestProgress -Value ""
        $db | Add-Member -type NoteProperty -name RubrikSLADomain -Value ""
        $db | Add-Member -type NoteProperty -name isLiveMount -Value ""
        $DatabasesToBeBackedUp += $db
    }
    Write-Host "Connecting to Rubrik..."
    Connect-Rubrik -Server $RubrikServer -Credential $RubrikCredential | Out-Null
}

process
{
    #Start a backup for each databae in the list. With Rubrik, each backup is an async request
    #This means we can kick off a backup for each database in the list and then wait for all to be done. 
    foreach($Database in $DatabasesToBeBackedUp)
    {

        Write-Host "Getting information about $($Database.name) from Rubrik"
        $RubrikDatabase = Get-RubrikDatabase -Name $Database.Name -Hostname $Database.HostName -Instance $Database.Instance.ToUpper()
        
        if ($RubrikDatabase.isLiveMount -eq $true)
        {
            #If a database is a live mount, we must exclude from the backup process. This is because Rubrik by design does
            #not backup databases that are live mounts. Live mounts are just databases built from backups.
            $Database.isLiveMount = $true
            Write-Host "---Backup will not be taken of $($Database.name) as this a live mounted database"
        }
        else
        {
            $Database.isLiveMount = $false
            $Database.RubrikSLADomain = $RubrikDatabase.effectiveSlaDomainName
            if (-not ([string]::IsNullOrEmpty($SLAName)))
            {
                $RubrikSLA = Get-RubrikSLA -Name $SLAName 
                $Database.RubrikSLADomain = $RubrikSLA.Name
            }
        
            #If a database is not currently protected and an SLA Domain was not provided, we cannot backup the database. 
            #This is because we cannot assume how long the backup should be kept for. 
            if ($Database.RubrikSLADomain -ne "Unprotected")
            {
                Write-Host "--Initiating request for new snapshot of $($Database.name)"
                $RubrikRequest = New-RubrikSnapshot -id $RubrikDatabase.id -SLA $Database.RubrikSLADomain -Confirm:$false
                $Database.RubrikRequestID = $RubrikRequest.id
            }
            else
            {
                Write-Host "---Backup will not be taken of $($Database.name) as there is no SLA Domain assigned"
            }
        }
    }

    #With the above kicking off a backup for each database, we can now track each database to see if it has completed.
    #Here we run through a loop for each database in the list where the backup has not failed or succeeded.
    #We heck the status of each async job we submitted to Rubrik. Based on the job ID, we get back a status and a progress
    #Progress is a percent complete. Progress will only show up once the status changes from queued to running. If the status
    #is queued, you will get an error when asking for progress. 
    Write-Host "Checking status of backup requests..."
    do
    {
        foreach ($Database in $DatabasesToBeBackedUp | where-object {-not ([string]::IsNullOrEmpty($_.RubrikRequestID)) -and $_.RubrikRequestStatus -notin 'FAILED','SUCCEEDED' })
        {
            $Request = Get-RubrikRequest -id $Database.RubrikRequestId -Type 'mssql'
            $Database.RubrikRequestStatus = $Request.Status
            if ($Request.Status -eq 'RUNNING'){$Database.RubrikRequestProgress = $Request.Progress}
        }
        $x=$DatabasesToBeBackedUp | where-object {-not ([string]::IsNullOrEmpty($_.RubrikRequestID)) -and $_.RubrikRequestStatus -notin 'FAILED','SUCCEEDED' } | Measure-Object
    }until ($x.count -eq 0)
}
End
{
    return $DatabasesToBeBackedUp 
}
