param($ServerInstance
      ,$RubrikServer
      ,$RubrikCredential = (Get-Credential -Message 'Please enter your Rubrik credentials')
      )

#Parse ServerInstance 
if($ServerInstance -contains '\'){
    $HostName = ($ServerInstance -split '\')[0]
    $InstanceName = ($ServerInstance -split '\')[1]
} else {
    $HostName = $ServerInstance
    $InstanceName = 'MSSQLSERVER'
}

#Connect to the Rubrik Cluster
Connect-Rubrik -Server $RubrikServer -Credential $RubrikCredential

$dbs = Get-RubrikDatabase -Hostname $HostName -Instance $InstanceName | Get-RubrikDatabase | Where-Object {$_.isrelic -ne 'TRUE' -and $_.isLiveMount -ne 'TRUE'}

$dbs = $dbs | Select-Object name,recoveryModel,effectiveSLADomainName,latestRecoveryPoint,id | 
    Sort-Object name | 
    Out-GridView -PassThru 
    
$requests = $dbs | New-RubrikSnapshot -Inherit -Confirm:$False

return $requests 