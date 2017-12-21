param( [String[]] $databases
        ,[String] $SourceServerInstance
        ,[String] $TargetServerInstance
        )


function ConvertFrom-ServerInstance($ServerInstance) {
    if($ServerInstance -contains '\'){
        $si = $ServerInstance -split '\'
        $return = New-Object psobject -Property @{'hostname'= $si[0];'instancename'=$si[1]}
    } else {
        $return = New-Object psobject -Property @{'hostname'= $ServerInstance;'instancename'='MSSQLSERVER'}
    }
    return $return
}

function Wait-RubrikRequests($reqs) {
    do{
        Start-Sleep -Seconds 15
        $reqs = $reqs | Get-RubrikRequest -Type mssql -ErrorAction SilentlyContinue
    }until(($reqs | Where-Object {@('QUEUED','RUNNING','FINISHING') -contains $_.status} | Measure-Object).Count -eq 0)
}

$source = ConvertFrom-ServerInstance $SourceServerInstance
$TargetInstance = (Get-RubrikSQLInstance -ServerInstance $TargetServerInstance)

"Begining unmount/cleanup process for: $($databases -join ",")" | Out-Host
$unmount_reqs = Get-RubrikDatabaseMount -TargetInstanceId $TargetInstance.id | 
    Where-Object {$databases -contains $_.sourceDatabaseName} |
    Remove-RubrikDatabaseMount -Confirm:$false 

if($unmount_reqs) {Wait-RubrikRequests $unmount_reqs}

"Begining mount process for: $($databases -join ",")" | Out-Host
$mount_reqs = Get-RubrikDatabase -Hostname $source.hostname -Instance $source.instance |
    Where-Object {$databases -contains $_.Name} | 
    ForEach-Object{$date = Get-RubrikSnapshot -id $_.id -Date (Get-Date); New-RubrikDatabaseMount -TargetInstanceId $TargetInstance.id -MountedDatabaseName "$($_.name)_LM" -RecoveryDateTime $date.date -id $_.id -confirm:$false}

if($mount_reqs) {Wait-RubrikRequests $mount_reqs}