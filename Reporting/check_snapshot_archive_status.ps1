#
# Name:     check_snapshot_archive_status.ps1
# Author:   Tim Hynes
# Use case: Reports on snapshots which have not been archived to the expected archive target
#
Import-Module Rubrik

$rubrik_clusters = Get-ChildItem .\creds

$non_cloud_snapshots = @()

foreach ($rubrik_cluster in $rubrik_clusters) {
    $cred = Import-CliXml $(".\creds\"+$rubrik_cluster.ToString())
    Connect-Rubrik -Server $($rubrik_cluster.ToString() -replace '^(.*).creds$','$1') -Credential $cred | Out-Null
    # VMware VMs
    $all_vms = Get-RubrikVM -PrimaryClusterId local
    foreach ($vm in $all_vms) {
        $snapshot_list = $vm | Get-RubrikSnapshot | ?{$_.date -gt $(Get-Date).AddHours(-24) -and $_.cloudState -eq 0}
        if ($snapshot_list.Count -gt 0) {
            $non_cloud_snapshots += @{
                "objectName" = $vm.Name
                "clusterName" = $rubrik_ip
                "slaDomain" = $vm.effectiveSlaDomainName
                "objectType" = "VMware VM"
                "snapshots" = $snapshot_list.date
            }
        }
    }
    # Filesets
    $all_filesets = Get-RubrikFileset -PrimaryClusterId local
    foreach ($fileset in $all_filesets) {
        $snapshot_list = ($fileset | get-rubrikfileset).snapshots | ?{$_.date -gt $(Get-Date).AddHours(-24) -and $_.cloudState -eq 0}
        if ($snapshot_list.Count -gt 0) {
            $non_cloud_snapshots += @{
                "objectName" = $fileset.Name
                "instanceName" = $sql_db.InstanceName
                "hostName" = $fileset.hostName
                "clusterName" = $rubrik_ip
                "slaDomain" = $mv.effectiveSlaDomainName
                "objectType" = "Fileset"
                "snapshots" = $snapshot_list.date
            }
        }
    }
    # SQL DBs
    $all_sql_dbs = Get-RubrikDatabase -PrimaryClusterId local
    foreach ($sql_db in $all_sql_dbs) {
        $snapshot_list = $sql_db | Get-RubrikSnapshot | ?{$_.date -gt $(Get-Date).AddHours(-24) -and $_.cloudState -eq 0}
        if ($snapshot_list.Count -gt 0) {
            $non_cloud_snapshots += @{
                "objectName" = $sql_db.Name
                "instanceName" = $sql_db.InstanceName
                "hostName" = $sql_db.rootProperties.rootName
                "clusterName" = $rubrik_ip
                "slaDomain" = $mv.effectiveSlaDomainName
                "objectType" = "SQL Server Database"
                "snapshots" = $snapshot_list.date
            }
        }
    }
    # Managed Volumes
    $all_mvs = Get-RubrikManagedVolume -PrimaryClusterId local
    foreach ($mv in $all_mvs) {
        $snapshot_list = $mv | Get-RubrikSnapshot | ?{$_.date -gt $(Get-Date).AddHours(-24) -and $_.cloudState -eq 0}
        if ($snapshot_list.Count -gt 0) {
            $non_cloud_snapshots += @{
                "objectName" = $mv.Name
                "clusterName" = $rubrik_ip
                "slaDomain" = $mv.effectiveSlaDomainName
                "objectType" = "Managed Volume"
                "snapshots" = $snapshot_list.date
            }
        }
    }

    Disconnect-Rubrik -Confirm:$false
}

$non_cloud_snapshots