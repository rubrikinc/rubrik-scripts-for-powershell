<#
.SYNOPSIS
    Script will prepare the JSON jobfile that will be used in the Export-RubrikDatabaseJob.ps1 script
.DESCRIPTION
    Script will prepare the JSON jobfile that will be used in the Export-RubrikDatabaseJob.ps1 script
.EXAMPLE
    PS C:\> .\Prepare-ExportDatabaseJobFile.ps1 -SourceSQLHost sql1 -Database AdventureWorks2016 -RecoveryPoint Latest -TargetSQLHost sql2
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
.PARAMETER TargetSQLHost
    Target SQL Host is the name of the SQL Server Host. 
    If an SQL FCI, then this will be the Virtual Name given to SQL Server
.PARAMETER TargetSQLInstance
    This is the name of the SQL Server Instance. 
    If referrencing a Default instance, then this should be MSSQLSERVER
    If referrencing a Named instance, then this should be the instance name
    This is defaulted to MSSQLSERVER if no value is provided. 
.PARAMETER TargetDataPath
    Location of where the data files should reside on the target SQL Server. If no value is provided, then we will take the 
    Default Data Path from the Target SQL Server 
.PARAMETER TargetLogPath
    Location of where the log files should reside on the target SQL Server. If no value is provided, then we will take the 
    Default Log Path from the Target SQL Server 
.PARAMETER OutFile
    Defaults to .\JobFile.json
    This writes a file to the current directory called JobFile.json

.OUTPUTS
    Output (if any)
.NOTES
    Name:       Prepare JSON Job File for Export-RubrikDatabasesJob.ps1
    Created:    6/27/2019
    Author:     Chris Lumnah
    Execution Process:
        1. Before running this script, you need to create a credential file so that you can securely log into the Rubrik 
        Cluster. To do so run the below command via Powershell

            $Credential = Get-Credential
            $Credential | Export-CliXml -Path .\rubrik.Cred
            
        The above will ask for a user name and password and them store them in an encrypted xml file.
        
        2. If this script will not be run on the target SQL server or is run with network names for the target SQL 
            server, verify that TCP/IP enabled for the database. This can be done in SQL Server Configuration Manager. 
            Restarting the database service is required after making this change. 
            
        3. This script must be run as a user that has admin privileges on the SQL database. This is required because if a 
            database is existing on the target that needs to be overwritten this script must drop the database. 
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
    [string]$RecoveryPoint,
    [Parameter(Position=5)]
    [String]$TargetSQLHost,
    [Parameter(Position=6)]
    [String]$TargetSQLInstance = 'MSSQLSERVER',
    [Parameter(Position=7)]
    [String]$TargetDataPath,
    [Parameter(Position=8)]
    [String]$TargetLogPath,
    [Parameter(Position=9)]
    [String]$OutFile = ".\JobFile.json"
)

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

Connect-Rubrik -Server $RubrikServer #-Credential $Credentials.Gaia | Out-Null
$RubrikConnectionInfo = [pscustomobject]@{
    Server = $global:rubrikConnection.server
    Token =  $global:rubrikConnection.token
}

$DatabaseInfo = @()
foreach($Database in $Databases){
    #region Get information about the Source SQL Server and Database
    IF([string]::IsNullOrEmpty($SourceSQLInstance)){
        $GetRubrikDatabase = @{
            Name = $Database
            HostName = $SourceSQLHost 
            Instance = 'MSSQLSERVER'
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
    
    $RubrikDatabase = Get-RubrikDatabase @GetRubrikDatabase | Where-Object {$_.isRelic -eq $false} 
    #| Select-object -First 1
    
    #endregion
    #region Get information about the Target SQL Server
    if ([bool]($RubrikDatabase.PSobject.Properties.name -match "instanceId" -or [bool]($RubrikDatabase.PSobject.Properties.name -match "availabilityGroupId") -eq $true)){
        if ([bool]($RubrikDatabase.PSobject.Properties.name -match "instanceId") -eq $true){$SourceRubrikSQLInstance = Get-RubrikSQLInstance -id $RubrikDatabase.instanceId}
        if ([bool]($RubrikDatabase.PSobject.Properties.name -match "availabilityGroupId") -eq $true){$SourceRubrikSQLInstance = Get-RubrikAvailabilityGroup -id $RubrikDatabase.availabilityGroupId}
        
        $TargetSQLServerInstance = Get-SQLServerInstance -HostName $TargetSQLHost -InstanceName $TargetSQLInstance

        $GetWindowsCluster = @{
            ServerInstance = $TargetSQLServerInstance
            Instance = $TargetSQLInstance
        }

        $Cluster =  Get-WindowsClusterResource @GetWindowsCluster
        if ([bool]($Cluster.PSobject.Properties.name -match "Cluster") -eq $true){
            $GetRubrikSQLInstance = @{
                HostName = $Cluster.Cluster
                Name  = $TargetSQLInstance
            }
        } else {
            $GetRubrikSQLInstance = @{
                HostName = $TargetSQLHost 
                Name  = $TargetSQLInstance
            }
        }
        $TargetRubrikSQLInstance = Get-RubrikSQLInstance @GetRubrikSQLInstance
        #endregion
        #region Get information about the database files
        if ([string]::IsNullOrEmpty($TargetDataPath) -or [string]::IsNullOrEmpty($TargetLogPath)){
            $DatabaseDefaultLocations = Get-SQLDatabaseDefaultLocations -Server $TargetSQLServerInstance
            $TargetDataPath = $DatabaseDefaultLocations.Data
            $TargetLogPath = $DatabaseDefaultLocations.Log
        }
    
        $TargetFiles = @()
        $DatabaseRecoveryPoint = Get-DatabaseRecoveryPoint -RubrikDatabase $RubrikDatabase -RestoreTime $RecoveryPoint
        $RubrikDatabaseFiles = Get-RubrikDatabaseFiles -Id $RubrikDatabase.id -RecoveryDateTime $DatabaseRecoveryPoint

        foreach ($RubrikDatabaseFile in $RubrikDatabaseFiles){
            if ($RubrikDatabaseFile.fileType -eq "Log"){
                $TargetFiles += [pscustomobject]@{
                    logicalName = $RubrikDatabaseFile.logicalName
                    exportPath = $TargetLogPath
                    newFilename = $RubrikDatabaseFile.originalName
                }       
            }else{
                $TargetFiles += [pscustomobject]@{
                    logicalName = $RubrikDatabaseFile.logicalName
                    exportPath = $TargetDataPath
                    newFilename=$RubrikDatabaseFile.originalName
                }       
            }
        }
        #endregion
        $DatabaseInfo += [pscustomobject]@{
            Source = [ordered]@{
                Databaseid      = $RubrikDatabase.id
                DatabaseName    = $RubrikDatabase.name
                Instance        = $SourceSQLInstance
                instanceId      = $SourceRubrikSQLInstance.id
                SQLHost         = $SourceSQLHost
            }
            Target = [ordered]@{
                DatabaseName    = $RubrikDatabase.name
                Instance        = $TargetSQLInstance
                instanceId      = $TargetRubrikSQLInstance.id
                SQLHost         = $TargetSQLHost
                RecoveryPoint   = $DatabaseRecoveryPoint.GetDateTimeFormats()[102]
                Files           = $TargetFiles
            }
        }
    }
}

$json = [pscustomobject]@{
    RubrikCluster = $RubrikConnectionInfo
    Databases = $DatabaseInfo
}

$json | ConvertTo-Json -Depth 6 | Out-File -FilePath $OutFile