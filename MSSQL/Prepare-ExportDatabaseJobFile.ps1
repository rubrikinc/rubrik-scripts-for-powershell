<#
.SYNOPSIS
    Script will prepare the JSON jobfile that will be used in the Export-RubrikDatabaseJob.ps1 script
.DESCRIPTION
    Script will prepare the JSON jobfile that will be used in the Export-RubrikDatabaseJob.ps1 script
.EXAMPLE
    PS C:\> .\Prepare-ExportDatabaseJobFile.ps1 -RubrikServer amer1-rbk01 `
    -SourceServerInstance SQL1 `
    -Databases AdventureWorks2016 `
    -RecoveryPoint latest `
    -TargetServerInstance SQL2
    
    Will Export the latest backup of AdventureWorks2016 from the SQL1 server instance to the SQL2 server instance
.EXAMPLE
    PS C:\> .\Prepare-ExportDatabaseJobFile.ps1 -RubrikServer amer1-rbk01 `
    -AvailabilityGroupName AG1 `
    -Databases AdventureWorks2016 `
    -RecoveryPoint latest `
    -TargetServerInstance SQL2

    Will Export the latest backup of AdventureWorks2016 from the Availability Group AG1 to the SQL2 Instance
.PARAMETER RubrikServer
    Rubrik Server should be the IP Address or your Rubrik Server Name. This will be the same value you use to access the Rubrik UI
.PARAMETER SourceServerInstance
    Source SQL Server
.PARAMETER AvailabilityGroupName
    Source Availability Group Name
.PARAMETER Databases
    Provide a comma separated list of databases found on the source SQL Server and Instance
.PARAMETER RecoveryPoint
    A time  to which the database should be restored to. There are a few different possibilities
        latest:             This will tell Rubrik to export the database to the latest recovery point Rubrik knows about
                            This will include the last full and any logs to get to the latest recovery point
        lastfull:           This will tell Rubrik to restore back to the last full backup it has
        Format:             (HH:MM:SS.mmm) or (HH:MM:SS.mmmZ) - Restores the database back to the local or 
                            UTC time (respectively) at the point in time specified within the last 24 hours
        Format:             Any valid <value> that PS Get-Date supports in: "Get-Date -Date <Value>"
                            Example: "2018-08-01T02:00:00.000Z" restores back to 2AM on August 1, 2018 UTC.
.PARAMETER TargetServerInstance
    Target SQL Server Instance
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
    Updated:    6/5/2020 by Chris Lumnah
        Converted *SQLHost and *SQLInstance to *SQLServerInstance
        Added Availability Group Parameter as a source 
        Added FinishRecovery as a hardcoded value of $true to the output JSON file. At the moment, this is hardcoded based on use cases
        There is not a lot of cases where you would not want to finish the recovery of a database. If there is a use case where you need to 
        not finish the recovery process (i.e. Keeping CDC or Replication) this can be changed to $false. By doing so, the DBA can run additional
        scripts after Rubrik has finished transfering the data. The DBA can then run RESTORE DATABASE [DBNAME] WITH KEEP_CDC/KEEP_REPLICATION


#>
[cmdletbinding()]
param(
    [Parameter(Position=0)]
    [String]$RubrikServer,
    [Parameter(ParameterSetName='ServerInstance', Position=1)]
    [String]$SourceServerInstance,
    [Parameter(ParameterSetName='AvailabilityGroup', Position=1)]
    [String]$AvailabilityGroupName,
    [Parameter(Position=3)]
    [String[]]$Databases,
    [Parameter(Position=4)]
    [string]$RecoveryPoint,
    [Parameter(Position=5)]
    [String]$TargetServerInstance,
    [Parameter(Position=6)]
    [String]$TargetDataPath,
    [Parameter(Position=7)]
    [String]$TargetLogPath,
    [Parameter(Position=8)]
    [String]$OutFile = ".\JobFile.json"
)

#region FUNCTIONS
$Path = ".\Functions"
Get-ChildItem -Path $Path -Filter *.ps1 |Where-Object { $_.FullName -ne $PSCommandPath } |ForEach-Object {
    . $_.FullName
}
#endregion
#Requires -Modules Rubrik, SQLServer, FailoverClusters
Import-Module Rubrik 
Import-Module SQLServer
Import-Module FailoverClusters

Connect-Rubrik -Server $RubrikServer #-Token $token
$RubrikConnectionInfo = [pscustomobject]@{
    Server = $global:rubrikConnection.server
    Token =  $global:rubrikConnection.token
}

