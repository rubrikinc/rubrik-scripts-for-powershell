<#
.SYNOPSIS
    Script will perform a Rubrik Restore of a database or list of databases
.DESCRIPTION
    Script will perform a Rubrik Restore of a database or list of databases
.EXAMPLE
    PS C:\> .\Restore-RubrikDatabasesJob.ps1 -RubrikServer 172.1.1.1 -SourceSQLHost sql1 -Database AdventureWorks2016 -RecoveryPoint Latest
    Will restore the latest backup of AdventureWorks2016 from the SQL1 server instance to the SQL2 server instance
.PARAMETER RubrikServer
    Rubrik Server should be the IP Address or your Rubrik Server Name. This will be the same value you use to access the Rubrik UI
.PARAMETER SourceSQLHost
    Source SQL Host is the name of the SQL Server Host. 
    If an SQL FCI, then this will be the Virtual Name given to SQL Server
    If an Availability Group, then this should be the availability group name
.PARAMETER SourceSQLInstance
    This is the name of the SQL Server Instance. 
    If referrencing a Default instance, then this should be MSSQLSERVER
    If referrencing a Named instance, then this should be the instance name
    This is defaulted to MSSQLSERVER if no value is provided. 
.PARAMETER Databases
    Provide a comma separated list of databases found on the source SQL Server and Instance
.PARAMETER RecoveryPoint
    A time  to which the database should be restored to. There are a few different possibilities
        latest:             This will tell Rubrik to export the database to the latest recovery point Rubrik knows about
                            This will include the last full and any logs to get to the latest recovery point
        last full:          This will tell Rubrik to restore back to the last full backup it has
        Format:             (HH:MM:SS.mmm) or (HH:MM:SS.mmmZ) - Restores the database back to the local or 
                            UTC time (respectively) at the point in time specified within the last 24 hours
        Format:             Any valid <value> that PS Get-Date supports in: "Get-Date -Date <Value>"
                            Example: "2018-08-01T02:00:00.000Z" restores back to 2AM on August 1, 2018 UTC.
.NOTES
    Name:       Restore databases via Rubrik
    Created:    9/19/2019
    Author:     Chris Lumnah

    This script should only be run by a DBA. This script should not be run in most circumstances. This script will restore a backup
    back to the original name, instance, and host. 
    
    !!!!!!!!!!!!!!!!!!!!!!THIS IS A DESTRUCTIVE SCRIPT!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!THIS IS A DESTRUCTIVE SCRIPT!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!THIS IS A DESTRUCTIVE SCRIPT!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!THIS IS A DESTRUCTIVE SCRIPT!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!THIS IS A DESTRUCTIVE SCRIPT!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!THIS IS A DESTRUCTIVE SCRIPT!!!!!!!!!!!!!!!!!!!!!!

    Unless you are a DBA and know what you are doing, this script could cause permanent data loss and cause a production outage. 

    Only use this script if your intention is to overwrite the database that the backup originated from. 

    DO NOT use this script if your intention is to make a copy of a database
    DO NOT use this script if your intention is refresh a database 
#>
[cmdletbinding()]
param(
    [Parameter(Position=0)]
    [String]$RubrikServer,
    [Parameter(Position=1)]
    [String]$SourceSQLHost,
    [Parameter(Position=2)]
    [String]$SourceSQLInstance,
    [Parameter(Position=3)]
    [String[]]$Databases,
    [Parameter(Position=4)]
    [string]$RecoveryPoint
)
Add-Type -AssemblyName PresentationCore,PresentationFramework
$MessageBoxText  = '
This script should only be run by a DBA. 
This script should not be run in most circumstances. 
This script will restore a backup back to the original name, instance, and host. 

!!!!!!!!!!!!!!!!!!!!!!THIS IS A DESTRUCTIVE SCRIPT!!!!!!!!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!THIS IS A DESTRUCTIVE SCRIPT!!!!!!!!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!THIS IS A DESTRUCTIVE SCRIPT!!!!!!!!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!THIS IS A DESTRUCTIVE SCRIPT!!!!!!!!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!THIS IS A DESTRUCTIVE SCRIPT!!!!!!!!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!THIS IS A DESTRUCTIVE SCRIPT!!!!!!!!!!!!!!!!!!!!!!

Unless you are a DBA and know what you are doing, this script could cause permanent data loss and cause a production outage. 

Only use this script if your intention is to overwrite the database that the backup originated from. 

