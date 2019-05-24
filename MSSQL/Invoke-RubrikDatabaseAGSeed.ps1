#requires -modules Rubrik, SQLServer
<#
.SYNOPSIS
    Use Rubrik to seed Availability Group Replicas
.DESCRIPTION
    Use Rubrik to seed Availability Group Replicas by using the Rubrik Log Shipping functionality that came out in v4.2
    
.EXAMPLE
    PS C:\> .\Invoke-RubikDatabaseAGSeed.ps1 -RubrikServer 172.12.12.111 `
        -DatabaseName "AthenaAM1-SQL16AG-1A-2016" `
        -SQLServerHost "AM1-SQL16AG-1A" `
        -SQLServerInstance "MSSQLSERVER" `
        -AGName "am1-sql16ag-2ag" `
        -RubrikCredentialFile "C:\Temp\Rubrik.cred"

    The above command will connect to the Rubrik Cluster of 172.12.12.111 and establish log shipping between AM1-SQL16AG-1a and the other replicas. Add the databases into the availability 
    group and then remove log shipping.
.INPUTS
    None except for parameters
.OUTPUTS
    None
.NOTES
    Name:               Seed Availability Group Replicas
    Created:            11/20/2018
    Author:             Chris Lumnah
    Execution Process:
        Before running this script, you need to create a credential file so that you can securly log into the Rubrik 
        Cluster. To do so run the below command via Powershell
        $Credential = Get-Credential
        $Credential | Export-CliXml -Path .\rubrik.Cred"
            
    The above will ask for a user name and password and them store them in an encrypted xml file.
    Script expects that the DBA has already created an Availability Group in SQL Server. The DBA should have already established what nodes are involved in the group
    connected them to the group and createa a listener. It is also expected that the DBA has already set the database into full recovery mode and is currently backing up the 
    primary database via Rubrik now. It is expected that the DBA has made the database meet standard SQL Server AG requirements. This script will connect to SQL Server and read 
    the [sys].[availability_replicas] table to determine what other servers are involved in the group. The script will then establish Rubrik Log Shipping between the primary replica 
    and the secondary replicas. Once the log shipping has caught up the secondary replicas to the primary, the script will then add all databases into the availability group and remove 
    Rubrik Log Shipping. 
#>
param
(
    [CmdletBinding()]
    [Parameter(Mandatory=$true)]
    [string]$RubrikServer,
    
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName,
    
    [Parameter(Mandatory=$true)]
    [string]$SQLServerHost,
    
    [Parameter(Mandatory=$false)]
    [string]$SQLServerInstance = "MSSQLSERVER",
    
    [Parameter(Mandatory=$true)]
    [string]$AGName,
    
    #[Parameter(Mandatory=$false)]
    #[string]$targetDataFilePath,
    
    #[Parameter(Mandatory=$false)]
    #[string]$targetLogFilePath,
    
    [Parameter(Mandatory=$false)]
    [string]$RubrikCredentialFile = "C:\Temp\Rubrik.cred"
)
Import-Module Rubrik
Import-Module SQLServer

if ($DatabaseName -in "master","msdb","model","tempdb","SSISDB")
{
    Write-Error "Only User databases are allowed for this operation. Do not specifiy a value of distribution, master, msdb, model, tempdb, SSISDB"
    break
}

if ([string]::IsNullOrEmpty($RubrikCredentialFile))
{
    $RubrikCredential = Get-Credential
}
elseif (Test-Path -Path $RubrikCredentialFile)
{
    $RubrikCredential = Import-CliXml -Path $RubrikCredentialFile
}
else 
{
    $RubrikCredential = Get-Credential
}

function Get-RubrikRequestInfo
{
    param(
        # Rubrik Request Object Info
        [Parameter(Mandatory=$true)]
        [PSObject]$RubrikRequest
    )
    
    $ExitList = @("SUCCEEDED", "FAILED")
    do 
    {
        $RubrikRequestInfo = Get-RubrikRequest -id $RubrikRequest.id -Type "mssql"
        IF ($RubrikRequestInfo.progress -gt 0)
        {
            Write-Host "$($RubrikRequestInfo.id) is $($RubrikRequestInfo.status) $($RubrikRequestInfo.progress) complete"
            Write-Progress -Activity "$($RubrikRequestInfo.id) is $($RubrikRequestInfo.status)" -status "Progress $($RubrikRequestInfo.progress)" -percentComplete ($RubrikRequestInfo.progress)
        }
        else
        {
            Write-Progress -Activity "$($RubrikRequestInfo.id)" -status "Job Queued" -percentComplete (0)
        }
        Start-Sleep -Seconds 1
    } while ($RubrikRequestInfo.status -notin $ExitList) 	
}

Write-Debug "Connecting to Rubrik:$RubrikServer"
Connect-Rubrik -Server $RubrikServer -Credential $RubrikCredential

#Get information about the database we will add to an availaility group
Write-Debug "Getting information about $DatabaseName from $RubrikServer"
$RubrikDatabase = Get-RubrikDatabase -Name $DatabaseName -Hostname $SQLServerHost -Instance $SQLServerInstance
$SourceSQLInstance = Get-RubrikSQLInstance -Hostname $SQLServerHost -Name $SQLServerInstance  

#Go to the primary replica and get the other replica servers
$ServerInstance = $SQLServerHost
if ($SQLServerInstance.ToUpper() -ne "MSSQLSERVER")
{
    $ServerInstance = "$($SQLServerHost)\$($SQLServerInstance)"
}

#Is the database already in an availability group?
Write-Debug "Checking to see if database is not already in an Availability Group"
$Query = "SELECT top 1 database_id 
FROM sys.dm_hadr_database_replica_states
WHERE database_id = DB_ID('$($DatabaseName)')"
$Groups = Invoke-Sqlcmd -ServerInstance $ServerInstance -Query $Query 

if ([bool]($Groups.PSobject.Properties.name -match "database_id") -eq $true)
{
    Write-Error "Database is already a member of an Availability Group"
    break
}

#What replicas are involved in the availbility group?
Write-Debug "Getting replica servers involved in $AGName from $ServerInstance"
If ($($SourceSQLInstance.Version).substring(0,$SourceSQLInstance.Version.indexOf(".")) -ge 13)
{
    $Query = "SELECT replica_server_name
    FROM [sys].[availability_groups] groups
    JOIN [sys].[availability_replicas] replicas
    ON groups.group_id = replicas.group_id
    WHERE groups.is_distributed = 0 AND name = '$($AGName)' " 
}
else 
{
    $Query = "SELECT replica_server_name
    FROM [sys].[availability_groups] groups
    JOIN [sys].[availability_replicas] replicas
    ON groups.group_id = replicas.group_id
    WHERE name = '$($AGName)' "  
}
$Replicas = Invoke-Sqlcmd -ServerInstance $ServerInstance -Query $Query 

[System.Collections.ArrayList] $ReplicasInAG=@()
foreach ($Replica in $Replicas)
{
    if ($Replica.replica_server_name.IndexOf("\") -gt 0)
    {
        Write-Debug "Getting information about $($Replica.replica_server_name) from $($RubrikServer)"
        $HostName = $Replica.replica_server_name.Substring(0,$Replica.replica_server_name.IndexOf("\"))
        $Instance = $Replica.replica_server_name.Substring($Replica.replica_server_name.IndexOf("\")+1,($Replica.replica_server_name.Length - $Replica.replica_server_name.IndexOf("\")) -1  )
        $TargetInstance = Get-RubrikSQLInstance -Hostname $HostName -Name $Instance       
    }
    else 
    {
        Write-Debug "Getting information about $($Replica.replica_server_name) from $($RubrikServer)"
        $TargetInstance = Get-RubrikSQLInstance -Hostname $Replica.replica_server_name -Name "MSSQLSERVER"
        $HostName = $Replica.replica_server_name
        $Instance = "DEFAULT"
    }

    $db = New-Object PSObject
    $db | Add-Member -type NoteProperty -name HostName -Value $HostName
    $db | Add-Member -type NoteProperty -name Instance -Value $Instance
    $db | Add-Member -type NoteProperty -name DatabaseName -Value $DatabaseName

    if ($Replica.replica_server_name -ne $SQLServerHost)
    {
        $Query = "SELECT state_desc FROM sys.databases WHERE name = '" + $DatabaseName + "'" 
        $Results = Invoke-Sqlcmd -ServerInstance $Replica.replica_server_name -Query $Query 

        if ([bool]($Results.PSobject.Properties.name -match "state_desc") -eq $true)
        {
            Write-Debug "$($DatabaseName) already exists on $($Replica.replica_server_name). Unable to setup log shipping when database already exists"
            $db | Add-Member -type NoteProperty -name RubrikRequest -Value "FAILED"
            $db | Add-Member -type NoteProperty -name Primary -Value $false
            break
        }   
        else 
        {
            $TargetFilePaths = Get-RubrikDatabaseFiles -Id $RubrikDatabase.id `
                -RecoveryDateTime (Get-RubrikDatabase -id $RubrikDatabase.ID).latestRecoveryPoint | Select-Object LogicalName,@{n='exportPath';e={$_.OriginalPath}},@{n='newFilename';e={$_.OriginalName}} 

            Write-Debug "Setting up log shipping between $ServerInstance and $($Replica.replica_server_name)"
            $RubrikRequest = New-RubrikLogShipping -id $RubrikDatabase.id `
                -targetInstanceId $TargetInstance.id `
                -targetDatabaseName $DatabaseName `
                -state "RESTORING" `
                -TargetFilePaths $TargetFilePaths 
                #-targetDataFilePath $targetDataFilePath `
                #-targetLogFilePath $targetLogFilePath
            $db | Add-Member -type NoteProperty -name RubrikRequest -Value $RubrikRequest
            $db | Add-Member -type NoteProperty -name Primary -Value $false
        }
    }
    else 
    {
        $db | Add-Member -type NoteProperty -name Primary -Value $true
    }

    $ReplicasInAG += $db
}
#Wait for log shipping requests to complete for all replicas
foreach($Replica in $ReplicasinAG | Where-Object Primary -eq $false)
{   
    Get-RubrikRequestInfo -RubrikRequest $Replica.RubrikRequest
}
#Add all replicas to the availability group and then remove log shipping. 
foreach($Replica in $ReplicasinAG | Sort-Object Primary -Descending)
{   
    Write-Debug "Adding $($DatabaseName) to $($AGName) on $($Replica.HostName)\$($Replica.Instance)"
    Add-SqlAvailabilityDatabase -Path "SQLSERVER:\SQL\$($Replica.HostName)\$($Replica.Instance)\AvailabilityGroups\$($AGName)" -Database $DatabaseName        
}
Write-Debug "Removing Log Shipping for $DatabaseName"
Get-RubrikLogShipping -PrimaryDatabaseName $DatabaseName -SecondaryDatabaseName $DatabaseName | Remove-RubrikLogShipping