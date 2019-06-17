<#
.SYNOPSIS
    Start-RubrikDBMigration.ps1 migrates databases from one server to another via Rubrik
.DESCRIPTION
    Start-RubrikDBMigration.ps1 migrates databases from one server to another via Rubrik. Script is meant for 
    small environments. For larger environments consider using log shipping.
    The script will take an on demand backup of each database provided and then wait for them to complete. Once they do, they will then start to restore to the target SQL Server. 
.PARAMETER RubrikCluster
    The IP address or name to your Rubrik Cluster. Required to be provided at runtime via the cmdline
.PARAMETER SourceSQLHost
    The host name to the source SQL Server
.PARAMETER SourceSQLInstance
    The instance for the SQL Server. Parameter is optional if using a default instance. If no value is provided, then we will assume MSSQLSERVER
.PARAMETER Databases
    Provide a single database or a comma separated list of databases. 
.PARAMETER TargetSQLHost
    The host name to the target SQL Server
.PARAMETER TargetSQLInstance
    The instance for the SQL Server. Parameter is optional if using a default instance. If no value is provided, then we will assume MSSQLSERVER
.PARAMETER TargetDataPath
    Path on the target SQL Server where SQL Server data files should live. If no value is provided, we will get the value from the target SQL Server.
.PARAMETER TargetLogPath
    Path on the target SQL Server where SQL Server log files should live. If no value is provided, we will get the value from the target SQL Server.
.PARAMETER MigrationFile
    Path to a CSV file with databases that should be migrated. 

    The CSV file should have the Column Header of the below
    SourceSQLHost, SourceSQLInstance, DatabaseName, TargetSQLHost, TargetSQLInstance, TargetDataPath, TargetLogPath
.PARAMETER TurnOffOldDBs
    If used, databases on Source SQL Server Instance will be set to read only and then set to offline after the backup has been taken. 
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
    https://github.com/rubrikinc/rubrik-scripts-for-powershell
    Updated:    06/14/2016
    Updater:    Chris Lumnah
    Updates:    Script will take either a csv of values or continue to take values from the cmdline. 
                Script will take a SQL Server and Instance as DBA would understand them and go look up the Windows Cluster name. 
                Script now requires the FailoverClusters module from Microsoft. 
                Script will work with stand alone SQL Instances and SQL Failover CLustered Instances
#>
[cmdletbinding(DefaultParameterSetName='File')]
param(
    [Parameter(Mandatory=$true)]
    [String]$RubrikServer,

    [Parameter(ParameterSetName="CMDLINE")]
    [String]$SourceSQLHost,
    
    [Parameter(ParameterSetName="CMDLINE")]
    [String]$SourceSQLInstance = 'MSSQLSERVER',

    [Parameter(ParameterSetName="CMDLINE")]
    [String[]]$Databases,

    [Parameter(ParameterSetName="CMDLINE")]
    [String]$TargetSQLHost,

    [Parameter(ParameterSetName="CMDLINE")]
    [String]$TargetSQLInstance = 'MSSQLSERVER',
    
    [Parameter(ParameterSetName="CMDLINE")]
    [String]$TargetDataPath,
    
    [Parameter(ParameterSetName="CMDLINE")]
    [String]$TargetLogPath,

    [Parameter(ParameterSetName="File")]
    [string]$MigrationFile,

    [Parameter(Mandatory=$false)]
    [switch]$TurnOffOldDBs
)
#region FUNCTIONS
function Get-SQLDatabaseDefaultLocations{
    #Code is based on snippet provied by Steve Bonham of LFG
    param(
        [Parameter(Mandatory=$true)]
        [string]$Server
    )
    Import-Module sqlserver  
    $SMOServer = new-object ('Microsoft.SqlServer.Management.Smo.Server') $Server 

    # Get the Default File Locations 
    $DatabaseDefaultLocations = New-Object PSObject
    Add-Member -InputObject $DatabaseDefaultLocations -MemberType NoteProperty -Name Data -Value $SMOServer.Settings.DefaultFile 
    Add-Member -InputObject $DatabaseDefaultLocations -MemberType NoteProperty -Name Log -Value $SMOServer.Settings.DefaultLog 
  
    if ($DatabaseDefaultLocations.Data.Length -eq 0){$DatabaseDefaultLocations.Data = $SMOServer.Information.MasterDBPath} 
    if ($DatabaseDefaultLocations.Log.Length -eq 0){$DatabaseDefaultLocations.Log = $SMOServer.Information.MasterDBLogPath} 
    return $DatabaseDefaultLocations
}

