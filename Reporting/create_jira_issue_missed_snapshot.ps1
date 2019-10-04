# Import our modules
# These can be imported using Install-Module JiraPS and Install-Module Rubrik
Import-Module JiraPs
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
$rubrik_ip = 'rubrik.demo.com'
$jira_server = 'https://myjirainstance.atlassian.net'
$jira_project = 'PRO'
# Connect to Jira
Set-JiraConfigServer $jira_server
New-JiraSession
# Connect to Rubrik
Connect-Rubrik -Server $rubrik_ip
# Get our report and throw the data in an object
$report_data = Get-RubrikReport -Name 'SLA Compliance Summary' | Get-RubrikReportData -ComplianceStatus 'NonCompliance'
$report_data_obj = @()
foreach ($report_data_set in $report_data.dataGrid) {
    $new_line = "" | Select-Object $report_data.columns
    for ($i = 0; $i -lt $report_data.columns.Count; $i++) {
        $new_line.$($report_data.columns[$i]) = $report_data_set[$i]
    }
    $report_data_obj += $new_line
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
        # Return only missed snapshots for the last 48 hours
        if ($snapshot_time -gt $(get-date).AddHours(-48)) { $recent_missed += $snapshot_time }
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
        # Return only successful snapshots for the last 48 hours
        if ($snapshot_time -gt $(get-date).AddHours(-48) -and $successful_snapshots[$i].isOnDemandSnapshot -ne '1') { $recent_snaps += $snapshot_time }
    }
    $snappable.SuccessfulSnapshotDetail = $recent_snaps
}
foreach ($snappable in $report_data_obj) {
    if ($snappable.MissedSnapshotDetail.Count -gt 1) {
        $description = @"
Rubrik backup job was missed in the last 48 hours for object "$($snappable.ObjectName)" (Rubrik type: $($snappable.ObjectType)) at the following times:
$([system.String]::Join("`n`r",$snappable.MissedSnapshotDetail))
"@
        New-JiraIssue -Project $jira_project -IssueType (Get-JiraIssueType -Name 'Incident').id`
         -Summary $('Failed Rubrik Backup Job - '+$snappable.ObjectName+' - Missed snapshots - '+$snappable.MissedSnapshotDetail.Count)`
         -Description $description
    }
}
