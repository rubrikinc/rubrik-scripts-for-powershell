<#
    .SYNOPSIS
        Will create a new snapshot of a fileset on a server
    .DESCRIPTION
    .PARAMETER Server
        IP address or DNS name to Rubrik Cluster
    .PARAMETER FileSetName
        Name of the Fileset created in Rubrik
    .PARAMETER HostName
        Name of the server that will be backed up
    .PARAMETER SLADomain
        Name of the SLA Domain
    .PARAMETER CredentialFile
        Path and filename of encrypted credential file
    .INPUTS
        None
    .OUTPUTS
        SUCCESS is a boolean value. $True if snapshot is successfull and $false if not. 
    .EXAMPLE
        .\New-FileSetSnapshot.ps1 -Server 172.21.8.51 -FileSetName 'Ola Hallengren SQL Backup Files' -HostName cl-sql2012n1.rangers.lab' -SLADomain 'SQL User Databases' -CredentialFile .\CredentialFile.Cred
    .LINK
        None
    .NOTES
        Name:       New FIle Set Snapshot
        Created:    5/2/2018
        Author:     Chris Lumnah
        Execution Process:
            1. Before running this script, you need to create a credential file so that you can securly log into the Rubrik 
            Cluster. To do so run the below command via Powershell

            $Credential = Get-Credential
            $Credential | Export-CliXml -Path .\rubrik.Cred"
            
            The above will ask for a user name and password and them store them in an encrypted xml file.
            
            2. Execute this script via the example above. 



#>
param
(
    [Parameter(Mandatory=$true,HelpMessage="IP address or DNS name to Rubrik Cluster")]
    [string]$RubrikServer,

    [Parameter(Mandatory=$true,HelpMessage="Name of the Fileset created in Rubrik")]
    [string]$FileSetName,

    [Parameter(Mandatory=$true,HelpMessage="Name of the server that will be backed up")]
    [string]$HostName,

    [Parameter(Mandatory=$true,HelpMessage="Name of the SLA Domain")]
    [string]$SLADomain,

    [Parameter(ParameterSetName = 'CredentialFile',HelpMessage="Path and filename of encrypted credential file")]
    [string]$RubrikCredentialFile,
    [Parameter(ParameterSetName = 'Token')]
    [string]$Token
)

Import-Module Rubrik
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

$RubrikFileSet = Get-RubrikFileset -Name $FileSetName -HostName $HostName | Where-Object {$_.isRelic -eq $false}

$RubrikRequest = New-RubrikSnapshot -id $RubrikFileSet.id -SLA $SLADomain -Confirm:$false

$Request = Get-RubrikRequest -id $RubrikRequest.id -Type fileset -WaitForCompletion

$Request

#We now return back the full $RubrikRequest Information. This should be evaluated now for the status to determine if the script
#is successfull or not. A Failed status is NOT a failed script. It is a failed fileset backup in Rubrik. If you see failure, you 
#should then decide what is the next appropriate step in your workflow. 
# $Request.status
