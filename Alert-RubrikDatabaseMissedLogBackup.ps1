<#
.SYNOPSIS
Alert-RubrikDatabaseMissedLogBackup.ps1 is used to alert DBAs to potentially missed database backups

.DESCRIPTION
Script will run against a Rubrik Cluster and return back all databases that Rubrik knows about. The database list is filtered 
to be databases not in SIMPLE recovery mode, not live mounts, protected databases, and databases that are not relics.
We will then take that list of databases and compare the latest recovery point and the date as of now to see if the latest recovery
point is within the transaction log backup frequency. 

.PARAMETER RubrikServer
IP address or the name of the Rubrik Server we should connect to

.PARAMETER RubrikCredentialFile
Full path and file name of the credential file to be used to authenticate to the Rubrik server. 

.EXAMPLE
Run script with a credential file for automated, scheduled processing
.\Alert-RubrikDatabaseMissedLogBackup.ps1 -RubrikServer 172.15.278.300 -RubrikCredentialFile "C:\temp\Rubrik.credential"

.EXAMPLE 
Run script without a credential file. Script will then ask you to supply a user ID and password via a prompt
.\Alert-RubrikDatabaseMissedLogBackup.ps1 -RubrikServer 172.15.278.300 

.NOTES
        Name:       Alert on missed database transaction log backups
        Created:    7/31/2018
        Author:     Chris Lumnah
        Execution Process:
            1. Use included script called Create-SecurePasswordFile.ps1 to create a file called Credential.txt. The 
                contents of this file will contain an encrypted string used as a password. The credential.txt file can
                only be used on the machine that Create-SecurePassword
            2. Execute this script via the example above. 
            3. From a Windows Powershell Administrative Shell run
                New-EventLog -Source Rubrik -LogName Application
#>

param
(
    # Rubrik Server IP or Name
    [Parameter(Mandatory=$true,Position=0)]
    [string]$RubrikServer,
    # Credential file that will be used to log in to Rubrik Server
    [Parameter(Mandatory=$false,Position=1)]
    [string]$RubrikCredentialFile
)
Import-Module Rubrik

if ($RubrikCredentialFile)
{
    $RubrikCredential = Import-CliXml -Path $RubrikCredentialFile
}
else 
{
    $RubrikCredential = Get-Credential    
}

#Connect to Rubrik
Connect-Rubrik -Server $RubrikServer -Credential $RubrikCredential | Out-Null

#Lets get all of the databases in Rubrik
$RubrikDatabases = Get-RubrikDatabase

$EndDate = Get-Date

#We need to limit the database list to be just databases that are not live mounts, in bulked-logged or full 
#recovery mode, protected via some SLA Domain, and is not a relic. This gives all databases that are on any host
#including those in an availability group. 
foreach($RubrikDatabase in $RubrikDatabases | `
    Where-Object {$_.isLiveMount -ne "true" -and `
        $_.recoveryModel -ne "SIMPLE" -and `
        $_.effectiveSlaDomainName -ne "Unprotected" -and `
        $_.isrelic -ne "true" })
{
    #The logic here is get the latest recovery point of the database. If there is no date, then that means we do 
    #not have a valid recovery point to roll back to. We need to flag this as an error and log this as such in 
    #the application log
    try 
    {
        $LatestRecoveryPoint = (Get-date (Get-RubrikDatabase -id $RubrikDatabase.id).latestRecoveryPoint)    
        $StartDate = $LatestRecoveryPoint.DateTime
    }
    catch 
    {
        $Message = "Host Name: $($RubrikDatabase.rootproperties.rootName)" 
        $Message = $Message + "`nInstance Name: $($RubrikDatabase.InstanceName)"
        $Message = $Message + "`nDatabase Name: $($RubrikDatabase.Name)"
        $Message = $Message + "`nThere is no valid recovery point"
        $Message = $Message + "`nTransaction Log Backup should happen every: $($RubrikDatabase.logBackupFrequencyInSeconds) seconds"

        Write-EventLog -LogName "Application" `
            -Source "Rubrik" `
            -EntryType "Error" `
            -EventId 54322 `
            -Message $Message
    }

    #Get the difference in time from the latest recovery point and now
    $TimeSpan = New-TimeSpan -Start  $StartDate -End $EndDate
    
    $Message = ""
    #We are checking to see if the difference in time from the latest recovery point and now is greater 
    #than the log frequency. If we find this, then we will log a warning in the application log. 
    If ($TimeSpan.TotalSeconds -gt $RubrikDatabase.logBackupFrequencyInSeconds)
    {
        $Message = "Host Name: $($RubrikDatabase.rootproperties.rootName)" 
        $Message = $Message + "`nInstance Name: $($RubrikDatabase.InstanceName)"
        $Message = $Message + "`nDatabase Name: $($RubrikDatabase.Name)"
        $Message = $Message + "`nLatest Recovery Point DateTime: $($LatestRecoveryPoint)"
        $Message = $Message + "`nTransaction Log Backup should happen every: $($RubrikDatabase.logBackupFrequencyInSeconds) seconds"

        Write-EventLog -LogName "Application" `
            -Source "Rubrik" `
            -EntryType "Warning" `
            -EventId 54321 `
            -Message $Message
    }
}