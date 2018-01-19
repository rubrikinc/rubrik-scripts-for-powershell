#Get data
Get-RubrikDatabase | Get-Member
Get-RubrikDatabase | Format-Table name,effectiveSlaDomainName,isRelic,isLiveMount -AutoSize

Get-RubrikDatabase -Hostname msfsql16-poc-01 | 
    Where-Object {$_.isRelic -ne 'TRUE' -and $_.isLiveMount -ne 'TRUE'} | 
    Sort-Object Name | 
    Format-Table name,effectiveSlaDomainName

(Get-RubrikDatabase -Hostname msfsql16-poc-01)[0] | 
    Get-RubrikDatabase | Get-Member

Get-RubrikDatabase -Hostname msfsql16-poc-01 | 
    Where-Object {$_.isRelic -ne 'TRUE' -and $_.isLiveMount -ne 'TRUE'} | 
    Get-RubrikDatabase |
    Sort-Object Name | 
    Format-Table name,effectiveSlaDomainName,@{n='LatestRecoveryTime';e={Get-Date $_.latestRecoveryPoint}},recoveryModel,logBackupFrequencyInSeconds

Get-RubrikDatabase -Hostname msfsql16-poc-01 | 
    Where-Object {$_.isRelic -ne 'TRUE' -and $_.isLiveMount -ne 'TRUE'} |
    Get-RubrikSnapshot -Date (Get-Date) | 
    Sort-Object Name | Format-Table databaseName,@{n='SnapshotDate';e={Get-Date $_.date}} -AutoSize