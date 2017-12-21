param(
    $VMFolder
    ,$SnapshotSLA
)

$vms = Get-RubrikVM | Where-Object {$_.FolderPath.Name -eq $VMFolder}

$reqs = $vms.id | ForEach-Object {New-RubrikSnapshot -id $_ -SLA $SnapshotSLA -Confirm:$false}

return $reqs