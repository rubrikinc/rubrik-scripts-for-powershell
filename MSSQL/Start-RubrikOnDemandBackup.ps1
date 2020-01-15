<#
.SYNOPSIS
Start-RubrikOnDemandBackup is used to run on-demand snapshots or log backups against MSSQL Databases

It is important to note....This script will work on Rubrik Versions 5.1 and later. If you try to run this on an earlier version of Rubrik, the script will fail as the endpoints do not exist. 

.DESCRIPTION
Based on parameters supplied, Start-RubrikOnDemandBackup will be used to backup All databases, all User databases, all system 
databases, a list of specific databases. This script will kick off an async request in Rubrik for a new snapshot of each 
database. The script will then wait for all databases to complete, and return back an object with each database and their 
respective success/failure status.

It is important to note....This script will work on Rubrik Versions 5.1 and later. If you try to run this on an earlier version of Rubrik, the script will fail as the endpoints do not exist. 

.PARAMETER RubrikServer
Rubrik Cluster

.PARAMETER RubrikCredentialFile
Full path and file name of the credential file to be used to authenticate to the Rubrik server. 

.PARAMETER Token
API Token string generated inside your Rubrik Cluster

.PARAMETER SQLServerInstance
SQL Server Instance Name
    If Named Instance: host\instance
    If Default Instance: host

.PARAMETER UserDatabases
Switch to denote that all user databases should be backed up. These will be any database that is not master, model, msdb, tempdb, distribution

.PARAMETER SystemDatabases
Switch to denote that all system database should be backed up. This will backup distribution, master, model, and msdb. Tempdb is always excluded
as this database cannot be backed up inside of SQL Server

.PARAMETER ExclusionList
A comma separated list of databases that should be excluded from the backup process. To be used as part of AllDatabases or UserDatabases

.PARAMETER DatabaseList
A comma separated list of databases that will be backed up.

.PARAMETER BackupType
Must be either Full or Log. If Full , then we will do an on-demand snapshot of the database. If Log, then a transaction log backup will be started. 

.PARAMETER SLAName
Name of the SLA Domain to be applied to this backup. If no SLAName is provided, then we will use the current assigned
SLA Domain on the database

TODO
.PARAMETER ExcludeReadOnly
Exlcude databases that are in a read only state in SQL Server

Add a config file for automating the connection. Will make it easier for scheduling and runtime. 

Backup databases just in a specific AG

.EXAMPLE
Backup all databases on an instance of SQL Server. 
.\Start-RubrikOnDemandBackup.ps1 -RubrikServer 172.256.256.256 `
    -SQLServerInstance sql1.domain.com `
    -RubrikCredentialFile "C:\temp\Rubrik.credential"
    
.EXAMPLE
Backup all user databases
.\Start-RubrikDBBackup.ps1 -RubrikServer 172.256.256.256 `
    -SQLServerInstance sql1.domain.com `
    -UserDatabases `
    -RubrikCredentialFile "C:\temp\Rubrik.credential"

.EXAMPLE
Backup all system databases
.\Start-RubrikDBBackup.ps1 -RubrikServer 172.256.256.256 `
    -SQLServerInstance sql1.domain.com `
    -SystemDatabases `
    -RubrikCredentialFile "C:\temp\Rubrik.credential"

.EXAMPLE
Backup a selection of databases
.\Start-RubrikDBBackup.ps1 -RubrikServer 172.256.256.256 `
    -SQLServerInstance sql1.domain.com `
    -DatabaseList db1, db2 `
    -RubrikCredentialFile "C:\temp\Rubrik.credential"

.EXAMPLE
Exclude databases from a backup job
.\Start-RubrikDBBackup.ps1 -RubrikServer 172.256.256.256 `
    -SQLServerInstance sql1.domain.com `
    -ExclusionList db1, db2
    -RubrikCredentialFile "C:\temp\Rubrik.credential"

.EXAMPLE
Backup databases with a specific SLA Domain
.\Start-RubrikDBBackup.ps1 -RubrikServer 172.256.256.256 `
    -SQLServerInstance sql1.domain.com `
    -AllDatabases `
    -RubrikCredentialFile "C:\temp\Rubrik.credential"
    -SLAName "Gold"

