<#
    .SYNOPSIS
        Will export databases from instance of SQL registered in Rubrik to another instance registered in Rubrik

    .DESCRIPTION
        Will export databases from instance of SQL registered in Rubrik to another instance registered in Rubrik
        Will read a JSON file to get input and out information. For an example, use Export-RubrikDatabasesJobFile.json

        The Databases section of the JSON is an array that can be copied many times. 


    .PARAMETER JobFile
        JSON file that will provide values for the script to work 

    .INPUTS
        None

    .OUTPUTS
        None

    .EXAMPLE
        .\Export-RubrikDatabasesJob -JobFile .\Export-RubrikDatabasesJobFile.json

    .LINK
        None

    .NOTES
        Name:       Export Rubrik Databases Job 
        Created:    2/6/2018
        Author:     Chris Lumnah
        Execution Process:
            1. Before running this script, you need to create a credential file so that you can securely log into the Rubrik 
            Cluster. To do so run the below command via Powershell

            $Credential = Get-Credential
            $Credential | Export-CliXml -Path .\rubrik.Cred
            
            The above will ask for a user name and password and them store them in an encrypted xml file.
            
            2. Modify the JSON file to include the appropriate values. 
                RubrikCluster
                    Server:                     IP Address to the Rubrik Cluster
                    Credential:                 Should contain the full path and file name to the credential file created in step 1
                    Token:                      API Token that is generated inside Rubrik UI
                Databases - Repeatable array    The file is configured for one database to be exported. If you want to export more than one
                                                database, you must add additional elements. Copy from line 8-34. Put a comma after the curly 
                                                brace and then paste what was copied from line 8-34. Update the values in the new fields. 
                    Source:
                        AvailabilityGroupName:  Source location of the database. If in AG, this value is used to get backup from one of the members of the AG
                        ServerInstance:         Server Instance as used by a DBA. Named instances are HOST\INSTANCE, while default instances are HOST. 
                                                You may need to use the FQDN if that is what is listed in Rubrik
                        WindowsCluster:         The windows cluster the database may reside on.
                        Name:                   Database name to be exported    
                    Target:
                        ServerInstance:         Server Instance as used by a DBA. Named instances are HOST\INSTANCE, while default instances are HOST. 
                                                You may need to use the FQDN if that is what is listed in Rubrik
                        WindowsCluster:         The windows cluster the database may reside on. If you provide a value for a windows cluster
                                                make sure you also provide a value for ServerInstance. We will use this as a way drop the database
                                                from the target server if we encounter the bug in Rubrik 5.0
                        Name:                   Database name to be exported. If no value is provided, we use the Name under Source
                        RecoveryPoint:          A time  to which the database should be restored to. There are a few different possibilities
                            latest:             This will tell Rubrik to export the database to the latest recovery point Rubrik knows about
                                                This will include the last full and any logs to get to the latest recovery point
                            last full:          This will tell Rubrik to restore back to the last full backup it has
                            Format:             (HH:MM:SS.mmm) or (HH:MM:SS.mmmZ) - Restores the database back to the local or 
                                                UTC time (respectively) at the point in time specified within the last 24 hours
                            Format:             Any valid <value> that PS Get-Date supports in: "Get-Date -Date <Value>"
                                                Example: "2018-08-01T02:00:00.000Z" restores back to 2AM on August 1, 2018 UTC.
                        Files - Repeatable array
                            LogicalName:        Represents the logical name of a database file in SQL on the target SQL server.
                            Path:               Represents the physical path to a data or log file in SQL on the target SQL server.
                            FileName:           Physical file name of the data or log file in SQL on the target SQL server.

            3. If this script will not be run on the target SQL server or is run with network names for the target SQL 
               server, verify that TCP/IP enabled for the database. This can be done in SQL Server Configuration Manager. 
               Restarting the database service is required after making this change. 
               
            4. This script must be run as a user that has admin privileges on the SQL database. This is required because if a 
               database is existing on the target that needs to be overwritten this script must drop the database. 
               
            5. Execute this script via the example above. 

        Updated:    08/08/2018
        Updater:    Damani Norman
        Updates:    - Corrected spelling.
                    - Updated documentation.
                    - Added ability to restore databases to any point in time with in the last 24 hours.
                      Useful for refreshing databases to a specific point in time. 
                    - Added CmdletBinding for Verbose and Debug output.
                    - Removed CredentialFilePassword and Username from JSON files and code as they are no longer used.
                    - Added recover job tracking and status reporting.
        Updated:    05/03/2019
        Updater:    Chris Lumnah
        Updates:    - Allows for export to and from a cluster
                    - Allows for export to and from a stand alone SQL Instance
                    - Allows for export from an Avaialbility Group
                    - Allows for recovery point of last full backup
                    - Allows for API Token for authentication
                    - Moved the checking of a request in Rubrik to be checked based on a standard function
                    - Moved the removing of a database to a function
                    - Allow for the updated functionality of Overwrite on Export that came in Rubrik 5.0
                    - Has code to overcome the bug of Overwrite on Export that came in Rubrik 5.0
                    - Created a new function to get recovery point based on parameters
                    - Made changes to code to get better efficiencies
