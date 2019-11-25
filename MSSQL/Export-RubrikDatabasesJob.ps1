<#
.SYNOPSIS
    Script will read a JSON file that contains database information to restore a database from one instance to another. 
.DESCRIPTION
    Script will read a JSON file that contains database information to restore a database from one instance to another. 
    You can also provide your own JSON file as long as it has the information required to do a restore. 
.EXAMPLE
    PS C:\> .\Export-RubrikDatabaseJob.ps1 -JobFile .\JobFile.json
    
.NOTES
    Name:       Export Rubrik Databases Job 
    Created:    7/1/2019
    Author:     Chris Lumnah
    Execution Process:
        1. Before running this script, you need to create a credential file so that you can securely log into the Rubrik Cluster. To do so run the below command via Powershell

                $Credential = Get-Credential
                $Credential | Export-CliXml -Path .\rubrik.Cred

            The above will ask for a user name and password and them store them in an encrypted xml file.

        2. Modify the JSON file to include the appropriate values. 
            RubrikCluster
                Server:                     IP Address to the Rubrik Cluster
                Credential:                 Should contain the full path and file name to the credential file created in step 1
                Token:                      API Token that is generated inside Rubrik UI
                Databases - Repeatable array    The file is configured for one database to be exported. If you want to export more than one database, you must add additional elements. Copy from line 8-34. Put a comma after the curly 
                                                brace and then paste what was copied from line 8-34. Update the values in the new fields. 
                    Source:
                        DatabaseName:       Source Database Name
                        Instance:           Will either be blank if an Availability Group, MSSQLSERVER if a default instance, or the name of the instance
                        SQLHost:            Will either be the Availability Group name, the host name ot a stand alone instance, or the virtual network name if an FCI
                    Target:
                        DatabaseName:       Target Database Name
                        Instance:           Will either be blank if an Availability Group, MSSQLSERVER if a default instance, or the name of the instance
                        SQLHost:            Will either be the Availability Group name, the host name ot a stand alone instance, or the virtual network name if an FCI
                        RecoveryPoint:      A time  to which the database should be restored to. There are a few different possibilities
                            latest:         This will tell Rubrik to export the database to the latest recovery point Rubrik knows about
                                            This will include the last full and any logs to get to the latest recovery point
                            last full:      This will tell Rubrik to restore back to the last full backup it has
                            Format:         (HH:MM:SS.mmm) or (HH:MM:SS.mmmZ) - Restores the database back to the local or UTC time (respectively) at the point in time specified within the last 24 hours
                            Format:         Any valid <value> that PS Get-Date supports in: "Get-Date -Date <Value>"
                                            Example: "2018-08-01T02:00:00.000Z" restores back to 2AM on August 1, 2018 UTC.
                        Files - Repeatable array
                            logicalName:    Represents the logical name of a database file in SQL on the target SQL server.
                            exportPath:     Represents the physical path to a data or log file in SQL on the target SQL server.
                            newFilename:    Physical file name of the data or log file in SQL on the target SQL server.

        3. If this script will not be run on the target SQL server or is run with network names for the target SQL server, verify that TCP/IP enabled for the database. This can be done in SQL Server Configuration Manager. 
            Restarting the database service is required after making this change. 

        4. This script must be run as a user that has admin privileges on the SQL database. This is required because if a database is existing on the target that needs to be overwritten this script must drop the database. 

        5. Execute this script via the example above. 
#>
param(
    $JobFile = ".\JobFile.json"
)
Import-Module Rubrik -Force
#region FUNCTIONS
$Path = ".\Functions"
Get-ChildItem -Path $Path -Filter *.ps1 |Where-Object { $_.FullName -ne $PSCommandPath } |ForEach-Object {
    . $_.FullName
}

function Get-TargetFiles{
    param(
        [PSCustomObject]$Files
    )
    #Create a hash table containing all of the files for the database. 
    $TargetFiles = @()
    foreach ($File in $Files){
        $TargetFiles += @{logicalName=$File.logicalName;exportPath=$File.exportPath;newFilename=$File.newFilename}       
    }
    return $TargetFiles
}
#endregion

if (!(Test-Path -Path $JobFile)){exit}

$JobFile = (Get-Content $JobFile) -join "`n"  | ConvertFrom-Json

