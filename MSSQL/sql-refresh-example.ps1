#Load Rubrik Module
import-module Rubrik

#set credential to log in to Rubrik
$cred = Get-Credential 

#Connect to Rubrik server
Connect-Rubrik -Server '<Rubrik IP>' -Credential $cred -Verbose

#Export all dbs to another instance, no file relocation
$SourceServer = 'SERVERA'
$TargetServer = 'SERVERB'

$db = Get-RubrikDatabase -Hostname $SourceServer -Instance 'MSSQLSERVER' | Where-Object {@('master','model','msdb') -notcontains $_.Name -and $_.isRelic -ne 'True'}
$TargetInstanceID = (Get-RubrikDatabase -Hostname $TargetServer -Instance 'MSSQLSERVER' -Database 'master').instanceId

#If you need to drop databases before Export/Restore
$db.name | ForEach-Object {Invoke-Sqlcmd -ServerInstance $TargetServer -Database tempdb -Query 'DROP DATABASE $_;'}

#go ahead and run the export after a meta data refresh
New-RubrikHost $SourceServer
$requests = $db | Export-RubrikDatabase -RecoveryDateTime (Get-Date '2017-06-26T12:00:00') -TargetInstanceId $TargetInstanceID -WhatIf
#If the above -WhatIf output is good, replace -WhatIf with -Confirm:$false

$reqcount = ($requests | Where-Object {$_.status -ne 'SUCCEEDED'} | Measure-Object).Count
if($reqcount -eq 0){
    $db.name | ForEach-Object {Invoke-Sqlcmd -ServerInstance $TargetServer -Database tempdb -InputFile C:\SQLFiles\postexport.sql}
}


#To create live mounts, use this instead of the Export-RubrikDatabase
#only support in Rubrik 4.0
$db | New-RubrikDatabaseMount -RecoveryDateTime (Get-Date '2017-06-26T12:00:00') -TargetInstanceId $TargetInstanceID -MountedDatabaseName "$_`LM" -WhatIf

#To Execute post export/mount scripts
#capture outupt of Export-RubrikDatabase call, these are there the async requests
#you will want to check to see if all the requests are 'SUCCEEDED'

$reqcount = ($requests | Where-Object {$_.status -ne 'SUCCEEDED'} | Measure-Object).Count
if($reqcount -eq 0){
    $db.name | ForEach-Object {Invoke-Sqlcmd -ServerInstance $TargetServer -Database tempdb -InputFile C:\SQLFiles\postexport.sql}
}