#>
[CmdletBinding()]

param(
    $JobFile = ".\Export-RubrikDatabasesJobFile.json"
)
Import-Module Rubrik
#region FUNCTIONS
function Remove-Database{
    param(
        [String]$DatabaseName,
        [String]$ServerInstance
    )
    
    $Query = "SELECT state_desc FROM sys.databases WHERE name = '" + $DatabaseName + "'" 
    $Results = Invoke-Sqlcmd -ServerInstance $ServerInstance -Query $Query

    if ([bool]($Results.PSobject.Properties.name -match "state_desc") -eq $true){
        if ($Results.state_desc -eq 'ONLINE'){
            Write-Host "Setting $($DatabaseName) to SINGLE_USER"
            Write-Host "Dropping $($DatabaseName)"
            $Query = "ALTER DATABASE [" + $DatabaseName + "] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; `nDROP DATABASE [" + $DatabaseName + "]"
            $Results = Invoke-Sqlcmd -ServerInstance $ServerInstance -Query $Query
        }
        else {
            Write-Host "Dropping $($DatabaseName)"
            $Query = "DROP DATABASE [" + $DatabaseName + "]"
            $Results = Invoke-Sqlcmd -ServerInstance $ServerInstance -Query $Query -Database master
        }
    }
}
function Get-RecoveryPoint{
    param(
        [PSObject]$RubrikDatabase,
        [String]$RestoreTime
    )
    switch -Wildcard ($RestoreTime){
        "latest" {
            $LastRecoveryPoint = (Get-RubrikDatabase -id $RubrikDatabase.ID).latestRecoveryPoint
            $RecoveryDateTime = Get-date -Date $LastRecoveryPoint
        }
        "last full" {
            $RubrikSnapshot = Get-RubrikSnapshot -id $RubrikDatabase.id | Sort-Object date -Descending | Select-object -First 1
            $RecoveryDateTime = $RubrikSnapshot.date
        }
        default {
            $RawRestoreDate = (get-date -Date $RestoreTime)
            Write-Verbose ("RawRestoreDate is: $RawRestoreDate")
            $Now = Get-Date
            if ($RawRestoreDate -ge $Now){$RecoveryDateTime = $RawRestoreDate.AddDays(-1)} 
            else{$RecoveryDateTime = $RawRestoreDate}
        }
    }
    return $RecoveryDateTime
}

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
#endregion