#Currently there is no way to check for an existing connection to a Rubrik Cluster. This attempts to do that and only 
#connects if an existing connection is not present. 
Write-Host("Connecting to Rubrik cluster node $($JobFile.RubrikCluster.Server)...")
switch($true){
    {$JobFile.RubrikCluster.Token}{
        $ConnectRubrik = @{
            Server  = $JobFile.RubrikCluster.Server
            Token   = $JobFile.RubrikCluster.Token
        }
    }
    {$Jobfile.RubrikCluster.Credential}{
        $ConnectRubrik = @{
            Server      = $JobFile.RubrikCluster.Server
            Credential  = Import-CliXml -Path $JobFIle.RubrikCluster.Credential
        }
    }
    default{
        $ConnectRubrik = @{
            Server = $JobFile.RubrikCluster.Server
            #Credential = $Credentials.RangerLab
        }
    }
}

Connect-Rubrik @ConnectRubrik #| Out-Null

foreach ($Database in $JobFile.Databases) {
    #region Get information about the Source SQL Server and Database
    $GetRubrikDatabase = @{
        id = $Database.Source.Databaseid
        instanceId = $Database.Source.instanceId
    }
    $RubrikDatabase = Get-RubrikDatabase @GetRubrikDatabase
    #endregion
    #region Get Recovery Point
    $RecoveryDateTime = Get-DatabaseRecoveryPoint -RubrikDatabase $RubrikDatabase -RestoreTime $Database.Target.RecoveryPoint
    if ([bool]($RecoveryDateTime.PSobject.Properties.name -match "DateTime") -eq $false){
        Write-Error "Rubrik is unable to find a valid recovery point for $($DatabaseName)"
        exit
    }
    #endregion

    if ( $Database.Source.Databaseid -and $Database.Source.instanceId -and $Database.Target.instanceId ){
        Write-Host "Prepared JSON"
        $TargetSQLServerInstance = Get-SQLServerInstance -HostName $Database.Target.SQLHost -InstanceName $Database.Target.Instance
        $TargetFiles = Get-TargetFiles -Files $Database.Target.Files
        $GetRubrikSQLInstance = @{
            HostName = $Database.Target.SQLHost
            Name  = $Database.Target.Instance
        }

        $ExportRubrikDatabase = @{
            id = $Database.Source.Databaseid
            TargetInstanceId = $Database.Target.instanceId
            TargetDatabaseName = $Database.Target.DatabaseName
            recoveryDateTime = $RecoveryDateTime
            FinishRecovery = $true
            TargetFilePaths = $TargetFiles
            Confirm = $false
            overwrite = $true
        }
    }else{
        #region Get information about the Source SQL Server and Database
        $SourceSQLServerInstance = Get-SQLServerInstance -HostName $Database.Source.SQLHost -InstanceName $Database.Source.Instance
        $GetWindowsCluster = @{
            ServerInstance = $SourceSQLServerInstance
            Instance = $Database.Source.Instance
        }
        $Cluster =  Get-WindowsClusterResource @GetWindowsCluster
        if ([bool]($Cluster.PSobject.Properties.name -match "Cluster") -eq $true){
            $GetRubrikDatabase = @{
                Name = $Database.Source.DatabaseName
                HostName = $Cluster.Cluster
                Instance = $Database.Source.Instance
            }
        }else{
            $GetRubrikDatabase = @{
                Name = $Database.Source.DatabaseName
                HostName = $Database.Source.SQLHost
                Instance = $Database.Source.Instance
            }
        }
        $RubrikDatabase = Get-RubrikDatabase @GetRubrikDatabase
        #$SourceRubrikSQLInstance = Get-RubrikSQLInstance -id $RubrikDatabase.instanceId 
        #endregion

        #region Get information about the Target SQL Server
        if ([bool]($RubrikDatabase.PSobject.Properties.name -match "instanceId") -eq $true){
            $TargetSQLServerInstance = Get-SQLServerInstance -HostName $Database.Target.SQLHost -InstanceName $Database.Target.Instance
            $GetWindowsCluster = @{
                ServerInstance = $TargetSQLServerInstance
                Instance = $Database.Target.Instance
            }

            $Cluster =  Get-WindowsClusterResource @GetWindowsCluster
            if ([bool]($Cluster.PSobject.Properties.name -match "Cluster") -eq $true){
                $GetRubrikSQLInstance = @{
                    HostName = $Cluster.Cluster
                    Name  = $Database.Target.Instance
                }
            } else {
                $GetRubrikSQLInstance = @{
                    HostName = $Database.Target.SQLHost
                    Name  = $Database.Target.Instance
                }
            }
            $TargetRubrikSQLInstance = Get-RubrikSQLInstance @GetRubrikSQLInstance
            if ([bool]($TargetRubrikSQLInstance.PSobject.Properties.name -match "name") -eq $false){
                Write-Error "Rubrik is unable to connect to the $($GetRubrikSQLInstance.HostName)\$($GetRubrikSQLInstance.Name)"
                exit
            }
            #endregion
        }
        #region Get information about the database files
        $TargetFiles = @()
        foreach ($DatabaseFile in $Database.Target.Files){
                $TargetFiles += @{logicalName=$DatabaseFile.logicalName;exportPath=$DatabaseFile.exportPath;newFilename=$DatabaseFile.newFilename}       
        }
        #endregion
        $DatabaseName = $Database.Source.DatabaseName
        if ($Database.Target.Name){$DatabaseName = $Database.Target.DatabaseName}

        #Rubrik Version 5 introduces the ability to do a destructive overwrite. Previous versions do not have this ability and thus we need to drop the database before we can Export
        if ($global:rubrikConnection.version.Split(".")[0] -lt 5){
            Remove-Database -DatabaseName $DatabaseName -ServerInstance $TargetSQLServerInstance 
            #Refresh Rubik so it does not think the database still exists
            $GetRubrikHost = @{
                Name = $GetRubrikSQLInstance.HostName
            }
            Write-Host "Refreshing $($Database.Target.ServerInstance) in Rubrik" 
            Get-RubrikHost @GetRubrikHost | Update-RubrikHost | Out-Null
        }
        
        $ExportRubrikDatabase = @{
            id = $RubrikDatabase.id
            TargetInstanceId = $TargetRubrikSQLInstance.id
            TargetDatabaseName = $DatabaseName
            recoveryDateTime = $RecoveryDateTime
            FinishRecovery = $true
            TargetFilePaths = $TargetFiles
            Confirm = $false
            Overwrite = $true
        }
    }
    Write-Host "Restoring $($ExportRubrikDatabase.TargetDatabaseName) to $($ExportRubrikDatabase.recoveryDateTime) onto $($GetRubrikSQLInstance.HostName)\$($GetRubrikSQLInstance.Name)"
    $RubrikRequest = Export-RubrikDatabase @ExportRubrikDatabase -Verbose
    $RubrikRequestInfo = Get-RubrikRequestInfo -RubrikRequest $RubrikRequest -Type mssql
    $RubrikRequestInfo.error
    #The below code only needs to be run if we hit a bug with earlier editions of Rubrik V5
    if ($RubrikRequestInfo.error -like "*Cannot create a file when that file already exists*" -or $RubrikRequestInfo.error -like "*does not have enough space*"){
        Write-Host "First attempt of restoring $($ExportRubrikDatabase.TargetDatabaseName) to $($ExportRubrikDatabase.recoveryDateTime) onto $($GetRubrikSQLInstance.HostName)\$($GetRubrikSQLInstance.Name) failed."
        Write-Host "Will try alternative method to restore database"
        Remove-Database -DatabaseName $($ExportRubrikDatabase.TargetDatabaseName) -ServerInstance $TargetSQLServerInstance 
        #Refresh Rubik so it does not think the database still exists
        $GetRubrikHost = @{
            Name = $GetRubrikSQLInstance.HostName
        }
        Write-Host "Refreshing  $($GetRubrikSQLInstance.HostName) in Rubrik" 
        Get-RubrikHost @GetRubrikHost | Update-RubrikHost | Out-Null
        Write-Host "Restoring $($ExportRubrikDatabase.TargetDatabaseName) to $($ExportRubrikDatabase.recoveryDateTime) onto $($GetRubrikSQLInstance.HostName)\$($GetRubrikSQLInstance.Name)"
        $RubrikRequest = Export-RubrikDatabase @ExportRubrikDatabase -Verbose
        $RubrikRequestInfo = Get-RubrikRequestInfo -RubrikRequest $RubrikRequest -Type mssql
    }
}
   