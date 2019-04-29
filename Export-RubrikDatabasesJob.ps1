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
                    Server: IP Address to the Rubrik Cluster
                    Credential: Should contain the full path and file name to the credential file created in step 1

                Databases - Repeatable array
                    Name: Database name to be exported    
                    SourceIsAG: Boolean value. If true, SourceHostName should have an availability group name filled in. If False, then it should be either 
                                the Windows Cluster Name, or the standalone host name
                    SourceHostName: Source SQL Server. Value will change based on SourceIsAG being true or false
                    SourceInstance: Source SQL Server Instance name. Will either be MSSQLSERVER or the named instance value
                    TargetHostName: Target SQL Server. Value will change based on SourceIsAG being true or false
                    TargetInstance: Target SQL Server Instance name. Will either be MSSQLSERVER or the named instance value
                    TargetDatabaseName: Will be the name of the database once restored to the target sql server
                    RestoreTime: A time  to which the database should be restored to. 
                                 Format: (HH:MM:SS.mmm) or (HH:MM:SS.mmmZ) - Restores the database back to the local or 
                                         UTC time (respectively) at the point in time specified within the last 24 hours
                                 Format: Any valid <value> that PS Get-Date supports in: "Get-Date -Date <Value>"
                                         Example: "2018-08-01T02:00:00.000Z" restores back to 2AM on August 1, 2018 UTC.
                    Files - Repeatable array
                        LogicalName: Represents the logical name of a database file in SQL on the target SQL server.
                        Path: Represents the physical path to a data or log file in SQL on the target SQL server.
                        FileName: Physical file name of the data or log file in SQL on the target SQL server.

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


#>
[CmdletBinding()]

param(
    $JobFile = ".\Export-RubrikDatabasesJobFile.json"
)

$Now = get-date
$Exports = @{}

Import-Module Rubrik

if (Test-Path -Path $JobFile) {
    $JobFile = (Get-Content $JobFile) -join "`n"  | ConvertFrom-Json

    #Currently there is no way to check for an existing connection to a Rubrik Cluster. This attempts to do that and only 
    #connects if an existing connection is not present. 
    Write-Host("Connecting to Rubrik cluster node $($JobFile.RubrikCluster.Server)...")
    try 
    {
        Get-RubrikVersion | Out-Null
    }
    catch 
    {
        #04/05/2018 - Chris Lumnah - Instead of using an encrypted text file, I am now using the more standard
        #CLiXml method
        $Credential = Import-CliXml -Path $JobFIle.RubrikCluster.Credential
        Connect-Rubrik -Server $JobFile.RubrikCluster.Server -Credential $Credential
    }

    foreach ($Database in $JobFile.Databases) {
        if ($Database.SourceIsAG -eq $true) 
        {
            $RubrikDatabase = Get-RubrikDatabase -Name $Database.Name -Hostname $Database.SourceHostName 
        }
        else 
        {    
            $RubrikDatabase = Get-RubrikDatabase -Name $Database.Name -Hostname $Database.SourceHostName -Instance $Database.SourceInstance
        }
      
        #Added test to see if Get-RubrikDatabase found anything. Now, if database is not found in Rubrik, we will exit the script
        if ([bool]($RubrikDatabase.PSobject.Properties.name -match "name") -eq $false)
        {
            Write-Error "Database $($Database.Name) on $($Database.SourceHostName)\$($Database.SourceInstance) was not found"
            exit
        }
        
        #Create a hash table containing all of the files for the database. 
        $TargetFiles = @()
        foreach ($DatabaseFile in $JobFile.Databases.Files)
        {
                $TargetFiles += @{logicalName=$DatabaseFile.logicalName;exportPath=$DatabaseFile.Path;newFilename=$DatabaseFile.FileName}       
        }

        $TargetServerInstance = $Database.TargetHostName
        if ($Database.TargetInstance -ne "MSSQLSERVER")
        {
            $TargetServerInstance = "$($Database.TargetHostName)\$($Database.TargetInstance)"
        }

        #We look for the existence of the database on the target instance. If it exists, we must drop the database before we can 
        #proceed with exportation of the database to the target instance.

        $DatabaseName = $Database.Name
        if ($Database.TargetDatabaseName){$DatabaseName = $Database.TargetDatabaseName}

        $Query = "SELECT state_desc FROM sys.databases WHERE name = '" + $DatabaseName + "'" 
        $Results = Invoke-Sqlcmd -ServerInstance $TargetServerInstance -Query $Query

        if ([bool]($Results.PSobject.Properties.name -match "state_desc") -eq $true)
        {
            IF ($Results.state_desc -eq 'ONLINE')
            {
                Write-Host "Setting $($DatabaseName) to SINGLE_USER"
                Write-Host "Dropping $($DatabaseName)"
                $Query = "ALTER DATABASE [" + $DatabaseName + "] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; `nDROP DATABASE [" + $DatabaseName + "]"
                $Results = Invoke-Sqlcmd -ServerInstance $TargetServerInstance -Query $Query
            }
            else 
            {
                Write-Host "Dropping $($DatabaseName)"
                $Query = "DROP DATABASE [" + $DatabaseName + "]"
                $Results = Invoke-Sqlcmd -ServerInstance $TargetServerInstance -Query $Query -Database master
            }
        }
        
        #Refresh Rubik so it does not think the database still exists
        Write-Host "Refreshing $($Database.TargetHostName) in Rubrik"
        New-RubrikHost -Name $Database.TargetHostName -Confirm:$false | Out-Null
        
        $TargetInstance = (Get-RubrikSQLInstance -Hostname $Database.TargetHostName -Instance $Database.TargetInstance)
        $LastRecoveryPoint = (Get-RubrikDatabase -id $RubrikDatabase.ID).latestRecoveryPoint

        Write-Verbose ("Latest snapshot time is: $LastRecoveryPoint")

        if ( $Database.RestoreTime -match "latest" ) 
        {
            $RestoreTime = Get-date -Date $LastRecoveryPoint
        } 
        else 
        {
            $RawRestoreDate = (get-date -Date $Database.RestoreTime)
            Write-Verbose ("RawRestoreDate is: $RawRestoreDate")

            if ($RawRestoreDate -ge $Now) 
            {
                $RestoreTime = $RawRestoreDate.AddDays(-1)
            } 
            else 
            {
                $RestoreTime = $RawRestoreDate 
            }
        }

        Write-Verbose ("RestoreTime is: $RestoreTime")
        Write-Host ("Starting restore of database " + $DatabaseName + " to restore point: $RestoreTime...")
        $Result = ""
        try 
        {
            $Result = Export-RubrikDatabase -Id $RubrikDatabase.id `
                -TargetInstanceId $TargetInstance.id `
                -TargetDatabaseName $DatabaseName `
                -recoveryDateTime $RestoreTime `
                -FinishRecovery `
                -TargetFilePaths $TargetFiles `
                -Confirm:$false
        } 
        catch 
        {
            $formatstring = "{0} : {1}`n{2}`n" +
                "    + CategoryInfo          : {3}`n" +
                "    + FullyQualifiedErrorId : {4}`n"
        
            $fields = $_.InvocationInfo.MyCommand.Name,
                    $_.ErrorDetails.Message,
                    $_.InvocationInfo.PositionMessage,
                    $_.CategoryInfo.ToString(),
                    $_.FullyQualifiedErrorId
            Write-Error ("Starting restore request for $($DatabaseName) failed.")
            Write-Error ($formatstring -f $fields)
        }
        Write-Verbose ("Result is: $Result")
        Write-Verbose ("Exports.add($($DatabaseName), $($Result.id))")
        
        if ( -Not [string]::IsNullOrEmpty($Result.id)) {$Exports.add($DatabaseName, $Result.id)}
    }
    Write-Verbose ("Exports is:")
    foreach($k in $Exports.Keys){Write-Verbose "$k is $($Exports[$k])"}

    foreach ($Export in $Exports.keys) {
        Write-Verbose ("Export is: $Export")
        $ExportStatus = ""
        while ($ExportStatus.status -notin "SUCCEEDED", "FAILED", "FINISHING") {
            $ExportStatus = Get-RubrikRequest -id $Exports.$Export -Type mssql
            Write-Verbose ("ExportStatus is: $ExportStatus")
            Write-Host ("SQL Restore job for database " + $Export + " is " + $ExportStatus.status + ", progress: " + $ExportStatus.progress )
            #Start-Sleep 5
        }
        if ($ExportStatus.status -in "SUCCEEDED", "FINISHING") {
            Write-Host ("SQL Restore of $Export " + $ExportStatus.status)
        } else {
            Write-Error ("SQL Restore of $Export " + $ExportStatus.status)
            Write-Error ("Error message was: " + $ExportStatus.error)
        }
    }
} 


