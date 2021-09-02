<#
.SYNOPSIS
    Remove the Live Mount a list of databases 
.DESCRIPTION
    Remove the Live Mount a list of databases from one SQL Server to another
.EXAMPLE
    PS C:\> .\Invoke-RubrikDatabaseUnMount.ps1 -RubrikServer 172.12.12.111 `
        -SourceServerInstance am1-chrilumn-w1\sql2016 `
        -Databases AdventureWorks2016 `
        -RecoveryPoint latest `
        -TargetServerInstance am1-chrilumn-w1\sql2017 

    The above command will connect to the Rubrik Cluster of 172.12.12.111 and remove the live mount the AdventureWorks2016 database on am1-chrilumn-w1\sql2016 to am1-chrlumn-w1-sql2017
    
.EXAMPLE
    PS C:\> .\Invoke-RubrikDatabaseUnMount.ps1 -RubrikServer amer1-rbk01 `
        -SourceServerInstance am1-chrilumn-w1\sql2016 `
        -Databases DB1, DB2, DB3, DB4, DB5, DB6 `
        -RecoveryPoint latest `
        -TargetServerInstance am1-chrilumn-w1\sql2017 

    The above command will connect to the Rubrik Cluster of 172.12.12.111 and remove the live mount the list of databases database on am1-chrilumn-w1\sql2016 to am1-chrlumn-w1-sql2017  
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
Import-Module Rubrik
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

foreach ($Database in $Databases){
    #region Get information about the Database
    Write-Host "Get information about the DATABASE:$($Database)" -ForegroundColor Green
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

    #Get the live Mount Info
    $GetRubrikDatabaseMount = @{
        SourceDatabaseID = $RubrikDatabase.id
        TargetInstanceID = $TargetRubrikSQLInstance.id
    }
    $DatabaseMount = Get-RubrikDatabaseMount @GetRubrikDatabaseMount

    Remove-RubrikDatabaseMount -id $DatabaseMount.id
}
