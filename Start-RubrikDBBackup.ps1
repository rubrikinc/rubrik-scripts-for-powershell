<#
.SYNOPSIS
Start-RubrikDBBackup is used to run full backups against a set of databases on an instance of SQL

.DESCRIPTION
Based on parameters supplied, Start-RubrikDBBackup will be used to backup All databases, all User databases, all system 
databases, a list of specific databases. This script will kick off an async request in Rubrik for a new snapshot of each 
database. The script will then wait for all databases to complete, and return back an object with each database and their 
respective success/failure status. One thing to note, we will not backup databases that are offline or not in a read_write status

.PARAMETER ServerInstance
SQL Server Instance Name
    If Named Instance: host\instance
    If Default Instance: host

.PARAMETER AvailabilityGroup
In Rubrik, an Availability Group is a "Host" for the databases. It is a construct so we can keep the log chain in check regardless of 
what replica the backup is taken on. 

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

.PARAMETER ExcludeReadOnly
Exlcude databases that are in a read only state in SQL Server


.EXAMPLE
Backup all databases on an instance of SQL Server. Will NOT backup databaess on the instance that are in the availability group
.\Start-RubrikDBBackup.ps1 -RubrikServer 172.256.256.256 `
    -SQLServerInstance sql1.domain.com `
    -AllDatabases `
    -RubrikCredentialFile "C:\temp\Rubrik.credential"
    
.EXAMPLE
Backup all databases inside of an availability group
.\Start-RubrikDBBackup.ps1 -RubrikServer 172.256.256.256 `
    -AvailabilityGroupName AGName `
    -AllDatabases `
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
    -AllDatabases `
    -ExclusionList db1, db2
    -RubrikCredentialFile "C:\temp\Rubrik.credential"

.EXAMPLE
Exclude read only databases from a backup job
.\Start-RubrikDBBackup.ps1 -RubrikServer 172.256.256.256 `
    -SQLServerInstance sql1.domain.com `
    -AllDatabases `
    -ExcludeReadOnly
    -RubrikCredentialFile "C:\temp\Rubrik.credential"    