function Get-WindowsClusterResource{
    param(
        [String]$ServerInstance,
        [String]$Instance
    )
    Import-Module FailoverClusters
    Import-Module SqlServer
    $InvokeSQLCMD = @{
        Query = "SELECT TOP (1) [NodeName] FROM [master].[sys].[dm_os_cluster_nodes]"
        ServerInstance = $ServerInstance
    }
    $Results = Invoke-SQLCMD @InvokeSQLCMD      
    if ([bool]($Results.PSobject.Properties.name -match "NodeName") -eq $true){  
        $Cluster = Get-ClusterResource -Cluster $Results.NodeName | Where-Object {$_.ResourceType -like "*SQL Server*" -and $_.Name -like "*$Instance*" -and $_.Name -notlike "*Agent*"} 
        return $Cluster
    }
}
#endregion
#region MODULES
#Requires -Modules FailoverClusters, Rubrik, SQLServer
Import-Module Rubrik
Import-Module SQLServer
Import-Module FailoverClusters
#endregion
#region Rubrik Connection Information
#$Credential = (Get-Credential -Message "Enter User ID and Password to connect to Rurbik Cluster" )
$ConnectRubrik = @{
    Server = $RubrikServer
    Credential = $Credential
    #Credential  = $Credentials.RangerLab
}
Connect-Rubrik @ConnectRubrik
#endregion

#Create an object to store databases to be backed up
[System.Collections.ArrayList] $DatabasesToBeMigrated=@()

