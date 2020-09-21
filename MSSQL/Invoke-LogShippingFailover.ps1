<#
.SYNOPSIS
    Script will fail over a database involve with log shipping to the secondary side and then reverse the log shipping process from the new primary to the new secondary
.DESCRIPTION
    Script will fail over a database involve with log shipping to the secondary side and then reverse the log shipping process from the new primary to the new secondary
.EXAMPLE
    PS C:\> .\Invoke-LogShippingFailover.ps1 -RubrikServer 172.1.1.1 -SourceSQLServerInstance sql1\instancename -TargetSQLServerInstance sql2\instancename -Databases Adventureworks
    Will bring Adventureworks online on SQL2\InstanceName, take Adventureworks offline on SQL1\InstanceName and then reverse the log shipping process from SQL2 to SQL1
.PARAMETER RubrikServer
    Rubrik Server should be the IP Address or your Rubrik Server Name. This will be the same value you use to access the Rubrik UI
.PARAMETER SourceSQLServerInstance
    Source SQL Host is the name of the SQL Server Host. 
    If an SQL FCI, then this will be the Virtual Name given to SQL Server
    If an Availability Group, then this should be the availability group name
.PARAMETER TargetSQLServerInstance
    This is the name of the SQL Server Instance. 
    If referrencing a Default instance, then this should be MSSQLSERVER
    If referrencing a Named instance, then this should be the instance name
    This is defaulted to MSSQLSERVER if no value is provided. 
.PARAMETER Databases
    Provide a comma separated list of databases found on the source SQL Server and Instance
.PARAMETER RubrikCredentialFile
    File that will contain encrypted credentials to log into to RUbrik with. To create that file use the statements
        $Credential = Get-Credential
        $Credential | Export-CliXml -Path .\rubrik.Cred
.PARAMETER Token
    API Token from Rubrik. You can generate this inside of the Rurbik UI

.NOTES
    Name:       Invoke Log Shipping Failover
    Created:    4/10/2020
    Author:     Chris Lumnah

#>
[cmdletbinding()]
#requires -modules Rubrik, SQLServer
[CmdletBinding()]
param (
    [Parameter()]
    [string]$RubrikCluster,
    [Parameter()]
    [string]$SourceSQLServerInstance,
    [Parameter()]
    [string]$TargetSQLServerInstance,
    [Parameter()]
    [string[]]$Databases,
    [Parameter(ParameterSetName = 'CredentialFile')]
    [string]$RubrikCredentialFile,
    [Parameter(ParameterSetName = 'Token')]
    [string]$Token

)

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
        }
    }
}
Connect-Rubrik @ConnectRubrik

$PrimaryInstance = Get-RubrikSQLInstance -ServerInstance $SourceSQLServerInstance
$SecondaryInstance = Get-RubrikSQLInstance -ServerInstance $TargetSQLServerInstance