$DatabaseInfo = @()
foreach($Database in $Databases){
    #region Get information about the Source SQL Server and Database
    switch ($PSBoundParameters.Keys) {
        'SourceServerInstance' {
            Write-Host "Get information about $($Database) on $($SourceServerInstance)"
            $SourceInstance = $SourceServerInstance.split("\")[1]
            If([string]::IsNullOrEmpty($SourceInstance)){$SourceInstance = "MSSQLSERVER"}
  
            $GetWindowsCluster = @{
                ServerInstance = $SourceServerInstance
                Instance = $SourceInstance
            }
            $Cluster =  Get-WindowsClusterResource @GetWindowsCluster
          
            if ([bool]($Cluster.PSobject.Properties.name -match "Cluster") -eq $true){
                $GetRubrikDatabase = @{
                    Name = $Database
                    HostName = $Cluster.Cluster
                    Instance = $SourceInstance
                }
            }else{
                $GetRubrikDatabase = @{
                    Name = $Database
                    ServerInstance = $SourceServerInstance
                }
            }
        }
        'AvailabilityGroupName' {
            Write-Host "Get information about $($Database) on $($AvailabilityGroupName)"
            $GetRubrikDatabase = @{
                Name = $Database
                AvailabilityGroupName = $AvailabilityGroupName
            }
        }
        'Default' {}
    }
    
    $RubrikDatabase = Get-RubrikDatabase @GetRubrikDatabase | Where-Object {$_.isRelic -eq $false} 
    #endregion
    if ([bool]($RubrikDatabase.PSobject.Properties.name -match "instanceId" -or [bool]($RubrikDatabase.PSobject.Properties.name -match "availabilityGroupId") -eq $true)){
        if ([bool]($RubrikDatabase.PSobject.Properties.name -match "instanceId") -eq $true){$SourceRubrikSQLInstance = $RubrikDatabase.instanceId}
        if ([bool]($RubrikDatabase.PSobject.Properties.name -match "availabilityGroupId") -eq $true){$SourceRubrikSQLInstance = $RubrikDatabase.availabilityGroupId}

        #region Get information about the Target SQL Server
        Write-Host "Get information about $($TargetServerInstance)"
        $TargetInstance = $TargetServerInstance.split("\")[1]
        If([string]::IsNullOrEmpty($TargetInstance)){$TargetInstance = "MSSQLSERVER"}
            
        $GetWindowsCluster = @{
            ServerInstance = $TargetServerInstance
            Instance = $TargetInstance
        }

        $Cluster =  Get-WindowsClusterResource @GetWindowsCluster
        if ([bool]($Cluster.PSobject.Properties.name -match "Cluster") -eq $true){
            $GetRubrikSQLInstance = @{
                HostName = $Cluster.Cluster
                Name  = $TargetSQLInstance
            }
        } else {
            $GetRubrikSQLInstance = @{
            ServerInstance = $TargetServerInstance
            }
        }
        $TargetRubrikSQLInstance = Get-RubrikSQLInstance @GetRubrikSQLInstance
        #endregion
        #region Get information about the database files
        if ([string]::IsNullOrEmpty($TargetDataPath) -or [string]::IsNullOrEmpty($TargetLogPath)){
            $DatabaseDefaultLocations = Get-SQLDatabaseDefaultLocations -Server $TargetServerInstance
            $TargetDataPath = $DatabaseDefaultLocations.Data
            $TargetLogPath = $DatabaseDefaultLocations.Log
        }
        
        $TargetFiles = @()
        switch ($RecoveryPoint) {
            "Latest" {
                $GetRubrikDatabaseRecoveryPoint = @{
                    id = $RubrikDatabase.id
                    Latest = $true
                }
            }
            "LastFull" {
                $GetRubrikDatabaseRecoveryPoint = @{
                    id = $RubrikDatabase.id
                    LastFull = $true
                }
            }
            Default {
                $GetRubrikDatabaseRecoveryPoint = @{
                    id = $RubrikDatabase.id
                    RestoreTime = $RecoveryPoint
                }
            }
        }
        $DatabaseRecoveryPoint = Get-RubrikDatabaseRecoveryPoint @GetRubrikDatabaseRecoveryPoint
        
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
    }else{
        Write-Host "Database Not Found"
    }
    # endregion
    $DatabaseInfo += [pscustomobject]@{
        Source = [ordered]@{
            DatabaseName    = $RubrikDatabase.name
            Databaseid      = $RubrikDatabase.id
            ServerInstance  = $SourceServerInstance
            AvailabilityGroupName = $AvailabilityGroupName
            instanceId      = $SourceRubrikSQLInstance
        }
        Target = [ordered]@{
            DatabaseName    = $RubrikDatabase.name
            ServerInstance  = $TargetServerInstance
            instanceId      = $TargetRubrikSQLInstance.id
            RecoveryPoint   = $DatabaseRecoveryPoint
            Files           = $TargetFiles
            FinishRecovery  = $true
        }
    }
}

$json = [pscustomobject]@{
    RubrikCluster = $RubrikConnectionInfo
    Databases = $DatabaseInfo
}

$json | ConvertTo-Json -Depth 6 | Out-File -FilePath $OutFile