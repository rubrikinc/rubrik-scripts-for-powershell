param($ServerInstance)

#Parse ServerInstance 
if($ServerInstance -contains '\'){
    $HostName = ($ServerInstance -split '\')[0]
    $InstanceName = ($ServerInstance -split '\')[1]
} else {
    $HostName = $ServerInstance
    $InstanceName = 'MSSQLSERVER'
}

$dbs = Get-RubrikDatabase -Hostname $HostName -Instance $InstanceName | Get-RubrikDatabase | Where-Object {$_.isrelic -ne 'TRUE' -and $_.isLiveMount -ne 'TRUE'}

$dbs = $dbs | Select-Object name,recoveryModel,effectiveSLADomainName,latestRecoveryPoint,id | 
    Sort-Object name | 
    Out-GridView -PassThru 
    
$requests = $dbs | ForEach-Object{New-RubrikSnapshot -id $_.id -SLA $_.effectiveSLADomainName -Confirm:$False}

return $requests 