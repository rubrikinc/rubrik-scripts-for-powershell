<#
    .SYNOPSIS
        Will export databases from instance of SQL registered in Rubrik to another instance registered in Rubrik

    .DESCRIPTION
        Will export databases from instance of SQL registered in Rubrik to another instance registered in Rubrik
        Will read a JSON file to get input and out information. For an example, use Export-RubrikDatabasesJobFile.json

        The Databaess section of the JSON is an array that can be copied many times. 


    .PARAMETER JobFile
        JSON file that will provide values for the script to work 

    .INPUTS
        None

    .OUTPUTS
        None

    .EXAMPLE
        .\Export-RubrikDatabaessJob -JobFile .\Export-RubrikDatabasesJobFile.json

    .LINK
        None

    .NOTES
        Name:       Export Rubrik Databases Job 
        Created:    2/6/2018
        Author:     Chris Lumnah
        Execution Process:
            1. Before running this script, you need to create a credential file so that you can securly log into the Rubrik 
            Cluster. To do so run the below command via Powershell

            $Credential = Get-Credential
            $Credential | Export-CliXml -Path .\rubrik.Cred"
            
            The above will ask for a user name and password and them store them in an encrypted xml file.
            
            2. Modify the JSON file to include the appropriate values. 
                RubrikCluster
                    Server: IP Address to the Rubrk Cluster
                    Credential: Should contain the full path and file name to the credential file created in step 1
                    s
                Databases - Repeatable array
                    Name: Database name to be exported
                    SourceServerInstance: Source SQL Server Instance
                    TargetServerInstance: Target SQL Server Instance
                    Files - Repeatable array
                        LogicalName: Represents the logical name of a database file in SQL
                        Path: Represents the physical path to a data or log file in SQL
                        FileName: Physical file name of the data or log file in SQL
            3. Execute this script via the example above. 



#>
param(
    $JobFile = ".\Export-RubrikDatabasesJobFile.json"
)

Import-Module Rubrik

if (Test-Path -Path $JobFile)
{
    $JobFile = (Get-Content $JobFile) -join "`n"  | ConvertFrom-Json

    #Currently there is no way to check for an existing connection to a Rubrik Cluster. This attempts to do that and only 
    #connects if an existing connection is not present. 
    try 
    {
        Get-RubrikVersion | Out-Null
    }
    catch 
    {
        #04/05/2018 - Chris Lumnah - Instead of using an encrypted text file, I am now using the more standard
        #CLiXml method
        #$Password = Get-Content $JobFIle.RubrikCluster.CredentialFilePassword | ConvertTo-SecureString
        $Credential = Import-CliXml -Path $JobFIle.RubrikCluster.Credential
        # Connect-Rubrik -Server $JobFile.RubrikCluster.Server `
        #    -Username $JobFile.RubrikCluster.Username  `
        #    -Password $Password | Out-Null
        Connect-Rubrik -Server $JobFile.RubrikCluster.Server -Credential $Credential
    }

    foreach ($Database in $JobFile.Databases)
    {
        $RubrikDatabase = Get-RubrikDatabase -Name $Database.Name -ServerInstance $Database.SourceServerInstance
        
        $TargetFiles = @()
        foreach ($DatabaseFile in $JobFile.Databases.Files)
        {
                $TargetFiles += @{logicalName=$DatabaseFile.logicalName;exportPath=$DatabaseFile.Path;newFileName=$DatabaseFile.FileName}       
        }


        #We look for the existance of the database on the target instance. If it exists, we must drop the database before we can 
        #proceed with exportation of the database to the target instance.
        $Query = "SELECT 1 FROM sys.databases WHERE name = '" + $Database.Name + "'" 
        $Results = Invoke-Sqlcmd -ServerInstance $Database.TargetServerInstance -Query $Query

        IF ($Results.Column1 -eq 1)
        {
            $Query = "ALTER DATABASE [" + $Database.Name + "] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;"
            $Results = Invoke-Sqlcmd -ServerInstance $Database.TargetServerInstance -Query $Query
            $Query = "DROP DATABASE [" + $Database.Name + "]"
            $Results = Invoke-Sqlcmd -ServerInstance $Database.TargetServerInstance -Query $Query
            #Refresh Rubik so it does not think the database still exists
            New-RubrikHost -Name $Database.TargetServerInstance -Confirm:$false | Out-Null
        }
        
        $TargetInstance = (Get-RubrikSQLInstance -ServerInstance $Database.TargetServerInstance)
        
        Export-RubrikDatabase -Id $RubrikDatabase.id `
            -TargetInstanceId $TargetInstance.id `
            -TargetDatabaseName $Database.Name `
            -recoveryDateTime (Get-date (Get-RubrikDatabase -id $RubrikDatabase.ID).latestRecoveryPoint) `
            -FinishRecovery `
            -TargetFilePaths $TargetFiles `
            -Confirm:$false
    }
}



<# 
In case the JSON file is deleted, you can use the below as an example to recreate the file. 

{
    "RubrikCluster":
    {
        "Server": "172.21.8.31",
        "Credential":"C:\\Users\\chrislumnah\\OneDrive\\Documents\\WindowsPowerShell\\Credentials\\RangerLab-AD.credential",
        "Username - NO LONGER USED": "admin",
        "CredentialFilePassword - NO LONGER USED":"C:\\Users\\chris\\OneDrive\\Documents\\WindowsPowerShell\\Credential.txt"

    },
    "Databases":
    [ 
        {
            "Name": "AdventureWorks2016",
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