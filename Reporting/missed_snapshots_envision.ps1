Import-Module Rubrik
# New functions to get only missed snapshots
function Get-RubrikVmwareMissedSnapshot ($vm_id) {
    $uri = 'vmware/vm/'+$vm_id+'/missed_snapshot'
    $method = 'GET'
    $response = Invoke-RubrikRESTCall -Endpoint $uri -Method $method
    Return $response
}
function Get-RubrikFilesetMissedSnapshot ($fileset_id) {
    $uri = 'fileset/'+$fileset_id+'/missed_snapshot'
    $method = 'GET'
    $response = Invoke-RubrikRESTCall -Endpoint $uri -Method $method
    Return $response
}
function Get-RubrikSqlDbMissedSnapshot ($sqldb_id) {
    $uri = 'mssql/db/'+$sqldb_id+'/missed_snapshot'
    $method = 'GET'
    $response = Invoke-RubrikRESTCall -Endpoint $uri -Method $method
    Return $response
}

# Variables
$rubrik_ip = 'notacluster.rubrik.com'
$rubrik_cred = Get-Credential
Connect-Rubrik -Server $rubrik_ip -Credential $rubrik_cred
# Declare Arrays for use
$csv_data = @()

# Get our report and throw the data in an object
$report_id = Get-RubrikReport -Name 'SLA Compliance Summary' | select -expand id
$report_query = @{limit = 100}
$report_data_obj = @()
$has_more = $true
while ($has_more -eq $true) {
    if ($cursor -ne $null) {
        $report_query['cursor'] = $cursor
    }
    $headers = @{
        Accept = 'application/json'
    }
    $report_response = Invoke-WebRequest -Uri $("https://"+$rubrik_ip+"/api/internal/report/"+$report_id+"/table") -Headers $headers -Method POST -Body $(ConvertTo-Json $report_query) -Credential $rubrik_cred
    $report_data = $report_response.Content | ConvertFrom-Json
    $has_more = $report_data.hasMore
    $cursor = $report_data.cursor
    foreach ($report_entry in $report_data.dataGrid) {
        $row = '' | select $report_data.columns
        for ($i = 0; $i -lt $report_entry.count; $i++) {
            $row.$($report_data.columns[$i]) = $($report_entry[$i])
        }
        $report_data_obj += $row
    }
}
# Add two new columns to our array
$report_data_obj | Add-Member -NotePropertyName MissedSnapshotDetail -NotePropertyValue @()
$report_data_obj | Add-Member -NotePropertyName SuccessfulSnapshotDetail -NotePropertyValue @()
# For each object we need to identify its recent snapshots, failed or successful


foreach ($snappable in $report_data_obj) {
    switch ($snappable.ObjectType) {
        "VmwareVirtualMachine" { $missed_snapshots = Get-RubrikVmwareMissedSnapshot $snappable.ObjectId }
        "LinuxFileset" { $missed_snapshots = Get-RubrikFilesetMissedSnapshot $snappable.ObjectId }
        "ManagedVolume" { $missed_snapshots = @{} }
        "Mssql" { $missed_snapshots = Get-RubrikSqlDbMissedSnapshot $snappable.ObjectId }
        "WindowsFileset" { $missed_snapshots = Get-RubrikFilesetMissedSnapshot $snappable.ObjectId }
    }
    $recent_missed = @()
    for ($i = 0; $i -lt $missed_snapshots.total; $i++) {
        $snapshot_time = [datetime]$missed_snapshots.data[$i].missedSnapshotTime
        # Return only missed snapshots for the last 24 hours
        if ($snapshot_time -gt $(get-date).AddHours(-24)) { $recent_missed += $snapshot_time }
    }
    $snappable.MissedSnapshotDetail = $recent_missed
    $recent_snaps = @()
    switch ($snappable.ObjectType) {
        "VmwareVirtualMachine" { $successful_snapshots = get-rubrikvm -id $snappable.ObjectId | Get-RubrikSnapshot }
        "LinuxFileset" { $successful_snapshots = (get-rubrikfileset -id $snappable.ObjectId).snapshots }
        "ManagedVolume" { $successful_snapshots = @{} }
        "Mssql" { $successful_snapshots = get-rubrikdatabase -id $snappable.ObjectId | Get-RubrikSnapshot }
        "WindowsFileset" { $successful_snapshots = (get-rubrikfileset -id $snappable.ObjectId).snapshots }
    }
    for ($i = 0; $i -lt $successful_snapshots.count; $i++) {
        $snapshot_time = [datetime]$successful_snapshots[$i].date
        # Return only successful snapshots for the last 24 hours
        if ($snapshot_time -gt $(get-date).AddHours(-24) -and $successful_snapshots[$i].isOnDemandSnapshot -ne '1') { $recent_snaps += $snapshot_time }
    }
    $snappable.SuccessfulSnapshotDetail = $recent_snaps
}


foreach ($snappable in $report_data_obj) {
    
    if ($snappable.MissedSnapshotDetail.Count -gt 1) {
        $csv_data+=New-Object PSObject -Property @{ObjectId=$snappable.ObjectId;ObjectName=$snappable.ObjectName;ObjectType=$snappable.ObjectType;ObjectState=$snappable.ObjectState;Location=$snappable.Location;SlaDomain=$snappable.SlaDomain;ComplianceStatus=$snappable.ComplianceStatus;misssedSnapshotDetail=$([system.String]::Join("`n`r",$snappable.MissedSnapshotDetail))}
    }
}
write-host "Outputted CSV file to current Directory: $(Get-Location)\rubrik_backup_sla_misssed_snapshots.csv"
$csv_data | export-csv .\rubrik_backup_sla_misssed_snapshots.csv -notype -Force
write-host "Script Completed - An Empty CSV indicates no missed snapshots!"