#region Create a queue of all databases that need to be migrated
if ($PSBoundParameters.ContainsKey('MigrationFile')){
    $MigrationTasks = Import-Csv $MigrationFile 

    foreach ($Database in $MigrationTasks){
        $db = New-Object PSObject
        $db | Add-Member -type NoteProperty -name SourceSQLHost -Value $Database.SourceSQLHost
        
        if ([string]::IsNullOrEmpty($Database.SourceSQLInstance)){
            $db | Add-Member -type NoteProperty -name SourceSQLInstance -Value "MSSQLSERVER"
            $db | Add-Member -type NoteProperty -name SourceServerInstance -Value "$($Database.SourceSQLHost)"
        }else{
            $db | Add-Member -type NoteProperty -name SourceSQLInstance -Value $Database.SourceSQLInstance
            $db | Add-Member -type NoteProperty -name SourceServerInstance -Value "$($Database.SourceSQLHost)\$($Database.SourceSQLInstance)"
        }
        
        $db | Add-Member -type NoteProperty -name Name -Value $Database.DatabaseName

        $db | Add-Member -type NoteProperty -name TargetSQLHost -Value $Database.TargetSQLHost
        if ([string]::IsNullOrEmpty($Database.TargetSQLInstance)){
            $db | Add-Member -type NoteProperty -name TargetSQLInstance -Value "MSSQLSERVER"
            $db | Add-Member -type NoteProperty -name TargetServerInstance -Value "$($Database.TargetSQLHost)"
        }else{
            $db | Add-Member -type NoteProperty -name TargetSQLInstance -Value $Database.TargetSQLInstance
            $db | Add-Member -type NoteProperty -name TargetServerInstance -Value "$($Database.TargetSQLHost)\$($Database.TargetSQLInstance)"
        }

        $db | Add-Member -type NoteProperty -name TargetRubrikInstance -Value ""
        $db | Add-Member -type NoteProperty -name TargetDataPath -Value $Database.TargetDataPath
        $db | Add-Member -type NoteProperty -name TargetLogPath -Value $Database.TargetLogPath
        $db | Add-Member -type NoteProperty -name RubrikDatabase -Value ""
        $db | Add-Member -type NoteProperty -name RubrikRequest -Value ""
        $DatabasesToBeMigrated += $db
    }
}else{
    foreach ($Database in $Databases){
        $db = New-Object PSObject
        $db | Add-Member -type NoteProperty -name SourceSQLHost -Value $SourceSQLHost
        
        if ([string]::IsNullOrEmpty($SourceSQLInstance)){
            $db | Add-Member -type NoteProperty -name SourceSQLInstance -Value "MSSQLSERVER"
            $db | Add-Member -type NoteProperty -name SourceServerInstance -Value "$($SourceSQLHost)"
        }else{
            $db | Add-Member -type NoteProperty -name SourceSQLInstance -Value $SourceSQLInstance
            $db | Add-Member -type NoteProperty -name SourceServerInstance -Value "$($SourceSQLHost)\$($SourceSQLInstance)"
        }

        $db | Add-Member -type NoteProperty -name Name -Value $Database

        $db | Add-Member -type NoteProperty -name TargetSQLHost -Value $TargetSQLHost

        if ([string]::IsNullOrEmpty($TargetSQLInstance)){
            $db | Add-Member -type NoteProperty -name TargetSQLInstance -Value "MSSQLSERVER"
            $db | Add-Member -type NoteProperty -name TargetServerInstance -Value "$($TargetSQLHost)"
        }else{
            $db | Add-Member -type NoteProperty -name TargetSQLInstance -Value $TargetSQLInstance
            $db | Add-Member -type NoteProperty -name TargetServerInstance -Value "$($TargetSQLHost)\$($TargetSQLInstance)"
        }

        $db | Add-Member -type NoteProperty -name TargetRubrikInstance -Value ""
        $db | Add-Member -type NoteProperty -name TargetDataPath -Value $TargetDataPath
        $db | Add-Member -type NoteProperty -name TargetLogPath -Value $TargetLogPath
        $db | Add-Member -type NoteProperty -name RubrikDatabase -Value ""
        $db | Add-Member -type NoteProperty -name RubrikRequest -Value ""
        $DatabasesToBeMigrated += $db
    }
}
#endregion

#region Set databases to read only if this is the final backup
if($TurnOffOldDBs){
    Foreach($Database in $DatabasesToBeMigrated){
        Write-Host "Setting $($Database.Name) on $($Database.SourceServerInstance) to Read Only"
        
        $InvokeSQLCMD = @{
            ServerInstance = $Database.SourceServerInstance
            Query = "ALTER DATABASE [$($Database.Name)] SET READ_ONLY WITH NO_WAIT"
        }
        Invoke-Sqlcmd @InvokeSQLCMD
    }
}
#endregion