.EXAMPLE
Backup databases with a specific SLA Domain
.\Start-RubrikDBBackup.ps1 -RubrikServer 172.256.256.256 `
    -SQLServerInstance sql1.domain.com `
    -AllDatabases `
    -RubrikCredentialFile "C:\temp\Rubrik.credential"
    -SLAName "Gold"

.NOTES
Name:               Start Rubrik Database Backup
Created:            05/23/2018
Author:             Chris Lumnah
Updated:            4/8/2019
                    Script has been rewritten to allow for backups of a availability group. 
Execution Process:
    Before running this script, you need to create a credential file so that you can securly log into the Rubrik 
    Cluster. To do so run the below command via Powershell
    $Credential = Get-Credential
    $Credential | Export-CliXml -Path .\rubrik.Cred"
            
    The above will ask for a user name and password and them store them in an encrypted xml file.
#>
[CmdletBinding(DefaultParameterSetName = 'ServerInstance')]
param
(
    [Parameter(Mandatory=$true, ParameterSetName = 'ServerInstance', Position=0)]   
    [Parameter(Mandatory=$true, ParameterSetName = 'AvailabilityGroup', Position=0)]
    [string]$RubrikServer, 
    
    [Parameter(ParameterSetName = 'ServerInstance', Position=1)]
    [string]$SQLServerInstance,

    [Parameter(ParameterSetName = 'AvailabilityGroup', Position=1)]
    [string]$AvailabilityGroupName ,

    [Parameter(ParameterSetName = 'AllDatabases', Position=2)]
    [Parameter(ParameterSetName = 'ServerInstance', Position=2)]
    [Parameter(ParameterSetName = 'AvailabilityGroup', Position=2)]
    [switch]$AllDatabases,

    [Parameter(ParameterSetName = 'UserDatabases', Position=2)]
    [Parameter(ParameterSetName = 'ServerInstance', Position=2)]
    [Parameter(ParameterSetName = 'AvailabilityGroup', Position=2)]
    [switch]$UserDatabases,

    [Parameter(ParameterSetName = 'SystemDatabases', Position=2)]
    [Parameter(ParameterSetName = 'ServerInstance', Position=2)]
    [Parameter(ParameterSetName = 'AvailabilityGroup', Position=2)]
    [switch]$SystemDatabases,

    [Parameter(ParameterSetName = 'DatabaseList', Position=2)]
    [Parameter(ParameterSetName = 'ServerInstance', Position=2)]
    [Parameter(ParameterSetName = 'AvailabilityGroup', Position=2)]
    [string[]]$DatabaseList,

    [Parameter(ParameterSetName = 'AvailabilityGroup')]
    [Parameter(ParameterSetName = 'ServerInstance')]
    [Parameter(ParameterSetName = 'ExclusionList', Position=3)]
    [string[]]$ExclusionList,

    [Parameter(ParameterSetName = 'AvailabilityGroup')]
    [Parameter(ParameterSetName = 'ServerInstance')]
    [Parameter(ParameterSetName = 'AllDatabases')]
    [Parameter(Position=4)]
    [string]$SLAName,

    [Parameter(ParameterSetName = 'AvailabilityGroup')]
    [Parameter(ParameterSetName = 'ServerInstance')]
    [Parameter(Position=5)]
    [switch]$ExcludeReadOnly,

    [Parameter(ParameterSetName = 'AvailabilityGroup')]
    [Parameter(ParameterSetName = 'ServerInstance')]
    [Parameter(ParameterSetName = 'CredentialFile', Position=6)]
    [string]$RubrikCredentialFile,

    [Parameter(ParameterSetName = 'AvailabilityGroup')]
    [Parameter(ParameterSetName = 'ServerInstance')]
    [Parameter(ParameterSetName = 'Token', Position=6)]
    [string]$Token
)
function Get-RubrikRequestInfo {
    param(
        # Rubrik Request Object Info
        [Parameter(Mandatory = $true)]
        [PSObject]$RubrikRequest,
        # The type of request
        [Parameter(Mandatory = $true)]
        [ValidateSet('fileset', 'mssql', 'vmware/vm', 'hyperv/vm', 'managed_volume')]
        [String]$Type
    )
    
    $ExitList = @("SUCCEEDED", "FAILED")
    do {
        $RubrikRequestInfo = Get-RubrikRequest -id $RubrikRequest.id -Type $Type
        IF ($RubrikRequestInfo.progress -gt 0) {
            Write-Debug "$($RubrikRequestInfo.id) is $($RubrikRequestInfo.status) $($RubrikRequestInfo.progress) complete"
            Write-Progress -Activity "$($RubrikRequestInfo.id) is $($RubrikRequestInfo.status)" -status "Progress $($RubrikRequestInfo.progress)" -percentComplete ($RubrikRequestInfo.progress)
        }
        else {
            Write-Progress -Activity "$($RubrikRequestInfo.id)" -status "Job Queued" -percentComplete (0)
        }
        Start-Sleep -Seconds 1
    } while ($RubrikRequestInfo.status -notin $ExitList) 	
    return Get-RubrikRequest -id $RubrikRequest.id -Type $Type
}
######################################################################################################################################################
#region Connection to Rubrik
try{
    Get-Rubrikversion
}
catch{
    switch($true){
        {$RubrikCredentialFile} {$RubrikCredential = Import-CliXml -Path $RubrikCredentialFile
            Connect-Rubrik -Server $RubrikServer -Credential $RubrikCredential}
        {$Token}                {Connect-Rubrik -Server $RubrikServer -Token $Token}
        default                 {Connect-Rubrik -Server $RubrikServer}
        }
}
#endregion

#Set List of system databases
$SystemDatabaseList = @('master', 'model', 'msdb', 'SSISDB', 'distribution')

#region Create comma separated lists that has each value enclosed in single quotes. This will get used later in TSQL Statements
#for ($i=0; $i -lt $ExclusionList.Count; $i++) {
#    $ExclusionList[$i] = "'" + $ExclusionList[$i] + "'"
#}
#$ExclusionList = $ExclusionList -join ","
#$ExclusionList
#for ($i=0; $i -lt $DatabaseList.Count; $i++) {
#    $DatabaseList[$i] = "'" + $DatabaseList[$i] + "'"
#}
#$DatabaseList = $DatabaseList -join ","
#endregion

#region Create parameter splat based on AG or SQLInstance provided via parameters then use it to get databases from Rubrik
if ($AvailabilityGroupName) {
    $GetRubrikDatabase = @{
        HostName = $AvailabilityGroupName
    }
}
else {
    $GetRubrikDatabase = @{
        ServerInstance = $SQLServerInstance
    }
}

#Get Databases from Rubrik
switch ($true) {
    { $AllDatabases } {
        $RubrikDatabases = Get-RubrikDatabase @GetRubrikDatabase | 
        Where-Object { $_.isRelic -eq $false -and $_.isLivemount -eq $false }
    }
    { $UserDatabases } {
        $RubrikDatabases = Get-RubrikDatabase @GetRubrikDatabase | 
        Where-Object { $_.isRelic -eq $false -and $_.isLivemount -eq $false -and $_.name -notin $SystemDatabaseList }
    }
    { $SystemDatabases } {
        $RubrikDatabases = Get-RubrikDatabase @GetRubrikDatabase | 
        Where-Object { $_.isRelic -eq $false -and $_.isLivemount -eq $false -and $_.name -in $SystemDatabaseList }
    } 
    { $DatabaseList } {
        $RubrikDatabases = Get-RubrikDatabase @GetRubrikDatabase | 
        Where-Object { $_.isRelic -eq $false -and $_.isLivemount -eq $false -and $_.name -in $DatabaseList }
    }   
}            
#endregion

#region Take data from returned from Rubrik and build a queue so we can monitor the backup prgress
[System.Collections.ArrayList] $DatabasesToBeBackedUp = @()
foreach ($RubrikDatabase in $RubrikDatabases) {
    $db = New-Object PSObject
    $db | Add-Member -type NoteProperty -name Name -Value $RubrikDatabase.name
    $db | Add-Member -type NoteProperty -name id -Value $RubrikDatabase.id
    $db | Add-Member -type NoteProperty -name ServerInstance -Value $SQLServerInstance
    $db | Add-Member -type NoteProperty -name AvailabilityGroup -Value $AvailabilityGroupName
    $db | Add-Member -type NoteProperty -name RubrikRequest -Value ""
    
    $db | Add-Member -type NoteProperty -name RubrikSLADomain -Value $RubrikDatabase.effectiveSlaDomainName
    if (-not ([string]::IsNullOrEmpty($SLAName))) {
        $RubrikSLA = Get-RubrikSLA -Name $SLAName 
        $db | Add-Member -type NoteProperty -name RubrikSLADomain -Value $RubrikSLA.Name
    }

    if($ExclusionList -contains $RubrikDatabase.name  ){
        $db | Add-Member -type NoteProperty -name Exclude -Value $true
    }else{
        $db | Add-Member -type NoteProperty -name Exclude -Value $false
    }
    $DatabasesToBeBackedUp += $db
}
$DatabasesToBeBackedUp
#endregion

#TODO: Come back to this and work on exluding the read only databases of an instance of SQL
#Exclude databases based off of the status of the database being READ_ONLY
if ($ExcludeReadOnly) {
    foreach ($Database in $DatabasesToBeBackedUp) {
        $Query = "SELECT name, is_read_only FROM sys.databases WHERE name = '$($Database.name)'"
        $Results = Invoke-Sqlcmd -ServerInstance $SQLServerInstance -Query $Query
        if ($Results.is_read_only -eq 1) { $Database.Exclude = $true }
    }
}


#Kick off the backup of each database
foreach ($Database in $DatabasesToBeBackedUp | Where-Object { $_.Exclude -eq $false }) {
    Write-Host "Starting Backup of $($Database.name)"
    $RubrikRequest = New-RubrikSnapshot -id $Database.id -SLA $Database.RubrikSLADomain -Confirm:$false 
    $Database.RubrikRequest = $RubrikRequest
}

#Check the status of the requested backup
Write-Host "Waiting for all backups to finish"
foreach ($Database in $DatabasesToBeBackedUp | Where-Object { $_.Exclude -eq $false }) {
    $RubrikRequestInfo = Get-RubrikRequestInfo -RubrikRequest $Database.RubrikRequest -Type mssql
    $Database.RubrikRequest = $RubrikRequestInfo
}

Return $DatabasesToBeBackedUp