.NOTES
Name:               Start Rubrik Database On-Demand Backup
Created:            12/11/2019
Author:             Chris Lumnah
Execution Process:
    Before running this script, you need to create a credential file so that you can securly log into the Rubrik 
    Cluster. To do so run the below command via Powershell
    $Credential = Get-Credential
    $Credential | Export-CliXml -Path .\rubrik.Cred"
            
    The above will ask for a user name and password and them store them in an encrypted xml file.


    It is important to note....This script will work on Rubrik Versions 5.1 and later. If you try to run this on an earlier version of Rubrik, the script will fail as the endpoints do not exist. 
#>
[CmdletBinding(DefaultParameterSetName = 'ServerInstance')]
param(
    [Parameter(Mandatory=$true, Position=0)]   
    [string]$RubrikServer,
    
    [Parameter(ParameterSetName = 'CredentialFile', Position=1)]
    [string]$RubrikCredentialFile,
    
    [Parameter(ParameterSetName = 'Token', Position=1)]
    [string]$Token,
    
    [Parameter(Mandatory=$true, Position=2)]   
    [string]$SQLServerInstance,

    [Parameter(ParameterSetName = 'CredentialFile')]
    [Parameter(ParameterSetName = 'Token')]
    [Parameter(ParameterSetName = 'UserDatabases', Position=3)]    
    [switch]$UserDatabases = $false,

    [Parameter(ParameterSetName = 'CredentialFile')]
    [Parameter(ParameterSetName = 'Token')]
    [Parameter(ParameterSetName = 'SystemDatabases', Position=3)]    
    [switch]$SystemDatabases = $false,

    [Parameter(ParameterSetName = 'CredentialFile')]
    [Parameter(ParameterSetName = 'Token')]
    [Parameter(ParameterSetName = 'DatabaseList', Position=3)]    
    [string[]]$DatabaseList,

    [Parameter(ParameterSetName = 'CredentialFile')]
    [Parameter(ParameterSetName = 'Token')]
    [Parameter(ParameterSetName = 'ExclusionList', Position=3)]    
    [string[]]$ExclusionList,

    [ValidateSet("Full", "Log")]
    [string]$BackupType = "Full",

    [Parameter(Position=4)]
    [string]$SLAName
)

######################################################################################################################################################
#region Connection to Rubrik
switch($true){
    {$RubrikCredentialFile} {$RubrikCredential = Import-CliXml -Path $RubrikCredentialFile
        $ConnectRubrik = @{
            Server = $RubrikServer
            Credential = $RubrikCredential
        }
    }
    {$Token} {
        $ConnectRubrik = @{
            Server = $RubrikServer
            Token = $Token
        }
    }
    default {
        $ConnectRubrik = @{
            Server = $RubrikServer
        }
    }
}

Connect-Rubrik @ConnectRubrik
#endregion

#region Get all databases on a given instance of SQL Server
$RubrikSQLInstance = Get-RubrikSQLInstance -ServerInstance $SQLServerInstance

$rbkVersion = $global:RubrikConnection.version
# :TODO
# Filter out Live mounts and Relics from both calls
if ($rbkVersion.Split(".")[0] -ge 5 -and $rbkVersion.Split(".")[1] -ge 1){
    $RubrikHierarchyChildren = (Invoke-RubrikRESTCall -Endpoint "mssql/hierarchy/$($RubrikSQLInstance.id)/children" -Method GET).data    
}else{
    $RubrikHierarchyChildren = Get-RubrikDatabase | Where-Object {$_.replicas.instanceId -eq $RubrikSQLInstance.id -and $_.isrelic -eq $False}
}
#endregion


