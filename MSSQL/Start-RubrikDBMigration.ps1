<#
.SYNOPSIS
    Start-RubrikDBMigration.ps1 migrates databases from one server to another via Rubrik
.DESCRIPTION
    Start-RubrikDBMigration.ps1 migrates databases from one server to another via Rubrik. Script is meant for 
    small environments. For larger environments consider using log shipping
.PARAMETER RubrikCluster
    The IP address or name to your Rubrik Cluster
.PARAMETER SourceSQLHost
    The host name to the source SQL Server
.PARAMETER SourceInstance
    The instance for the SQL Server. Parameter is optional if usinga default instance. 
.PARAMETER Databases
    Provide a single database or a comma separated list of databases. 
.PARAMETER TargetSQLHost
    The host name to the target SQL Server
.PARAMETER TargetInstance
    The instance for the SQL Server. Parameter is optional if usinga default instance. 
.PARAMETER TargetDataPath
    Path on the target SQL Server where SQL Server data files should live
.PARAMETER TargetLogPath
    Path on the target SQL Server where SQL Server log files should live
.PARAMETER TurnOffOldDBs
    If used, databases on Source SQL Server Instance will be set to read only and then set to offline
    after the backup has been taken. 
.EXAMPLE
    PS C:\> .\Start-RubrikDBMigration.ps1 `
        -RubrikCluster 172.21.54.18 `
        -SourceSQLHost SQL2012 `
        -Databases AdventureWorks2012, AdventureWorksDW2012, RetrosheetOrg `
        -TargetSQLHost SQL2016 `
        -TargetDataPath D:\SQLData `
        -TargetLogPath L:\SQLLogs `
        -TurnOffOldDBs
    Will migrate databases from source server to target server and will set the databses on the source server
    to read only and then to offline once backup has been taken. 
.EXAMPLE
    PS C:\> .\Start-RubrikDBMigration.ps1 `
        -RubrikCluster 172.21.54.18 `
        -SourceSQLHost SQL2012 `
        -Databases AdventureWorks2012, AdventureWorksDW2012, RetrosheetOrg `
        -TargetSQLHost SQL2016 `
        -TargetDataPath D:\SQLData `
        -TargetLogPath L:\SQLLogs 
    Will migrate databases from source server to target server and will NOT set the databses on the source server
    to read only and then to offline once backup has been taken. This is good for testing the migration process. 
.NOTES
    Author:     Chris Lumnah
    Created:    10/20/2018
    Company:    Rubrik Inc
    https://github.com/rubrik-devops/powershell-scripts
#>
param(
    [Parameter(Mandatory=$true)]
    [String]$RubrikCluster,

    [Parameter(Mandatory=$true)]
    [String]$SourceSQLHost,
    
    [Parameter(Mandatory=$false)]
    [String]$SourceInstance = 'MSSQLSERVER',

    [Parameter(Mandatory=$true)]
    [String[]]$Databases,

    [Parameter(Mandatory=$true)]
    [String]$TargetSQLHost,

    [Parameter(Mandatory=$false)]
    [String]$TargetInstance = 'MSSQLSERVER',
    
    [Parameter(Mandatory=$true)]
    [String]$TargetDataPath,
    
    [Parameter(Mandatory=$true)]
    [String]$TargetLogPath,
    
    [switch]$TurnOffOldDBs
)

Import-Module Rubrik
Import-Module SQLServer

$Credential = (Get-Credential -Message "Enter User ID and Password to connect to Rurbik Cluster" )
Connect-Rubrik -Server $RubrikCluster -Credential $Credential

$SourceServerInstance = $SourceSQLHost
if ($SourceInstance.ToUpper() -ne 'MSSQLSERVER')
{
    $SourceServerInstance = "$($SourceSQLHost)\$($SourceInstance)"
}

#Create an object to store databases to be backed up
[System.Collections.ArrayList] $DatabasesToBeMigrated=@()
foreach ($Database in $Databases)
{
    $db = New-Object PSObject
    $db | Add-Member -type NoteProperty -name HostName -Value $SourceSQLHost
    $db | Add-Member -type NoteProperty -name Instance -Value $SourceInstance
    $db | Add-Member -type NoteProperty -name Name -Value $Database
    $db | Add-Member -type NoteProperty -name SourceServerInstance -Value $SourceServerInstance
    $db | Add-Member -type NoteProperty -name ID -Value ""
    $db | Add-Member -type NoteProperty -name RubrikRequestID -Value ""
    $db | Add-Member -type NoteProperty -name RubrikRequestStatus -Value ""
    $db | Add-Member -type NoteProperty -name RubrikRequestProgress -Value ""
    $db | Add-Member -type NoteProperty -name RubrikSLADomain -Value ""
    $db | Add-Member -type NoteProperty -name isLiveMount -Value ""
    $DatabasesToBeMigrated += $db
}

#Backup each database via an async job on Rubrik appliance
Foreach($Database in $DatabasesToBeMigrated)
{
    if($TurnOffOldDBs)
    {
        Write-Host "Setting $($Database.Name) to Read Only"
        $Query = "ALTER DATABASE [$($Database.Name)] SET READ_ONLY WITH NO_WAIT"
        Invoke-Sqlcmd -ServerInstance $Database.SourceServerInstance -Query $Query
    }

    $RubrikDatabase = Get-RubrikDatabase -Name $Database.Name -Hostname $Database.HostName -Instance $Database.Instance.ToUpper()
    $Database.id = $RubrikDatabase.ID
    Write-Host "Kicking off a on demand backup of $($Database.Name)"
    $RubrikRequest = New-RubrikSnapshot -id $RubrikDatabase.id -SLA $RubrikDatabase.effectiveSlaDomainName -Confirm:$false
    $Database.RubrikRequestID = $RubrikRequest.id

}

#Wait for all backups to complete
do
{
    foreach ($Database in $DatabasesToBeMigrated | where-object {-not ([string]::IsNullOrEmpty($_.RubrikRequestID)) -and $_.RubrikRequestStatus -notin 'FAILED','SUCCEEDED' })
    {
        $Request = Get-RubrikRequest -id $Database.RubrikRequestId -Type 'mssql'
        $Database.RubrikRequestStatus = $Request.Status
        if ($Request.Status -eq 'RUNNING'){$Database.RubrikRequestProgress = $Request.Progress}
        Write-Host "Checking $($Database.Name) backup progress. $($Request.Progress) complete. Current Status is $($Request.Status)"
    }
    $x=$DatabasesToBeMigrated | where-object {-not ([string]::IsNullOrEmpty($_.RubrikRequestID)) -and $_.RubrikRequestStatus -notin 'FAILED','SUCCEEDED' } | Measure-Object
}until ($x.count -eq 0)

#Lets Start doing Restores 
$TargetRubrikInstance = Get-RubrikSQLInstance -Hostname $TargetSQLHost -Name $TargetInstance.ToUpper()
$TargetServerInstance = $TargetSQLHost
if ($TargetInstance -ne "MSSQLSERVER")
{
    $TargetServerInstance = "$($TargetSQLHost)\$($TargetInstance)"
}

#Clean up the target server and get rid of the database if it already exists. 
Foreach($Database in $DatabasesToBeMigrated)
{
    $Database.RubrikRequestID = ""
    $Database.RubrikRequestStatus = ""
    $Database.RubrikRequestProgress = ""

    if($TurnOffOldDBs)
    {
        Write-Host "Setting $($Database.Name) offline on $($Database.SourceServerInstance)"
        $Query = "ALTER DATABASE [$($Database.Name)] SET OFFLINE"
        Invoke-Sqlcmd -ServerInstance $Database.SourceServerInstance -Query $Query
    }

    $Query = "SELECT state_desc FROM sys.databases WHERE name = '" + $Database.Name + "'" 
    $Results = Invoke-Sqlcmd -ServerInstance $TargetServerInstance -Query $Query

    if ([bool]($Results.PSobject.Properties.name -match "state_desc") -eq $true)
    {
        IF ($Results.state_desc -eq 'ONLINE')
        {
            Write-Host "Setting $($Database.Name) to SINGLE_USER"
            Write-Host "Dropping $($Database.Name)"
            $Query = "ALTER DATABASE [" + $Database.Name + "] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; `nDROP DATABASE [" + $Database.Name + "]"
            $Results = Invoke-Sqlcmd -ServerInstance $TargetServerInstance -Query $Query
        }
        else 
        {
            Write-Host "Dropping $($Database.Name)"
                $Query = "DROP DATABASE [" + $Database.Name + "]"
                $Results = Invoke-Sqlcmd -ServerInstance $TargetServerInstance -Query $Query -Database master
        }
    }
    
    #Refresh Rubik so it does not think the database still exists
    Write-Host "Refreshing $($TargetSQLHost) in Rubrik"
    New-RubrikHost -Name $TargetSQLHost -Confirm:$false | Out-Null
    
    $RubrikDatabaseFiles = Get-RubrikDatabaseFiles -Id $Database.ID -RecoveryDateTime (Get-RubrikDatabase -id $Database.ID).latestRecoveryPoint

    $TargetFiles = @()
    foreach ($RubrikDatabaseFile in $RubrikDatabaseFiles)
    {
        if ($RubrikDatabaseFile.islog -eq $true)
        {
            $TargetFiles += @{logicalName=$RubrikDatabaseFile.logicalName;exportPath=$TargetLogPath;newFilename=$RubrikDatabaseFile.originalName}       
        }
        else 
        {
            $TargetFiles += @{logicalName=$RubrikDatabaseFile.logicalName;exportPath=$TargetDataPath;newFilename=$RubrikDatabaseFile.originalName}       
        }
    }
    Write-Host "Starting restore of $($Database.Name) onto $($TargetServerInstance)"
    $RubrikRequest = Export-RubrikDatabase -Id $Database.id `
        -TargetInstanceId $TargetRubrikInstance.id `
        -TargetDatabaseName $Database.Name `
        -recoveryDateTime (Get-RubrikDatabase -id $Database.ID).latestRecoveryPoint `
        -FinishRecovery `
        -TargetFilePaths $TargetFiles `
        -Confirm:$false

    $Database.RubrikRequestID = $RubrikRequest.id

}

#Wait for all restores to complete
do
{
    foreach ($Database in $DatabasesToBeMigrated | where-object {-not ([string]::IsNullOrEmpty($_.RubrikRequestID)) -and $_.RubrikRequestStatus -notin 'FAILED','SUCCEEDED' })
    {
        $Request = Get-RubrikRequest -id $Database.RubrikRequestId -Type 'mssql'
        $Database.RubrikRequestStatus = $Request.Status
        if ($Request.Status -eq 'RUNNING'){$Database.RubrikRequestProgress = $Request.Progress}
        Write-Host "Checking $($Database.Name) restore progress. $($Request.Progress) complete"
    }
    $x=$DatabasesToBeMigrated | where-object {-not ([string]::IsNullOrEmpty($_.RubrikRequestID)) -and $_.RubrikRequestStatus -notin 'FAILED','SUCCEEDED' } | Measure-Object
}until ($x.count -eq 0)

if($TurnOffOldDBs)
{
    Foreach($Database in $DatabasesToBeMigrated)
    {
        Write-Host "Setting $($Database.Name) to Read Write"
        $Query = "ALTER DATABASE [$($Database.Name)] SET READ_WRITE"
        Invoke-Sqlcmd -ServerInstance $TargetServerInstance -Query $Query
    }
}