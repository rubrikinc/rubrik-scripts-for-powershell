<#
    .SYNOPSIS
        Script to start Live Mount for a given databases
    .DESCRIPTION
        Script will Live Mount given databases from a SQL Server instance to a given target adding the suffix "_LM" at the LiveMounted database
        The script will unmount previous database for databases in the parameter $databases
    .PARAMETER databases
        Mandatory parameter, can be a array of database names    
    .PARAMETER SourceServerInstance
        SQL Server Instance name where the given database is hosted, this is the Source SQL Server instance. If default instance, then just use the server name, if a named instance, use
        Server\Instance
    .PARAMETER TargetServerInstance
        SQL Server Instance name where the databases will be mounted, this is the Target SQL Server instance. If default instance, then just use the server name, if a named instance, use
        Server\Instance 
    .PARAMETER RecoveryDateTime
        optional parameter, should be used if you want to Mount an specif point in time,
        The default Point In Time it will be the "Latest Recovery Point" if this parameter is not informed
    .EXAMPLE
        Example of how to run the script   
        
        Live Mounting databases using an specific point in time
        .\invoke-MassLiveMount.ps1 -databases ("tpcc","AdventureWorks2014","pubs","dbTest","dbTest2") `
                -SourceServerInstance "MF-SQL17-test" `
                -TargetServerInstance "MF-SQL17-01"`
                -RecoveryDateTime "07/01/2019 15:01:38" `
                -Verbose 

        Live Mounting databases using the latest recovey point
        .\invoke-MassLiveMount.ps1 -databases ("tpcc","AdventureWorks2014","pubs","dbTest","dbTest2") `
                -SourceServerInstance "MF-SQL17-test" `
                -TargetServerInstance "MF-SQL17-01"`
                -Verbose  
    .LINK
        None
    .NOTES
    Execution Process:
    Before running this script, you need to connect to the Rubrik cluster, and also ensure SQL Permission for account that will run this script.
        Ex.
        $RubrikServer = "172.21.8.51"
        #$RubrikCredential = (Get-Credential -Message 'Please enter your Rubrik credentials')
        Connect-Rubrik -Server $RubrikServer -Credential $RubrikCredential

        Created:    2019-07-01
        Author:     Marcelo Fernandes
        Notes:      Added parameter for Point In Time restore and changed the script to consider Log Backup as well (previously it was considering only snapshots)
#>

param(   [Parameter(Mandatory=$true)]
         [string[]]$databases
        ,[Parameter(Mandatory=$true)]
         [String]$SourceServerInstance
        ,[String]$TargetServerInstance
        ,[ValidateScript({get-date $_ })] 
         [datetime]$RecoveryDateTime
        )

Function ConvertFrom-ServerInstance($ServerInstance) {
    if($ServerInstance.Contains('\')){
        $si = $ServerInstance.Split('\')
        $return = New-Object psobject -Property @{'hostname'= $si[0];'instancename'=$si[1]}
    } else {
        $return = New-Object psobject -Property @{'hostname'= $ServerInstance;'instancename'='MSSQLSERVER'}
    }
    return $return
}

Function Wait-RubrikRequests($reqs) {
    do{
        Start-Sleep -Seconds 15
        $reqs = $reqs | Get-RubrikRequest -Type mssql -ErrorAction SilentlyContinue
    }until(($reqs | Where-Object {@('QUEUED','RUNNING','FINISHING') -contains $_.status} | Measure-Object).Count -eq 0)
}

$source = ConvertFrom-ServerInstance $SourceServerInstance
$target = ConvertFrom-ServerInstance $TargetServerInstance

$TargetInstance = (Get-RubrikSQLInstance -ServerInstance $target.hostname -name $target.instancename)

Write-Verbose "Begining unmount/cleanup process for: $($databases -join ",")"
$unmount_reqs = Get-RubrikDatabaseMount -TargetInstanceId $TargetInstance.id | 
    Where-Object {$databases -contains $_.sourceDatabaseName -and $_.isrelic -ne 'TRUE'} |
    Remove-RubrikDatabaseMount -Confirm:$false 

if($unmount_reqs) {Wait-RubrikRequests $unmount_reqs}

#Starting Live Mount DBs
"Begining mount process for: $($databases -join ",")" | Out-Host

$sourceDBs = Get-RubrikDatabase -Hostname $source.hostname -Instance $source.instancename |Where-Object {$databases -contains $_.Name -and $_.isrelic -ne 'TRUE' -and $_.isLiveMount -ne 'TRUE'} 
$mount_reqs = $sourceDBs | Get-RubrikDatabase |
    ForEach-Object{
    $date = if($RecoveryDateTime){ $RecoveryDateTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }else{ $_.latestRecoveryPoint};
    write-Verbose "Livemounting $($_.name) -Recovery Point- $(get-date $date) UTC";
    try{
        New-RubrikDatabaseMount -TargetInstanceId $TargetInstance.id -MountedDatabaseName "$($_.name)_LM" -RecoveryDateTime $date -id $_.id -confirm:$false
       }catch{$_}}
if($mount_reqs) {Wait-RubrikRequests $mount_reqs}


Write-Verbose "Validating the LM and generating reports"

#validating DB mounteds
$dbMounted = Get-RubrikDatabaseMount -TargetInstanceId $TargetInstance.id | Where-Object {$databases -contains $_.sourceDatabaseName -and $_.isrelic -ne 'TRUE'} 
if($dbMounted){Write-Host "Databases mounted successfully -- [$($dbMounted.sourceDatabaseName -join ",")]" -ForegroundColor Green}

#PITR not found
$pitr_nf = $sourceDBs | Where-Object {$databases -contains $_.Name -and $dbMounted.sourceDatabaseName -notcontains $_.Name } 
if($pitr_nf){Write-Host "Could not find the Recover Point Time [$RecoveryDateTime] for [$($pitr_nf.name -join ",")]" -ForegroundColor Yellow}

#DB not found
$DB_nf = $databases | where-object {$sourceDBs.name -notcontains $_}
if($DB_nf){Write-Host "Databases not found at [$SourceServerInstance] -- [$($DB_nf -join ",")]" -ForegroundColor Red}