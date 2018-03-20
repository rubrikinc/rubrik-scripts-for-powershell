<#
    .SYNOPSIS
        Will scan a SQL Server for any database snapshots. Once it has that list, it will look for those databases in 
        Rubrik and unprotect them. 
    .DESCRIPTION
        Will scan a SQL Server for any database snapshots. Once it has that list, it will look for those databases in 
        Rubrik and unprotect them. 
    .PARAMETER ServerInstance
        ServerInstance name (combined hostname\instancename) if default instance, then hostname will suffice
    .PARAMETER RubrikServer
        The IP or FQDN of any available Rubrik node within the cluster
    .PARAMETER RubrikUserName
        Username with permissions to connect to the Rubrik cluster
    .PARAMETER RubrikPasswordFile
        Path to file containing an encrypted string that is the password for RubrikUserName

        If you need to create this file, use the below code

        $Credential = Get-Credential
        $Credential.Password | ConvertFrom-SecureString | Out-File "$($Credential.UserName).txt" -Force
        
    .INPUTS
        None

    .OUTPUTS
        None

    .EXAMPLE
        .\Unprotect-DatabaseSnapshotsInRubrik.ps1 -ServerName cl-SQL2016n1 -RubrikServer 172.21.8.31 -RubrikUserName chris.lumnah@rangers.lab -RubrikPasswordFile .\PasswordFile.txt

    .LINK
        None

    .NOTES
        Name:       Unprotct SQL Database Snapshots in Rubrik
        Created:    3/20/2018
        Author:     Chris Lumnah
        Execution Process:
            1. Use included script called Create-SecurePasswordFile.ps1 to create a file called Credential.txt. The 
                contents of this file will contain an encrypted string used as a password. The credential.txt file can
                only be used on the machine that Create-SecurePasswordFile.ps1 was run as the encryption method uses the 
                machine as part of the encryption process.
            2. Execute this script via the example above. 
#>
param(
    [Parameter(Mandatory=$true)]
    $ServerInstance,
    [Parameter(Mandatory=$true)]
    $RubrikServer,
    [Parameter(Mandatory=$true)]
    $RubrikUserName,
    [Parameter(Mandatory=$false)]
    $RubrikPasswordFile = ".\RubrikCredential.txt"
)
Import-Module SQLServer
Import-Module Rubrik

#Get all database snapshots
$Query = "select name from sys.databases where source_database_id is not null"
$Databases = Invoke-Sqlcmd -ServerInstance $ServerInstance -Query $Query

#Connect to Rubrik Cluster
$Password = Get-Content $RubrikPasswordFile | ConvertTo-SecureString
Connect-Rubrik -Server $RubrikServer -Username $RubrikUserName -Password $Password

#Find each snaoshot in Rubrik and unprotect them
foreach($Database in $Databases)
{
    Get-RubrikDatabase -Name $Database.name -ServerInstance $ServerInstance
    $RubrikDatabase = Get-RubrikDatabase -Name $Database.Name -ServerInstance $ServerInstance
    Protect-RubrikDatabase -id $RubrikDatabase.id -DoNotProtect -Confirm:$false
}