#Backup each database via an async job on Rubrik appliance
Foreach($Database in $DatabasesToBeMigrated){
    #Check if Source SQL Server is a FCI
    $GetWindowsCluster = @{
        ServerInstance = $Database.SourceServerInstance
        Instance = $Database.SourceSQLInstance
    }
    $Cluster =  Get-WindowsClusterResource @GetWindowsCluster
    if ([bool]($Cluster.PSobject.Properties.name -match "Cluster") -eq $true){
        $GetRubrikDatabase = @{
            Name = $Database.Name
            HostName = $Cluster.Cluster
            Instance = $Database.SourceSQLInstance
        }
    }else{
        $GetRubrikDatabase = @{
            Name = $Database.Name
            HostName = $Database.SourceSQLHost
            Instance = $Database.SourceSQLInstance
        }
    }
    $Database.RubrikDatabase = Get-RubrikDatabase @GetRubrikDatabase

    if ([bool]($Database.RubrikDatabase.PSobject.Properties.name -match "id") -eq $true){
        Write-Host "Kicking off an on demand backup of $($Database.Name) on $($Database.SourceServerInstance)"
        $NewRubrikSnapshot = @{
            id = $Database.RubrikDatabase.id
            SLA = $Database.RubrikDatabase.effectiveSlaDomainName
            Confirm = $false
        }
        $Database.RubrikRequest = New-RubrikSnapshot @NewRubrikSnapshot
    }
}
#Get the Target info for the queue
Foreach($Database in $DatabasesToBeMigrated){
    $GetWindowsCluster = @{
        ServerInstance = $Database.TargetServerInstance
        Instance = $Database.TargetSQLInstance
    }
    $Cluster =  Get-WindowsClusterResource @GetWindowsCluster

    if ([bool]($Cluster.PSobject.Properties.name -match "Cluster") -eq $true){
        $GetRubrikSQLInstance = @{
            HostName = $Cluster.Cluster
            Name = $Database.TargetSQLInstance
        }
        #Use this later to refresh the host that we restore too
        $GetRubrikHost = @{
            Name = $Cluster.OwnerNode
        }
    }else{
        $GetRubrikSQLInstance = @{
            HostName = $Database.TargetSQLHost
            Name = $Database.TargetSQLInstance
        }
        #Use this later to refresh the host that we restore too
        $GetRubrikHost = @{
            Name = $Database.TargetSQLHost
        }
    }
    $Database.TargetRubrikInstance = Get-RubrikSQLInstance @GetRubrikSQLInstance
}

