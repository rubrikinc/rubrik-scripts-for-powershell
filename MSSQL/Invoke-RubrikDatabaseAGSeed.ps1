<#
.SYNOPSIS
    Use Rubrik to seed Availability Group Replicas
.DESCRIPTION
    Use Rubrik to seed Availability Group Replicas by using the Rubrik Log Shipping functionality that came out in v4.2
    
.EXAMPLE
    PS C:\> .\Invoke-RubikDatabaseAGSeed.ps1 -RubrikServer 172.12.12.111 `
        -DatabaseName "AthenaAM1-SQL16AG-1A-2016" `
        -PrimarySQLServerInstance "AM1-SQL16AG-1A" `
        -AvailabilityGroupName "am1-sql16ag-2ag" `
        -RubrikCredentialFile "C:\Temp\Rubrik.cred"

    The above command will connect to the Rubrik Cluster of 172.12.12.111 and establish log shipping between AM1-SQL16AG-1a and the other replicas. Add the databases into the availability 
    group and then remove log shipping.

.EXAMPLE
    PS C:\> .\Invoke-RubikDatabaseAGSeed.ps1 -RubrikServer 172.12.12.111 `
        -DatabaseName "AthenaAM1-SQL16AG-1A-2016" `
        -PrimarySQLServerInstance "AM1-SQL16AG-1A" `
        -AvailabilityGroupName "am1-sql16ag-2ag" `
        -Token "cc90adcd-8bd4-4d1d-beec-bc26e40feb0f"

    The above command will connect to the Rubrik Cluster of 172.12.12.111 and establish log shipping between AM1-SQL16AG-1a and the other replicas. Add the databases into the availability 
    group and then remove log shipping.
.INPUTS
    None except for parameters
.OUTPUTS
    None
.NOTES
    Name:               Seed Availability Group Replicas
    Created:            11/20/2018
    Updated:            12/10/2020
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
[CmdletBinding(DefaultParameterSetName='UserPassword')]
param(
    [Parameter(Mandatory=$true)]
    [string]$RubrikServer,
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName,
    [Parameter(Mandatory=$true)]
    [string]$PrimarySQLServerInstance,
    [Parameter(Mandatory=$true)]
    [String]$AvailabilityGroupName,
    [Parameter(ParameterSetName = 'CredentialFile', Mandatory)]
    [string]$RubrikCredentialFile,
    [Parameter(ParameterSetName = 'Token', Mandatory)]
    [string]$Token,
    [Parameter(ParameterSetName='UserPassword',Mandatory)]
    [String]$Username,
    [Parameter(ParameterSetName='UserPassword',Mandatory)]
    [SecureString]$Password
)
#region Script Parameters For Testing
# $PSBoundParameters.Add('RubrikServer', $rubrik.server.amer1)
# $PSBoundParameters.Add('DatabaseName','Athena_AM1-SQL16AG-1B')
# $PSBoundParameters.Add('PrimarySQLServerInstance','am1-sql16ag-1b')
# $PSBoundParameters.Add('AvailabilityGroupName','am1-sql16ag-1ag')
# $PSBoundParameters.Add('Token',$Rubrik.token.amer1)

# $RubrikServer = $PSBoundParameters['RubrikServer']
# $DatabaseName = $PSBoundParameters['DatabaseName']
# $PrimarySQLServerInstance = $PSBoundParameters['PrimarySQLServerInstance']
# $AvailabilityGroupName = $PSBoundParameters['AvailabilityGroupName']
# $Token = $PSBoundParameters['Token']
#endregion
#requires -modules  Rubrik, SQLServer
Import-Module Rubrik
Import-Module SQLServer

#region Check to see if the database name is a system database
if ($DatabaseName -in "master","msdb","model","tempdb","SSISDB")
{
    Write-Error "Only User databases are allowed for this operation. Do not specifiy a value of distribution, master, msdb, model, tempdb, SSISDB"
    break
}
# endregion

#region Check to make sure that the Availability Group is not set to AUTOMATIC SEEDING. If it is, it will cause problems with this script. 
$Query = "SELECT seeding_mode_desc FROM sys.availability_groups ag JOIN sys.availability_replicas r ON ag.group_id = r.group_id WHERE name = '$AvailabilityGroupName'" 

$AutoSeed = Invoke-Sqlcmd -ServerInstance $PrimarySQLServerInstance -Query $Query -Verbose

if ( $AutoSeed.seeding_mode_desc -eq "AUTOMATIC"){
    Write-Error "For this script to work, all replicas in the Availability Group named $($AvailabilityGroupName) must be set to MANUAL SEEDING mode"
    break
}
#endregion