#region Take data from returned from Rubrik and build a queue so we can monitor the backup prgress
[System.Collections.ArrayList] $DatabasesToBeBackedUp = @()
foreach ($RubrikDatabase in $RubrikHierarchyChildren) {
    $db = New-Object PSObject
    $db | Add-Member -type NoteProperty -name id -Value $RubrikDatabase.id
    $db | Add-Member -type NoteProperty -name Name -Value $RubrikDatabase.name
    $db | Add-Member -type NoteProperty -name Exclude -Value $false
    $db | Add-Member -type NoteProperty -name isInAvailabilityGroup -Value $RubrikDatabase.isInAvailabilityGroup
    if ($rbkVersion.Split(".")[0] -ge 5 -and $rbkVersion.Split(".")[1] -ge 1){
        if ($RubrikDatabase.isInAvailabilityGroup -eq $true){
            $db | Add-Member -type NoteProperty -name infraPathName -Value $RubrikDatabase.infraPath[0].name
            $db | Add-Member -type NoteProperty -name infraPathid -Value $RubrikDatabase.infraPath[0].id
        }else{
            $db | Add-Member -type NoteProperty -name infraPathName -Value $RubrikDatabase.infraPath[0].name
            $db | Add-Member -type NoteProperty -name infraPathid -Value $RubrikDatabase.infraPath[1].id
        }
    }else{
        if ($RubrikDatabase.isInAvailabilityGroup -eq $true){
            $db | Add-Member -type NoteProperty -name infraPathName -Value $RubrikDatabase.rootProperties.rootName
            $db | Add-Member -type NoteProperty -name infraPathid -Value $RubrikDatabase.rootProperties.rootId
        }else{
            $db | Add-Member -type NoteProperty -name infraPathName -Value $RubrikDatabase.rootProperties.rootName
            $db | Add-Member -type NoteProperty -name infraPathid -Value $RubrikDatabase.instanceid
        }

    }
    
    
    $db | Add-Member -type NoteProperty -name RubrikRequest -Value ""
    
    if (-not ([string]::IsNullOrEmpty($SLAName))) {
        $RubrikSLA = Get-RubrikSLA -Name $SLAName 
        $db | Add-Member -type NoteProperty -name RubrikSLADomain -Value $RubrikSLA.Name
    }else{
        $db | Add-Member -type NoteProperty -name RubrikSLADomain -Value $RubrikDatabase.effectiveSlaDomainName
    }
    $DatabasesToBeBackedUp += $db
}

#endregion

#region Database Exclusions
#Set List of system databases
$SystemDatabaseList = @('master', 'model', 'msdb', 'SSISDB', 'distribution')

foreach ($Database in $DatabasesToBeBackedUp){
    switch ($PSBoundParameters.Keys) {
        'UserDatabases' {
            if ($SystemDatabaseList -contains $Database.name){
                $Database.Exclude = $true
            }
        }
        'SystemDatabases' {
            if ($SystemDatabaseList -notcontains $Database.name){
                $Database.Exclude = $true
            }
        }
        'DatabaseList' {
            if ($DatabaseList -notcontains $Database.name){
                $Database.Exclude = $true
            }
        }
        'ExclusionList' {
            if ($ExclusionList -contains $Database.name){
                $Database.Exclude = $true
            }
        }

        'Default' {}
    }
}
$DatabasesToBeBackedUp | Sort-Object name | ft *
#endregion


#region Start Backups
#Kick off the backup of each database
if ($BackupType -eq 'Full'){
    foreach ($Database in $DatabasesToBeBackedUp | Where-Object { $_.Exclude -eq $false }) {
        Write-Host "Starting On-Demand Snapshot of $($Database.name)"
        $RubrikRequest = New-RubrikSnapshot -id $Database.id -SLA $Database.RubrikSLADomain -Confirm:$false 
        $Database.RubrikRequest = $RubrikRequest
    }
}else{
    foreach ($Database in $DatabasesToBeBackedUp | Where-Object { $_.Exclude -eq $false }) {
        Write-Host "Starting On-Demand Log Backup of $($Database.name)"
        $RubrikRequest = New-RubrikLogBackup -id $Database.id 
        $Database.RubrikRequest = $RubrikRequest
    }
}
#endregion

#region Wait for each backup to finish
#Check the status of the requested backup
Write-Host "Waiting for all backups to finish"
foreach ($Database in $DatabasesToBeBackedUp | Where-Object { $_.Exclude -eq $false }) {
    Write-Host "Waiting for backup of $($Database.name) to complete"
    $Database.RubrikRequest = Get-RubrikRequest -id $Database.RubrikRequest.id -Type mssql -WaitForCompletion
}
#endregion
return $DatabasesToBeBackedUp
