# This code is not meant to be used for production. This is test code to determine if all of the backups for a given database have replicated to a secondary brik
# Based on current knowledge, I believe this may be the most effective way to determine that the latest round of backups have all been replicated from Brik 1 to 
# Brik 2. The notion here, is that we take the most recent snapshot and look at the latest recovery point. The two briks should match and there should be no holes in the 
# recoverable range. If there are, then that means we do not have a complete set of backups on the second brik. 
# Name:       Check Rubrik Database Replication
# Created:    11/25/2019
# Author:     Chris Lumnah

import-module Rubrik -Force
$ConnectRubrik = @{
    Server = $RubrikCluster.amer1
    Token  = $Credentials.APIToken.amer1
}

Connect-Rubrik @ConnectRubrik | Out-Null

$Brik_1_GetRubrikDatatabase = @{
    HostName         = 'am1-sql16-1'
    Name             = 'stackoverflow'
    PrimaryClusterID = 'local'
    #DetailedObject = $true
}

$SourceDatabase = Get-RubrikDatabase @Brik_1_GetRubrikDatatabase 
$LastSnapshot = (Get-RubrikSnapshot -id $SourceDatabase.id | Sort-Object date -Descending | Select-object -First 1).date



$SourceRecoverableRange = Get-RubrikDatabaseRecoverableRange -id $SourceDatabase.id -StartDateTime $LastSnapshot



$ConnectRubrik = @{
    Server     = $RubrikCluster.amer2
    Credential = $Credentials.Gaia
}
Connect-Rubrik @ConnectRubrik | Out-Null

$TargetRecoverableRange = Get-RubrikDatabaseRecoverableRange -id $SourceDatabase.id -StartDateTime $LastSnapshot



$Compare = Compare-Object -ReferenceObject $SourceRecoverableRange -DifferenceObject $TargetRecoverableRange -IncludeEqual -Property endTime
$Compare.SideIndicator
if ($Compare.SideIndicator -eq "==") {
    Write-Host "DO EXPORT TO TARGET"
}
else {
    Write-Host "REPLICATION HASN'T FINISHED, WAIT ON EXPORT"
    $SourceRecoverableRange | Format-Table *
    $TargetRecoverableRange | Format-Table *
}