#region Rubrik Connection
Write-Host "- Connecting to Rubrik:$RubrikServer"
switch($true){
    {$RubrikCredentialFile} {$RubrikCredential = Import-CliXml -Path $RubrikCredentialFile
        $ConnectRubrik = @{
            Server = $RubrikServer
            Credential = $RubrikCredential
        }
    }
    {$Token} {
        $ConnectRubrik = @{
            Server = $RubrikServer
            Token = $Token
        }
    }
    default {
        $ConnectRubrik = @{
            Server = $RubrikServer
            Username = $Username
            Password = $Password
        }
    }
}
Connect-Rubrik @ConnectRubrik
#endregion

#Get information about the database we will add to an availaility group
Write-Host "- Getting information about $DatabaseName on $PrimarySQLServerInstance from $RubrikServer"
$RubrikDatabase = Get-RubrikDatabase -Name $DatabaseName -ServerInstance $PrimarySQLServerInstance -DetailedObject | Where-Object {$_.isRelic -eq $false}
if ([bool]($RubrikDatabase.PSobject.Properties.name -match "id") -eq $false){
    Write-Error -Message "Database $DatabaseName on $PrimarySQLServerInstance not found on $RubrikServer"
    break
}

#Checking if the database has at least 1 full backup (snapshot)
if ([bool]($RubrikDatabase.latestRecoveryPoint) -eq $false){
    Write-Error "There are no full backup (snapshot) for $SQLServerHost\$SQLServerInstance\$DatabaseName, you have to start a full backup on Primary node before adding to an AG."
    break
}

#Go to the primary replica and get the other replica servers
$SourceSQLInstance = Get-RubrikSQLInstance -ServerInstance $PrimarySQLServerInstance

#Is the database already in an availability group?
Write-Host "- Checking to see if database is not already in an Availability Group"
$Query = "SELECT top 1 database_id 
FROM sys.dm_hadr_database_replica_states
WHERE database_id = DB_ID('$($DatabaseName)')"
$Groups = Invoke-Sqlcmd -ServerInstance $PrimarySQLServerInstance -Query $Query 

if ([bool]($Groups.PSobject.Properties.name -match "database_id") -eq $true){
    Write-Error "Database is already a member of an Availability Group"
    break
}

#What replicas are involved in the availbility group?
Write-Host "Getting replica servers involved in $AvailabilityGroupName from $PrimarySQLServerInstance"
If ($($SourceSQLInstance.Version).substring(0,$SourceSQLInstance.Version.indexOf(".")) -ge 13){
    $Query = "SELECT replica_server_name
    FROM [sys].[availability_groups] groups
    JOIN [sys].[availability_replicas] replicas
    ON groups.group_id = replicas.group_id
    WHERE groups.is_distributed = 0 AND name = '$($AvailabilityGroupName)' " 
}
else{
    $Query = "SELECT replica_server_name
    FROM [sys].[availability_groups] groups
    JOIN [sys].[availability_replicas] replicas
    ON groups.group_id = replicas.group_id
    WHERE name = '$($AvailabilityGroupName)' "  
}
$Replicas = Invoke-Sqlcmd -ServerInstance $PrimarySQLServerInstance -Query $Query 

