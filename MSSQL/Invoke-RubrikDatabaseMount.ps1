<#
.SYNOPSIS
    Live Mount a list of databases 
.DESCRIPTION
    Live Mount a list of databases from one SQL Server to another
.EXAMPLE
    PS C:\> .\Invoke-RubrikDatabaseMount.ps1 -RubrikServer 172.12.12.111 `
        -SourceServerInstance am1-chrilumn-w1\sql2016 `
        -Databases AdventureWorks2016 `
        -RecoveryPoint latest `
        -TargetServerInstance am1-chrilumn-w1\sql2017 

    The above command will connect to the Rubrik Cluster of 172.12.12.111 and live mount the AdventureWorks2016 database on am1-chrilumn-w1\sql2016 to am1-chrlumn-w1-sql2017
    
.EXAMPLE
    PS C:\> .\Invoke-RubrikDatabaseMount.ps1 -RubrikServer amer1-rbk01 `
        -SourceServerInstance am1-chrilumn-w1\sql2016 `
        -Databases DB1, DB2, DB3, DB4, DB5, DB6 `
        -RecoveryPoint latest `
        -TargetServerInstance am1-chrilumn-w1\sql2017 

    The above command will connect to the Rubrik Cluster of 172.12.12.111 and live mount the list of databases database on am1-chrilumn-w1\sql2016 to am1-chrlumn-w1-sql2017
.INPUTS
    None except for parameters
.OUTPUTS
    None
.NOTES
    Name:               Live Mount SQL Server Databases Singularly or in Mass
    Created:            6/18/2020
    Author:             Chris Lumnah
    Execution Process:
        Before running this script, you need to create a credential file so that you can securly log into the Rubrik 
        Cluster. To do so run the below command via Powershell
        $Credential = Get-Credential
        $Credential | Export-CliXml -Path .\rubrik.Cred"
            
    The above will ask for a user name and password and them store them in an encrypted xml file.
   
#>
[cmdletbinding()]
param(
    [Parameter(Position=0)]
    [String]$RubrikServer,

    [Parameter(ParameterSetName='ServerInstance', Position=2)]
    [String]$SourceServerInstance,

    [Parameter(ParameterSetName='AvailabilityGroup', Position=2)]
    [String]$AvailabilityGroupName,

    [Parameter(Position=3)]
    [String[]]$Databases,

    [Parameter(Position=4)]
    [string]$RecoveryPoint,

    [Parameter(Position=5)]
    [String]$TargetServerInstance,

    [Parameter(ParameterSetName = 'CredentialFile')]
    [Parameter(ParameterSetName='ServerInstance')]
    [Parameter(ParameterSetName='AvailabilityGroup')]
    [string]$RubrikCredentialFile,

    [Parameter(ParameterSetName = 'Token')]
    [Parameter(ParameterSetName='ServerInstance')]
    [Parameter(ParameterSetName='AvailabilityGroup')]
    [string]$Token
) 
#region Required Modules for Script to run
#Requires -Modules Rubrik, SQLServer
Import-Module SQLServer
#endregion

#region Rubrik Connection
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
#endregion

#region Get information about the Source SQL Server
Write-Host "Get information about the SOURCE:$($SourceServerInstance)$($AvailabilityGroupName)" -ForegroundColor Green
switch ($PSBoundParameters.Keys) {
    'SourceServerInstance' {
        $GetRubrikSQLInstance = @{
            ServerInstance = $SourceServerInstance
        }
        $SourceInstanceId = (Get-RubrikSQLInstance @GetRubrikSQLInstance).id
    }
    'AvailabilityGroupName' {
        $GetRubrikAvailabilityGroup  = @{
            GroupName = $AvailabilityGroupName
        }
        $SourceAvailabilityGroupID = (Get-RubrikAvailabilityGroup @GetRubrikAvailabilityGroup).id
    }
    'Default' {"Default"}
}
#endregion

#region Get information about the Target SQL Server
Write-Host "Get information about the TARGET:$($TargetServerInstance)" -ForegroundColor Green
$GetRubrikSQLInstance = @{
    ServerInstance = $TargetServerInstance
}
$TargetRubrikSQLInstance = Get-RubrikSQLInstance @GetRubrikSQLInstance
#endregion
$SubmittedJobs = @()
foreach ($Database in $Databases){
    #region Get information about the Database
    switch ($PSBoundParameters.Keys) {
        'SourceServerInstance' {
            $GetRubrikDatabase = @{
                InstanceID = $SourceInstanceId
                Name = $Database
            }
        }
        'AvailabilityGroupName' {
            $GetRubrikDatabase = @{
                AvailabilityGroupID = $SourceAvailabilityGroupID
                Name = $Database
            }
        }
        'Default' {}
    }

    $RubrikDatabase =  Get-RubrikDatabase @GetRubrikDatabase | Where-Object {$_.isRelic -eq $false -and $_.isLiveMount -eq $false}
    #endregion
    #region Get Database Recovery Point Info
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
    #endregion
        
    #Check if the database already exists on the target instance
    $TargetDatabase = Get-RubrikDatabase -InstanceID $TargetRubrikSQLInstance.id -Name $RubrikDatabase.name | Where-Object {$_.isRelic -eq $false}
    $DatabaseName = $RubrikDatabase.name
    #If the database exists on the target instance, rename the Live Mount database name to include the recovery point
    if ([bool]($TargetDatabase.PSobject.Properties.name -match "id") -eq $true){
        $DatabaseName = $RubrikDatabase.name + '_' + $DatabaseRecoveryPoint.ToString("yyyyMMdd_HHmmss")
    }
    Write-Host "Submitting Live Mount Request of $($Database) from $($SourceServerInstance)$($AvailabilityGroupName) to $($TargetServerInstance) as $($DatabaseName)" -ForegroundColor Green
    $NewRubrikDatabaseMount = @{
        id = $RubrikDatabase.id 
        TargetInstanceId = $TargetRubrikSQLInstance.id
        MountedDatabaseName = $DatabaseName
        RecoveryDateTime = $DatabaseRecoveryPoint
    }
    $Job = New-RubrikDatabaseMount @NewRubrikDatabaseMount 
    $SubmittedJobs += $Job
}
foreach($Job in $SubmittedJobs){
    Get-RubrikRequest -id $Job.id -Type mssql -WaitForCompletion
}