#Wait for all backups to complete
do{
    foreach ($Database in $DatabasesToBeMigrated | where-object {-not ([string]::IsNullOrEmpty($_.RubrikRequest.ID)) -and $_.RubrikRequest.Status -notin 'FAILED','SUCCEEDED' }){
        $Request = Get-RubrikRequest -id $Database.RubrikRequest.Id -Type 'mssql'
        $Database.RubrikRequest.Status = $Request.Status
        if ($Request.Status -eq 'RUNNING'){$Database.RubrikRequest.Progress = $Request.Progress}
        Write-Host "Checking $($Database.Name) backup progress. $($Request.Progress) complete. Current Status is $($Request.Status)"
    }
    $x=$DatabasesToBeMigrated | where-object {-not ([string]::IsNullOrEmpty($_.RubrikRequest.ID)) -and $_.RubrikRequest.Status -notin 'FAILED','SUCCEEDED' } | Measure-Object
}until ($x.count -eq 0)
#Clean up the target server and get rid of the database if it already exists. 
#Lets Start doing Restores 
Foreach($Database in $DatabasesToBeMigrated)
{
    $Database.RubrikRequest = ""

    if($TurnOffOldDBs)
    {
        Write-Host "Setting $($Database.Name) offline on $($Database.SourceServerInstance)"
        $InvokeSQLCMD = @{
            ServerInstance = $Database.SourceServerInstance
            Query = "ALTER DATABASE [$($Database.Name)] SET OFFLINE"
        }
        Invoke-Sqlcmd @InvokeSQLCMD
    }

    $InvokeSQLCMD = @{
        ServerInstance = $Database.TargetServerInstance
        Query = "SELECT state_desc FROM sys.databases WHERE name = '" + $Database.Name + "'" 
    }
    $Results = Invoke-Sqlcmd @InvokeSQLCMD

    if ([bool]($Results.PSobject.Properties.name -match "state_desc") -eq $true)
    {
        if ($Results.state_desc -eq 'ONLINE')
        {
            Write-Host "Setting $($Database.Name) to SINGLE_USER"
            Write-Host "Dropping $($Database.Name)"
            $InvokeSQLCMD = @{
                ServerInstance = $Database.TargetServerInstance
                Query = "ALTER DATABASE [" + $Database.Name + "] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; `nDROP DATABASE [" + $Database.Name + "]"
            }
            $Results = Invoke-Sqlcmd @InvokeSQLCMD
        }
        else 
        {
            Write-Host "Dropping $($Database.Name)"
            $InvokeSQLCMD = @{
                ServerInstance = $Database.TargetServerInstance
                Query = "DROP DATABASE [" + $Database.Name + "]"
            }
            $Results = Invoke-Sqlcmd @InvokeSQLCMD
        }
    }
    
    #Refresh Rubrik so it does not think the database still exists
    Write-Host "Refreshing $($Database.TargetSQLHost) in Rubrik"
    Get-RubrikHost @GetRubrikHost | Update-RubrikHost | Out-Null
    
    $RubrikDatabaseFiles = Get-RubrikDatabaseFiles -Id $Database.RubrikDatabase.ID -RecoveryDateTime (Get-RubrikDatabase -id $Database.RubrikDatabase.ID).latestRecoveryPoint

    if ([string]::IsNullOrEmpty($Database.TargetDataPath) -or [string]::IsNullOrEmpty($Database.TargetLogPath)){
        $DatabaseDefaultLocations = Get-SQLDatabaseDefaultLocations -Server $Database.TargetServerInstance
        $Database.TargetDataPath = $DatabaseDefaultLocations.Data
        $Database.TargetLogPath = $DatabaseDefaultLocations.Log
    }

    $TargetFiles = @()
    foreach ($RubrikDatabaseFile in $RubrikDatabaseFiles){
        if ($RubrikDatabaseFile.islog -eq $true){
            $TargetFiles += @{logicalName=$RubrikDatabaseFile.logicalName;exportPath=$Database.TargetLogPath;newFilename=$RubrikDatabaseFile.originalName}       
        }else{
            $TargetFiles += @{logicalName=$RubrikDatabaseFile.logicalName;exportPath=$Database.TargetDataPath;newFilename=$RubrikDatabaseFile.originalName}       
        }
    }

    Write-Host "Starting restore of $($Database.Name) onto $($Database.TargetServerInstance)"
    $ExportRubrikDatabase = @{
        Id =  $Database.RubrikDatabase.id
        TargetInstanceId = $Database.TargetRubrikInstance.id 
        TargetDatabaseName =  $Database.Name 
        recoveryDateTime = (Get-RubrikDatabase -id $Database.RubrikDatabase.id).latestRecoveryPoint
        FinishRecovery = $true
        TargetFilePaths =  $TargetFiles
        Confirm = $false
    }
    $Database.RubrikRequest = Export-RubrikDatabase @ExportRubrikDatabase
}
#Wait for all restores to complete
do{
    foreach ($Database in $DatabasesToBeMigrated | where-object {-not ([string]::IsNullOrEmpty($_.RubrikRequest.ID)) -and $_.RubrikRequest.Status -notin 'FAILED','SUCCEEDED' }){
        $Request = Get-RubrikRequest -id $Database.RubrikRequest.Id -Type 'mssql'
        $Database.RubrikRequest.Status = $Request.Status
        if ($Request.Status -eq 'RUNNING'){$Database.RubrikRequest.Progress = $Request.Progress}
        Write-Host "Checking $($Database.Name) restore progress. $($Request.Progress) complete. Current Status is $($Request.Status)"
    }
    $x=$DatabasesToBeMigrated | where-object {-not ([string]::IsNullOrEmpty($_.RubrikRequest.ID)) -and $_.RubrikRequest.Status -notin 'FAILED','SUCCEEDED' } | Measure-Object
}until ($x.count -eq 0)

if($TurnOffOldDBs){
    Foreach($Database in $DatabasesToBeMigrated){
        Write-Host "Setting $($Database.Name) to Read Write"
        $InvokeSQLCMD = @{
            Query = "ALTER DATABASE [$($Database.Name)] SET READ_WRITE"
            ServerInstance = $Database.TargetServerInstance
        }
        Invoke-Sqlcmd @InvokeSQLCMD
    }
}