[System.Collections.ArrayList] $ReplicasInAG=@()
foreach ($Replica in $Replicas){
    $db = New-Object PSObject
    $db | Add-Member -type NoteProperty -Name ReplicaServerName -Value $Replica.replica_server_name
    if ($Replica.replica_server_name.IndexOf("\") -gt 0){
        Write-Host "Getting information about $($Replica.replica_server_name) from $($RubrikServer)"
        $HostName = $Replica.replica_server_name.Substring(0,$Replica.replica_server_name.IndexOf("\"))
        $Instance = $Replica.replica_server_name.Substring($Replica.replica_server_name.IndexOf("\")+1,($Replica.replica_server_name.Length - $Replica.replica_server_name.IndexOf("\")) -1  )
        $TargetInstance = Get-RubrikSQLInstance -ServerInstance $Replica.replica_server_name
        if ([bool]($TargetInstance.PSobject.Properties.name -match "id") -eq $false){
            $FQDN = ([System.Net.Dns]::GetHostByName(($HostName))).hostname
            $TargetInstance = Get-RubrikSQLInstance -ServerInstance "$($FQDN)\$($Instance)"
            $Replica.replica_server_name = "$($FQDN)\$($Instance)"
        }
    }
    else{
        Write-Host "Getting information about $($Replica.replica_server_name) from $($RubrikServer)"
        $HostName = $Replica.replica_server_name
        $Instance = "DEFAULT"
        $TargetInstance = Get-RubrikSQLInstance -ServerInstance $Replica.replica_server_name
        if ([bool]($TargetInstance.PSobject.Properties.name -match "id") -eq $false){
            $FQDN = ([System.Net.Dns]::GetHostByName(($HostName))).hostname
            $TargetInstance = Get-RubrikSQLInstance -ServerInstance $FQDN
        }
    }


    if ([bool]($TargetInstance.PSobject.Properties.name -match "id") -eq $false){
        Write-Error -Message "$($Replica.replica_server_name) was not found on $RubrikServer"
        break
    }
    
    $db | Add-Member -type NoteProperty -name HostName -Value $HostName
    $db | Add-Member -type NoteProperty -name Instance -Value $Instance
    $db | Add-Member -type NoteProperty -name DatabaseName -Value $DatabaseName
    

    if ($Replica.replica_server_name -ne $PrimarySQLServerInstance){
        $Query = "SELECT state_desc FROM sys.databases WHERE name = '" + $DatabaseName + "'" 
        $Results = Invoke-Sqlcmd -ServerInstance $Replica.replica_server_name -Query $Query 

        if ([bool]($Results.PSobject.Properties.name -match "state_desc") -eq $true){
            Write-Host "$($DatabaseName) already exists on $($Replica.replica_server_name). Unable to setup log shipping when database already exists"
            $db | Add-Member -type NoteProperty -name RubrikRequest -Value "FAILED"
            $db | Add-Member -type NoteProperty -name Primary -Value $false
            break
        }   
        else{
            $TargetFilePaths = Get-RubrikDatabaseFiles -Id $RubrikDatabase.id `
                -RecoveryDateTime $RubrikDatabase.latestRecoveryPoint | Select-Object LogicalName,@{n='exportPath';e={$_.OriginalPath}},@{n='newFilename';e={$_.OriginalName}} 

            Write-Host "Setting up log shipping between $PrimarySQLServerInstance and $($Replica.replica_server_name)"
            $RubrikRequest = New-RubrikLogShipping -id $RubrikDatabase.id `
                -targetInstanceId $TargetInstance.id `
                -targetDatabaseName $DatabaseName `
                -state "RESTORING" `
                -TargetFilePaths $TargetFilePaths 
            $db | Add-Member -type NoteProperty -name RubrikRequest -Value $RubrikRequest
            $db | Add-Member -type NoteProperty -name Primary -Value $false
        }
    }
    else{
        $db | Add-Member -type NoteProperty -name Primary -Value $true
    }
    $ReplicasInAG += $db
}
$ReplicasInAG
break
# #Wait for log shipping requests to complete for all replicas
# foreach($Replica in $ReplicasinAG | Where-Object Primary -eq $false)
# {  
#     Get-RubrikRequest -id $Replica.RubrikRequest.id -WaitForCompletion -Type mssql
#     # Get-RubrikRequestInfo -RubrikRequest $Replica.RubrikRequest
# }

# Write-Host "Wait for all of the logs to be applied" -ForegroundColor Green
# foreach($Replica in $ReplicasinAG | Where-Object Primary -eq $false)
# {  
#     $GetRubrikLogShipping = @{
#         PrimaryDatabaseId = $RubrikDatabase.id
#     }
#     $RubrikLogShipping = Get-RubrikLogShipping @GetRubrikLogShipping


# Foreach ($LogShippedDB in $RubrikLogShipping){
#     do{
#         $CheckRubrikLogShipping = Get-RubrikLogShipping -id $LogShippedDB.id
#         $lastAppliedPoint = ($CheckRubrikLogShipping.lastAppliedPoint)
#         Start-Sleep -Seconds 1
#     } until ($latestRecoveryPoint -eq $lastAppliedPoint)
#     if ($RemoveLogShipping -eq $true){
#         Write-Host "Removing Log Shipping from $($LogShippedDB.location)" -ForegroundColor Green
#         Remove-RubrikLogShipping -id $LogShippedDB.id
#     }
# }



#Add all replicas to the availability group and then remove log shipping. 
foreach($Replica in $ReplicasinAG | Sort-Object Primary -Descending )
{
    if ([bool]($Replica.Primary) -eq $true){
        Write-Host "Adding $($DatabaseName) to $($AvailabilityGroupName) on $($Replica.ReplicaServerName)"
        $Query = "ALTER AVAILABILITY GROUP [$($AvailabilityGroupName)] ADD DATABASE [$($DatabaseName)];"
    }
    else {
        Write-Host "Joining $($DatabaseName) to $($AvailabilityGroupName) on $($Replica.ReplicaServerName)"
        $Query = "ALTER DATABASE [$($DatabaseName)] SET HADR AVAILABILITY GROUP =  [$($AvailabilityGroupName)]; "
    }
    Invoke-Sqlcmd -ServerInstance $Replica.ReplicaServerName -Query $Query -Verbose
}
Write-Host "Removing Log Shipping for $DatabaseName"
Get-RubrikLogShipping -PrimaryDatabaseName $DatabaseName -SecondaryDatabaseName $DatabaseName | Remove-RubrikLogShipping