#
# Name:     check_last_backup_time.ps1
# Author:   Tim Hynes
# Use case: Checks snapshots are within compliance for their SLA domains (requires CSV input)
#
Import-Module Rubrik

function Get-RubrikSlaThreshold ($sla_id) {
    $sla = Get-RubrikSLA -PrimaryClusterId local -id $sla_id
    switch ($sla.frequencies[0].timeUnit) {
        "Hourly" {
            $sla_threshold = $(Get-Date).ToUniversalTime().AddHours(-$sla.frequencies[0].frequency)
        }
        "Daily" {
            $sla_threshold = $(Get-Date).ToUniversalTime().AddDays(-$sla.frequencies[0].frequency)
        }
    }
    return $sla_threshold
}

$rubrik_clusters = Get-ChildItem .\creds

$csv_path = '.\inventory.csv'

$non_compliant_objects = @()
[System.Collections.ArrayList]$object_array = Import-CSV $csv_path

# CSV should look like:
#
#   name,type
#   myvm01,VMwareVM
#   mysqldbhost,SQLserver
#   myphysicalhost,Fileset

foreach ($rubrik_cluster in $rubrik_clusters) {
    $objects_to_drop = @()
    $cred = Import-CliXml $(".\creds\"+$rubrik_cluster.ToString())
    Connect-Rubrik -Server $($rubrik_cluster.ToString() -replace '^(.*).creds$','$1') -Credential $cred | Out-Null
    foreach ($object in $object_array) {
        switch ($object.type)
        {
            "VMwareVM" {
                $rk_object = Get-RubrikVM -PrimaryClusterId local -Name $object.name
                if ($rk_object.name.Count -gt 0) {
                    if ($rk_object.effectiveSlaDomainId -ne 'UNPROTECTED') {
                        $sla_threshold = Get-RubrikSlaThreshold($rk_object.effectiveSlaDomainId)
                        $snapshot_list = $rk_object | Get-RubrikSnapshot | ? {$_.date -gt $sla_threshold}
                        if ($snapshot_list.Count -eq 0) {
                            $non_compliant_objects += $object
                        }
                        $objects_to_drop += $object
                    }
                }
            }
            "Fileset" {
                $rk_filesets = get-rubrikfileset -PrimaryClusterID local -Host $object.name
                if ($rk_filesets.name.Count -gt 0) {
                    foreach ($rk_fileset in $rk_filesets) {
                        if ($rk_fileset.effectiveSlaDomainId -ne 'UNPROTECTED') {
                            $sla_threshold = Get-RubrikSlaThreshold($rk_fileset.effectiveSlaDomainId)
                            $snapshot_list = ($rk_fileset | get-rubrikfileset).snapshots | ? {$_.date -gt $sla_threshold}
                            if ($snapshot_list.Count -eq 0) {
                                $non_compliant_objects += $object
                            }
                        }
                    }
                    $objects_to_drop += $object
                }
            }
            "SQLServer" {
                $rk_sqldbs = get-rubrikdatabase -PrimaryClusterID local -Hostname $object.name
                if ($rk_sqldbs.name.Count -gt 0) {
                    foreach ($rk_sqldb in $rk_sqldbs) {
                        if ($rk_sqldb.effectiveSlaDomainId -ne 'UNPROTECTED') {
                            $sla_threshold = Get-RubrikSlaThreshold($rk_sqldb.effectiveSlaDomainId)
                            $snapshot_list = $rk_sqldb | Get-RubrikSnapshot | ? {$_.date -gt $sla_threshold}
                            if ($snapshot_list.Count -eq 0) {
                                $non_compliant_objects += $object
                            }
                        }
                    }
                    $objects_to_drop += $object
                }
            }
        }
    }
    Disconnect-Rubrik -Confirm:$false
    for ($i = 0; $i -lt $objects_to_drop.count; $i++) {
        $object_array.Remove($objects_to_drop[$i])
    }
}

Write-Output "NON COMPLIANT"
$non_compliant_objects

Write-Output "NOT FOUND"
$object_array