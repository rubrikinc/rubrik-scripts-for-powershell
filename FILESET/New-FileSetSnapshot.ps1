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
    [string]$Server,

    [Parameter(Mandatory=$true,HelpMessage="Name of the Fileset created in Rubrik")]
    [string]$FileSetName,

    [Parameter(Mandatory=$true,HelpMessage="Name of the server that will be backed up")]
    [string]$HostName,

    [Parameter(Mandatory=$true,HelpMessage="Name of the SLA Domain")]
    [string]$SLADomain,

    [Parameter(Mandatory=$true,HelpMessage="Path and filename of encrypted credential file")]
    [string]$CredentialFile
)

Import-Module Rubrik
$Credential = Import-CliXml -Path $CredentialFile
Connect-Rubrik -Server $Server -Credential $Credential | Out-Null

$RubrikFileSet = Get-RubrikFileset -Name $FileSetName -HostName $HostName

$RubrikRequest = New-RubrikSnapshot -id $RubrikFileSet.id -SLA $SLADomain -Confirm:$false

#Evaluate the request. Based on the status of the Async request, we will show the progress. We will exit if failure or success
#If failure, we return false, but success we return true
do
{
    $exit = $false
    $success=$false
    $Request = Get-RubrikRequest -id $RubrikRequest.id -Type 'fileset'

    switch -Wildcard ($Request.status) 
    {
        'QUE*' {Write-Progress -Activity "Backup up fileset $FileSetName on $HostName" -Status $Request.status -percentComplete (0)}
        'RUN*' 
        {
            if ([string]::IsNullOrEmpty($Request.progress)){$PercentComplete = 0} else {$PercentComplete = $Request.progress}
            Write-Progress -Activity "Backup up fileset $FileSetName on $HostName" -Status $Request.status -percentComplete $PercentComplete
        }
        'SUCCEED*' 
        {
            $exit = $true 
            $success = $true
        }
        'FAIL*' 
        {
            $exit = $true 
            $success = $false
        }
    }
}until ($exit -eq $true)

$success