ForEach ($Database in $Databases){
    $GetRubrikLogShipping = @{
        PrimaryDatabaseID = $PrimaryDatabase.id
        SecondaryDatabaseName = $PrimaryDatabase.name
        Location = $TargetSQLServerInstance
    }
    $RubrikLogShipping = Get-RubrikLogShipping @GetRubrikLogShipping
    if ([bool]($RubrikLogShipping.PSobject.Properties.name -match "id") -eq $true){
        $GetRubrikDatabase = @{
            Name = $Database
            InstanceID = $PrimaryInstance.id
        }
        $PrimaryDatabase = Get-RubrikDatabase @GetRubrikDatabase

        #region Sync up Primary and Secondary
        Write-Host "Take final transaction log backup of $($Database) on $SourceSQLServerInstance"
        $RubrikRequest = New-RubrikLogBackup -id $PrimaryDatabase.id
        Get-RubrikRequest -id $RubrikRequest.id -Type mssql -WaitForCompletion
    
        Write-Host "Get the latest recovery point"
        $latestRecoveryPoint = ((Get-RubrikDatabase -id $PrimaryDatabase.id).latestRecoveryPoint)

        Write-Host "Applying all transaction logs from $($SourceSQLServerInstance).$($PrimaryDatabase.name) to $($TargetSQLServerInstance).$($PrimaryDatabase.name)"

        Set-RubrikLogShipping -id $RubrikLogShipping.id -state $RubrikLogShipping.state     
    }else{
        Write-Host "Log Shipping is not setup for $($SourceSQLServerInstance).$($PrimaryDatabase.name) to $($TargetSQLServerInstance).$($PrimaryDatabase.name)"
        BREAK
    }
  
    Write-Host "Wait for all of the logs to be applied"
    do{
        $CheckRubrikLogShipping = Get-RubrikLogShipping -id $RubrikLogShipping.id
        $lastAppliedPoint = ($CheckRubrikLogShipping.lastAppliedPoint)
        Start-Sleep -Seconds 1
    } until ($latestRecoveryPoint -eq $lastAppliedPoint)
    
    #Grab the file layout of the primary database
    $TargetFilePaths = Get-RubrikDatabaseFiles -Id $PrimaryDatabase.id -RecoveryDateTime $latestRecoveryPoint | Select-Object LogicalName,@{n='exportPath';e={$_.OriginalPath}},@{n='newFilename';e={$_.OriginalName}} 
    
    #endregion

    #region Do Failover Steps
    Write-Host "Remove Log Shipping"
    Remove-RubrikLogShipping -id $RubrikLogShipping.id
    
    Write-Host "Quick comparison of the source database and the target database"
    write-host "Latest Recovery Point: $latestRecoveryPoint"
    write-host "Last Applied Point: $lastAppliedPoint"
    

    write-host "Bring the $($PrimaryDatabase.name) online on $TargetSQLServerInstance"
    $Query = "RESTORE DATABASE [$($PrimaryDatabase.name)] WITH RECOVERY"
    Invoke-Sqlcmd -ServerInstance $TargetSQLServerInstance -Query $Query

    write-host "Removing $($PrimaryDatabase.name) from $SourceSQLServerInstance"
    $Query = "DROP DATABASE [$($PrimaryDatabase.name)]"
    Invoke-Sqlcmd -ServerInstance $SourceSQLServerInstance -Query $Query

    Write-Host "Refresh Rubrik Metadata about $($SourceSQLServerInstance)"
    New-RubrikHost -Name $SourceSQLServerInstance | Out-Null

    Write-Host "Refresh Rubrik Metadata about $($TargetSQLServerInstance)"
    New-RubrikHost -Name $TargetSQLServerInstance | Out-Null
    # endregion

    #region establish log shipping going the other way
    $GetRubrikDatabase = @{
        Name = $Database
        InstanceID = $SecondaryInstance.id
    }
    $NewPrimaryDB = Get-RubrikDatabase @GetRubrikDatabase | Where-Object {$_.isRelic -eq $false}
    $NewTargetInstance = $SourceSQLInstance
    Write-Host "Taking new snapshot of $($TargetSQLServerInstance).$($PrimaryDatabase.name)"

    $RubrikRequest = New-RubrikSnapshot -id $NewPrimaryDB.id -SLA $NewPrimaryDB.effectiveSlaDomainName -Confirm:$false
    Get-RubrikRequest -id $RubrikRequest.id -Type mssql -WaitForCompletion

    Write-Host "Taking new transaction log backup of $($TargetSQLServerInstance).$($PrimaryDatabase.name)"
    # $RubrikRequest = New-RubrikLogBackup -id $NewPrimaryDB.id
    # Get-RubrikRequest -id $RubrikRequest.id -Type mssql -WaitForCompletion

    Write-Host "Setting up log shipping for $($TargetSQLServerInstance).$($PrimaryDatabase.name) to $($SourceSQLServerInstance).$($PrimaryDatabase.name)"
    New-RubrikLogShipping -id $NewPrimaryDB.id -state RESTORING -targetDatabaseName $NewPrimaryDB.Name -TargetFilePaths $TargetFilePaths -targetInstanceId $NewTargetInstance.id  -Verbose
    #endregion
}
