#
# Name:     get_failed_backup.ps1
# Author:   Tim Hynes
# Use case: Provides an list of missed backups in the last 12 hours (defined by $time_period_hours)
#
Import-Module Rubrik
# Functions
function Convert-RubrikTimeStamp($datestring) {
    # We need to convert the timestamp delivered by the Rubrik API (Fri Sep 29 06:09:09 UTC 2017), to something PowerShell can work with
    $split = $datestring.split(" ")
    $date = [datetime]$($split[2]+' '+$split[1]+' '+$split[-1]+' '+$split[3])
    return $date
}
# Define all our clusters here:
$rubrik_clusters = @{
    'cluster-1' = @{
        'ip' = '192.168.1.100';
        'user' = 'admin';
        'pass' = 'MyP@55!'
    };
    'cluster-2' = @{
        'ip' = '192.168.2.100';
        'user' = 'admin';
        'pass' = 'MyP@55!'
    };
}
# Define how many hours to search back through
$time_period_hours = 12
# User selects a cluster
$selected_cluster_name = $rubrik_clusters.keys.split("") | out-gridview -Title 'Select Rubrik Cluster' -PassThru
$selected_cluster = $rubrik_clusters[$selected_cluster_name]
# Connect to selected cluster
Connect-Rubrik -Server $selected_cluster.ip -Username $selected_cluster.user `
    -Password $(ConvertTo-SecureString -String $selected_cluster.pass -AsPlainText -Force) | Out-Null
# Run query for missed jobs
$missed_jobs = @()
$timestamp = $($(Get-Date).ToUniversalTime().AddHours(-$time_period_hours) | get-date -format s) + 'Z'
$events = Invoke-RubrikRestCall -Endpoint $('event/latest?limit=9&after_date='+$timestamp+'&event_type=Backup&event_status=Failure') -Method GET -api 1
$events.data.latestevent | % {
    #$this_event_timestamp = Convert-RubrikTimeStamp($_.time)
    $newer_events = Invoke-RubrikRestCall -Endpoint $('event/latest?after_date='+$($($($_.time).ToUniversalTime().AddSeconds(1) | get-date -format s) + 'Z')+'&event_type=Backup&object_ids='+$_.time) -Method GET -api 1
    # Check if we have any newer events
    $all_ok = $false
    if ($newer_events.data) {
        $newer_events.data | % { if ($_.eventStatus -in @('Success')) { $all_ok = $true } }
    }
    if (-not $all_ok) {
        $event_info = $_.eventInfo | ConvertFrom-JSON
        $row = '' | select time,objectName,objectType,message,locationName
        $row.time = $_.time
        $row.objectName = $_.objectName
        $row.objectType = $_.objectType
        $row.message = $event_info.message
        $row.locationName = $event_info.params.'${locationName}'
        $missed_jobs += $row
    }
}
Disconnect-Rubrik -Confirm:$false | Out-Null

$missed_jobs | Out-GridView -Title 'Missed Backup Jobs'