DO NOT use this script if your intention is to make a copy of a database
DO NOT use this script if your intention is refresh a database ' 
$MessageBoxCaption = 'Are you sure you want to proceed?'
$MessageBoxButton = [System.Windows.MessageBoxButton]::YesNo
$MessageBoxImage = [System.Windows.MessageBoxImage]::Error
$MessageBoxResult = [System.Windows.MessageBoxResult]::No
$Result = [System.Windows.MessageBox]::Show($MessageBoxText, $MessageBoxCaption, $MessageBoxButton, $MessageBoxImage, $MessageBoxResult)

if ($Result -eq 'No'){break}

$DatabasesToBeRestored = @()
[string[]]$SystemDatabases = "master", "model", "msdb", "distribution", "SSISDB"
if ($Databases | Where-Object {$SystemDatabases -contains $_}){
    Clear-Host
    Write-Host "***************************************************************" -ForegroundColor Red
    Write-Host "*                                                             *" -ForegroundColor Red
    Write-Host "* You have provided a SQL Server System Database in your      *" -ForegroundColor Red
    Write-Host "*                                                             *" -ForegroundColor Red
    Write-Host "* list of databasees to be restored. This is NOT ALLOWED.     *" -ForegroundColor Red
    Write-Host "*                                                             *" -ForegroundColor Red
    Write-Host "* Please contact Rubrik Support to learn how to recover a     *" -ForegroundColor Red
    Write-Host "*                                                             *" -ForegroundColor Red
    Write-Host "* SQL Server System Database to your system                   *" -ForegroundColor Red
    Write-Host "*                                                             *" -ForegroundColor Red
    Write-Host "***************************************************************" -ForegroundColor Red
    break
}



#region FUNCTIONS
$Path = ".\Functions"
Get-ChildItem -Path $Path -Filter *.ps1 |Where-Object { $_.FullName -ne $PSCommandPath } |ForEach-Object {
    . $_.FullName
}
#endregion

#Requires -Modules FailoverClusters, Rubrik, SQLServer
Import-Module Rubrik -Force
Import-Module SQLServer
Import-Module FailoverClusters

Connect-Rubrik -Server $RubrikServer -Token $Credentials.APIToken.amer1
# $RubrikConnectionInfo = [pscustomobject]@{
#     Server = $global:rubrikConnection.server
#     Token =  $global:rubrikConnection.token
# }

foreach($Database in $Databases){
    #region Get information about the Source SQL Server and Database
    IF([string]::IsNullOrEmpty($SourceSQLInstance)){
        $GetRubrikDatabase = @{
            Name = $Database
            HostName = $SourceSQLHost 
            Instance = "MSSQLSERVER"
        }
    }else{
        $SourceSQLServerInstance = Get-SQLServerInstance -HostName $SourceSQLHost -InstanceName $SourceSQLInstance
        $GetWindowsCluster = @{
            ServerInstance = $SourceSQLServerInstance
            Instance = $SourceSQLInstance
        }
        $Cluster =  Get-WindowsClusterResource @GetWindowsCluster
        if ([bool]($Cluster.PSobject.Properties.name -match "Cluster") -eq $true){
            $GetRubrikDatabase = @{
                Name = $Database
                HostName = $Cluster.Cluster
                Instance = $SourceSQLInstance
            }
        }else{
            $GetRubrikDatabase = @{
                Name = $Database
                HostName = $SourceSQLHost 
                Instance = $SourceSQLInstance
            }
        }
    }
    $RubrikDatabase = Get-RubrikDatabase @GetRubrikDatabase 
    
    $DatabaseRecoveryPoint = Get-DatabaseRecoveryPoint -RubrikDatabase $RubrikDatabase -RestoreTime $RecoveryPoint
    $RubrikRequest = Restore-RubrikDatabase -Id $RubrikDatabase.id -RecoveryDateTime $DatabaseRecoveryPoint -FinishRecovery 
    $db = New-Object PSObject
    $db | Add-Member -type NoteProperty -name Name -Value $RubrikDatabase.name
    $db | Add-Member -type NoteProperty -name RubrikRequest -Value $RubrikRequest
    $DatabasesToBeRestored += $db
}

Write-Host "Waiting for all restores to finish"
foreach ($Database in $DatabasesToBeBackedUp)  {
    $RubrikRequestInfo = Get-RubrikRequestInfo -RubrikRequest $Database.RubrikRequest -Type mssql
    $Database.RubrikRequest = $RubrikRequestInfo
}