if (Test-Path -Path $JobFile) {
    $JobFile = (Get-Content $JobFile) -join "`n"  | ConvertFrom-Json

    #Currently there is no way to check for an existing connection to a Rubrik Cluster. This attempts to do that and only 
    #connects if an existing connection is not present. 
    Write-Host("Connecting to Rubrik cluster node $($JobFile.RubrikCluster.Server)...")
    switch($true){
        {$JobFile.RubrikCluster.Token}{
            $ConnectRubrik = @{
                Server = $JobFile.RubrikCluster.Server
                Token = $JobFile.RubrikCluster.Token
            }
        }
        {$Jobfile.RubrikCluster.Credential}{
            $ConnectRubrik = @{
                Server = $JobFile.RubrikCluster.Server
                Credential = Import-CliXml -Path $JobFIle.RubrikCluster.Credential
            }
        }
        default{
            $ConnectRubrik = @{
                Server = $JobFile.RubrikCluster.Server
            }
        }
    }

    Connect-Rubrik @ConnectRubrik #| Out-Null

    foreach ($Database in $JobFile.Databases) {
        switch($true){
            {$Database.Source.AvailabilityGroupName}{
                $GetRubrikDatabase = @{
                    HostName = $Database.Source.AvailabilityGroupName
                    Name = $Database.Source.Name
                }
            }
            {$Database.Source.ServerInstance}{
                $GetRubrikDatabase = @{
                    HostName = $Database.Source.ServerInstance
                    Name = $Database.Source.Name
                }
            }
            {$Database.Source.WindowsCluster}{
                $GetRubrikDatabase = @{
                    HostName = $Database.Source.WindowsCluster
                    Name = $Database.Source.Name
                }
            }
        }
        Write-Host "Getting information about $($GetRubrikDatabase.Name) on $($GetRubrikDatabase.HostName)"
        $RubrikDatabase = Get-RubrikDatabase @GetRubrikDatabase | Where-Object { $_.isRelic -eq $false -and $_.isLivemount -eq $false }

        #Added test to see if Get-RubrikDatabase found anything. Now, if database is not found in Rubrik, we will exit the script
        if ([bool]($RubrikDatabase.PSobject.Properties.name -match "name") -eq $false)
        {
            Write-Error "Database $($GetRubrikDatabase.Name) on $($GetRubrikDatabase.HostName) was not found"
            exit
        }
        
        #Create a hash table containing all of the files for the database. 
        $TargetFiles = @()
        foreach ($DatabaseFile in $Database.Target.Files)
        {
                $TargetFiles += @{logicalName=$DatabaseFile.logicalName;exportPath=$DatabaseFile.Path;newFilename=$DatabaseFile.FileName}       
        }

        switch($true){
            {$Database.Target.ServerInstance}{
                $GetRubrikDatabase = @{
                    HostName = $Database.Target.ServerInstance
                    Name = $Database.Target.Name
                }
            }
            {$Database.Target.WindowsCluster}{
                $GetRubrikDatabase = @{
                    HostName = $Database.Target.WindowsCluster
                    Name = $Database.Target.Name
                }
            }
        }

        #based on version, allow for overwrite, otherwise drop database and refresh. 
        #We look for the existence of the database on the target instance. If it exists, we must drop the database before we can 
        #proceed with exportation of the database to the target instance.

        $DatabaseName = $Database.Source.Name
        if ($Database.Target.Name){$DatabaseName = $Database.Target.Name}

        $RecoveryDateTime = Get-RecoveryPoint -RubrikDatabase $RubrikDatabase -RestoreTime $Database.Target.RecoveryPoint
        
        if ([bool]($RecoveryDateTime.PSobject.Properties.name -match "DateTime") -eq $false)
        {
            Write-Error "Rubrik is unable to find a valid recovery point for $($DatabaseName)"
            exit
        }
        
        switch ($true) {
            {$Database.Target.ServerInstance} {$GetRubrikSQLInstance = @{ServerInstance = $Database.Target.ServerInstance}}
            {$Database.Target.WindowsCluster} {$GetRubrikSQLInstance = @{ServerInstance = $Database.Target.WindowsCluster}}
            Default {}
        }
        
        $TargetInstance = (Get-RubrikSQLInstance @GetRubrikSQLInstance)
        if ([bool]($TargetInstance.PSobject.Properties.name -match "name") -eq $false)
        {
            Write-Error "Rubrik is unable to connect to the $($GetRubrikSQLInstance.ServerInstance)"
            exit
        }

        
        #Rubrik Version 5 introduces the ability to do a destructive overwrite. Previous versions do not have this ability and thus we need to drop the database before we can Export
        if ($global:rubrikConnection.version.Split(".")[0] -lt 5){
            Remove-Database -DatabaseName $DatabaseName -ServerInstance $Database.Target.ServerInstance

            #Refresh Rubik so it does not think the database still exists
            switch ($true) {
                {$Database.Target.ServerInstance} {$GetRubrikHost = @{Name = $Database.Target.ServerInstance}}
                {$Database.Target.WindowsCluster} {$GetRubrikHost = @{Name = $Database.Target.WindowsCluster}}
                Default {}
            }
            Write-Host "Refreshing $($Database.Target.ServerInstance) in Rubrik" 
            Get-RubrikHost @GetRubrikHost | Update-RubrikHost | Out-Null
            Write-Host "Restoring $($DatabaseName) to $($RecoveryDateTime) onto $($GetRubrikSQLInstance.ServerInstance)"
            $ExportRubrikDatabase = @{
                id = $RubrikDatabase.id
                TargetInstanceId = $TargetInstance.id
                TargetDatabaseName = $DatabaseName
                recoveryDateTime = $RecoveryDateTime
                FinishRecovery = $true
                TargetFilePaths = $TargetFiles
                Confirm = $false
            }
        }
        else {
            Write-Host "Restoring $($DatabaseName) to $($RecoveryDateTime) onto $($GetRubrikSQLInstance.ServerInstance)"
            $ExportRubrikDatabase = @{
                id = $RubrikDatabase.id
                TargetInstanceId = $TargetInstance.id
                TargetDatabaseName = $DatabaseName
                recoveryDateTime = $RecoveryDateTime
                FinishRecovery = $true
                TargetFilePaths = $TargetFiles
                Confirm = $false
                overwrite = $true
            }
        }
        
        $RubrikRequest = Export-RubrikDatabase @ExportRubrikDatabase 
        $RubrikRequestInfo = Get-RubrikRequestInfo -RubrikRequest $RubrikRequest -Type mssql
        #The below code only needs to be run if we hit a bug with earlier editions of Rubrik V5
        if ($RubrikRequestInfo.error -like "*file already exists*"){
            Write-Host "First attempt of restoring $($DatabaseName) to $($RecoveryDateTime) onto $($GetRubrikSQLInstance.ServerInstance) failed."
            Write-Host "Will try alternative method to restore database"
            Remove-Database -DatabaseName $DatabaseName -ServerInstance $Database.Target.ServerInstance
            #Refresh Rubik so it does not think the database still exists
            switch ($true) {
                {$Database.Target.ServerInstance} {$GetRubrikHost = @{Name = $Database.Target.ServerInstance}}
                {$Database.Target.WindowsCluster} {$GetRubrikHost = @{Name = $Database.Target.WindowsCluster}}
                Default {}
            }       
            Write-Host "Refreshing $($Database.Target.ServerInstance) in Rubrik" 
            Get-RubrikHost @GetRubrikHost | Update-RubrikHost | Out-Null
            Write-Host "Restoring $($DatabaseName) to $($RecoveryDateTime) onto $($GetRubrikSQLInstance.ServerInstance)"
            $RubrikRequest = Export-RubrikDatabase @ExportRubrikDatabase 
            $RubrikRequestInfo = Get-RubrikRequestInfo -RubrikRequest $RubrikRequest -Type mssql
        }
    }
}