<# 
In case the JSON file is deleted, you can use the below as an example to recreate the file. 

{
    "RubrikCluster":
    {
        "Server": "172.21.8.31",
        "Credential":"C:\\Users\\chrislumnah\\OneDrive\\Documents\\WindowsPowerShell\\Credentials\\RangerLab-AD.credential"

    },
    "Databases":
    [ 
        {
            "Name": "AdventureWorks2016",
            "RestoreTime": "latest",
            "SourceServerInstance": "cl-sql2016n1.rangers.lab",
            "TargetServerInstance": "cl-sql2016n2.rangers.lab",
            "Files":
            [
                {
                    "LogicalName":"AdventureWorks2016_Data",
                    "Path":"E:\\Microsoft SQL Server\\MSSQL13.MSSQLSERVER\\MSSQL\\DATA\\",
                    "FileName":"AdventureWorks2016_Data.mdf"
                },
                {
                    "LogicalName":"AdventureWorks2016_Log",
                    "Path":"E:\\Microsoft SQL Server\\MSSQL13.MSSQLSERVER\\MSSQL\\DATA\\",
                    "FileName":"AdventureWorks2016_Log.ldf"
                }
            ]
        },
        {
            "Name": "AdventureWorksDW2016",
            "RestoreTime": "02:00",
            "SourceServerInstance": "cl-sql2016n1.rangers.lab",
            "TargetServerInstance": "cl-sql2016n2.rangers.lab",
            "Files":
            [
                {
                    "LogicalName":"AdventureWorksDW2016_Data",
                    "Path":"E:\\Microsoft SQL Server\\MSSQL13.MSSQLSERVER\\MSSQL\\DATA\\",
                    "FileName":"AdventureWorksDW2016_Data.mdf"
                },
                {
                    "LogicalName":"AdventureWorksDW2016_Log",
                    "Path":"E:\\Microsoft SQL Server\\MSSQL13.MSSQLSERVER\\MSSQL\\DATA\\",
                    "FileName":"AdventureWorksDW2016_Log.ldf"
                }
            ]
        }
    ]  
}
#>