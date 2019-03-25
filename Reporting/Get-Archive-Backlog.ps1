4<#
    .SYNOPSIS
        Will look for snapshots that have not been archived with in the archive threshold. 

    .DESCRIPTION
        This script will report on snapshots that have not been archived with in the archive threshold. It
        does this by querying SLAs that have archiving enabled. It then looks for any snapshots that have 
        been created before the archive threshold. The archive threshold is what the On-Brik slider is set
        to in the SLA Domain settings. If Instant Archive is enabled the archive threshold is set to 1 second.

        There is an option to set the archive threshold to a custom value for reporting purposes. This value 
        is represented in the number of seconds in the past from the current time. For example if querying for
        snapshots that should have been archived 10 days or more ago the -Age flag would be set to 864000.
        (10*24*3600)

        The Rubrik clusters to query are based on either command line inputs or the credentials files that are
        created for each cluster. 

    .INPUTS
        IP address(es) or hostname(s) of each Rubrik CLuster
        Rubrik Username
        Rubrik Password
        SLA Name(s) (Optional)
        Maximum Snapshot Age (Optional)

    .OUTPUTS
        Report of snapshots that have not been archived prior to the archive threshold. 

    .EXAMPLE
        All SLAs with archiving enabled. Archive threshold based on the SLAs On-Brik slider and Instant Archive settings:
        .\archive_backlog.ps1

        Individual SLA on a two Rubrik Cluster overriding the the oldest snapshot to look for to 30 days ago:
        .\archive_backlog.ps1 -RubrikClusters "192.168.1.10 192.168.1.15" -SLAs Gold -Age 30

    .LINK
        None

    .NOTES
        Name:       Archive Backlog 
        Created:    01/14/2019
        Author:     Tim Haynes
        Updated:    02/28/2019
        Updater:    Damani Norman
        Updates:

        1. Improved the output formatting and fields
        2. Made the clusters that are included in the report selectable
        3. Made it query the SLAs and report based on the actual On Brik slider
        4. Made it query either selected or all SLAs.
        5. Made it only report on SLAs that have archiving enabled.
        6. Gave an option to filer on snapshot age so older snapshots could be filtered out. 
        7. Filtered out some false positives like Snapshots that didn't have an SLA assigned. 
        8. Added support for Hyper-V VMs, Nutanix VMs.
        9. Broke out NAS vs OS based systems from Filesets.
        10. Added check and inclusion of empty cloudStates

        Execution Process:

            1. Install the Rubrik PowerShell Module

            Install-Module Rubrik

            NOTE: A specific minimum version of the Rubrik PowerShell module is required. Verify that the correct
                  version is installed with the command "Get-Module Rubrik". If not remove and reinstall the 
                  correct version. 

            1. Before running this script, you need to create one or more credential file(s) so that the script
               can securely log into the Rubrik Cluster. To do so run the below command via Powershell:

            $Credential = Get-Credential
            $Credential | Export-CliXml -Path .\creds\rubrik.Cred
            
            The above will ask for a user name and password and them store them in an encrypted xml file.
             
            2. Execute this script via the example above. 

        Known Issues:

            1. This script does not support Oracle snapshots (non-managed volume types)


#>

param(
    [parameter(Mandatory=$false, HelpMessage="Maximum age (days) of an archive to query for.")]
    [int] $MaxAge,

    [parameter(Mandatory=$false, HelpMessage="SLAs to query for snapshots that have not been archived.")] 
    [string[]] $SLAs,

    [parameter(Mandatory=$false, HelpMessage="Rubrik clusters to query.")]
    [string[]] $rubrik_clusters
)

#Requires -Modules @{ ModuleName="Rubrik"; ModuleVersion="4.0.0.217" }

$cloudState = 0

Import-Module Rubrik

if (-not $rubrik_clusters) {
    $rubrik_clusters = Get-ChildItem .\creds
}

$non_archived_snapshots = @()

function Get-Non-Archived-VMwareVMs {
    Write-Verbose "Scanning SLA $sla for VMware VM hosts archives not sent since $archivalThreshold (UTC)..."        
    $all_vmwarevms = Get-RubrikVM -SLA "$sla" -PrimaryClusterId local
    foreach ($vmwarevm in $all_vmwarevms) {
        $snapshot_list = $vmwarevm | Get-RubrikSnapshot | 
        Where-Object {($_.date -ne $null) -and `
                      ([datetime]$_.date -ge $beginDate -and [datetime]$_.date -le $archivalThreshold) -and `
                      ($_.cloudState -eq $cloudState -or [string]::IsNullOrEmpty($_.cloudState)) -and `
                      ($_.slaId -notmatch "UNPROTECTED")}
        foreach ($snapshot in $snapshot_list) {
            if ($DebugPreferences -match "SilentlyContinue") {
                $snapshot_list | Export-Clixml -Path snapshot_list.vmwarevms.$($vmwarevm.Name).xml
            }
            $script:non_archived_snapshots += @{
                "Object Name" = "N/A"
                "Database Instance" = "N/A"
                "Host Name" = $vmwarevm.Name
                "Rubrik Cluster" = $($rubrik_cluster.ToString())
                "SLA Domain" = $vmwarevm.effectiveSlaDomainName
                "Backup Type" = "VMware VM"
                "Snapshot Date (UTC)" = $snapshot.date
                "Cloud State" = $snapshot.cloudState
                "Archive Threshold (UTC)..." = $archivalThreshold
            }
        }
    }
}

function Get-Non-Archived-HyperVVMs {
    Write-Verbose "Scanning SLA $sla for Hyper-V VM archives not sent since $archivalThreshold (UTC)..."
    $all_hypervvms = Get-RubrikHyperVVM -SLA "$sla" -PrimaryClusterId local
    foreach ($hypervvm in $all_hypervvms) {
        $snapshot_list = $hypervvm | Get-RubrikSnapshot |
        Where-Object {($_.date -ne $null) -and `
                      ([datetime]$_.date -ge $beginDate -and [datetime]$_.date -le $archivalThreshold) -and `
                      ($_.cloudState -eq $cloudState -or [string]::IsNullOrEmpty($_.cloudState)) -and `
                      ($_.slaId -notmatch "UNPROTECTED")}
        foreach ($snapshot in $snapshot_list) {
            if ($DebugPreferences -match "SilentlyContinue") {
                $snapshot_list | Export-Clixml -Path snapshot_list.hypervvms.$($hypervvm.Name).xml
            }
            $script:non_archived_snapshots += @{
                "Object Name" = "N/A"
                "Database Instance" = "N/A"
                "Host Name" = $hypervvm.Name
                "Rubrik Cluster" = $($rubrik_cluster.ToString())
                "SLA Domain" = $hypervvm.effectiveSlaDomainName
                "Backup Type" = "Hyper-V VM"
                "Snapshot Date (UTC)" = $snapshot.date
                "Cloud State" = $snapshot.cloudState
                "Archive Threshold (UTC)..." = $archivalThreshold
            }
        }
    }
}

function Get-Non-Archived-NutanixVMs {
    Write-Verbose "Scanning SLA $sla for Nutanix VM archives not sent since $archivalThreshold (UTC)..."
    $all_nutanixvms = Get-RubrikNutanixVM -SLA "$sla" -PrimaryClusterId local
    foreach ($nutanixvm in $all_nutanixvms) {
        $snapshot_list = $nutanixvm | Get-RubrikSnapshot |
        Where-Object {($_.date -ne $null) -and `
                      ([datetime]$_.date -ge $beginDate -and [datetime]$_.date -le $archivalThreshold) -and `
                      ($_.cloudState -eq $cloudState -or [string]::IsNullOrEmpty($_.cloudState)) -and `
                      ($_.slaId -notmatch "UNPROTECTED")}
        foreach ($snapshot in $snapshot_list) {
            if ($DebugPreferences -match "SilentlyContinue") {
                $snapshot_list | Export-Clixml -Path snapshot_list.nutanixvms.$($nutanixvm.Name).xml
            }
            $script:non_archived_snapshots += @{
                "Object Name" = "N/A"
                "Database Instance" = "N/A"
                "Host Name" = $nutanixvm.Name
                "Rubrik Cluster" = $($rubrik_cluster.ToString())
                "SLA Domain" = $nutanixvm.effectiveSlaDomainName
                "Backup Type" = "Nutanix VM"
                "Snapshot Date (UTC)" = $snapshot.date
                "Cloud State" = $snapshot.cloudState
                "Archive Threshold (UTC)..." = $archivalThreshold
            }
        }
    }
}
    
function Get-Non-Archived-Filesets {
    Write-Verbose "Scanning SLA $sla for Filesets archives not sent since $archivalThreshold (UTC)..."
    $all_filesets = Get-RubrikFileset -SLA "$sla" -PrimaryClusterId local 
    foreach ($fileset in $all_filesets) {
        $snapshot_list = ($fileset | Get-RubrikFileset).snapshots | 
        Where-Object {($_.date -ne $null) -and `
                      ([datetime]$_.date -ge $beginDate -and [datetime]$_.date -le $archivalThreshold) -and `
                      ($_.cloudState -eq $cloudState -or [string]::IsNullOrEmpty($_.cloudState)) -and `
                      ($_.slaId -notmatch "UNPROTECTED")}
        foreach ($snapshot in $snapshot_list) {
            if ($DebugPreferences -match "SilentlyContinue") {
                $snapshot_list | Export-Clixml -Path snapshot_list.filesets.$($fileset.Name).xml
            }
            if ([string]::IsNullOrEmpty($fileset.shareId)) {
                $backuptype = "Fileset"
            } else {
                $backuptype = "NAS"
            }
            $script:non_archived_snapshots += @{
                "Object Name" = $fileset.Name
                "Database Instance" = $sql_db.InstanceName
                "Host Name" = $fileset.hostName
                "Rubrik Cluster" = $($rubrik_cluster.ToString())
                "SLA Domain" = $fileset.effectiveSlaDomainName
                "Backup Type" = $backuptype
                "Snapshot Date (UTC)" = $snapshot.date
                "Cloud State" = $snapshot.cloudState
                "Archive Threshold (UTC)..." = $archivalThreshold
            }
        }
    }
}

function Get-Non-Archived-SQL-DBs {
    Write-Verbose "Scanning SLA $sla for SQL Databases archives not sent since $archivalThreshold (UTC)..."
    $all_sql_dbs = Get-RubrikDatabase -SLA "$sla" -PrimaryClusterId local
    foreach ($sql_db in $all_sql_dbs) {
        $snapshot_list = $sql_db | Get-RubrikSnapshot | 
        Where-Object {($_.date -ne $null) -and `
                      ([datetime]$_.date -ge $beginDate -and [datetime]$_.date -le $archivalThreshold) -and `
                      ($_.cloudState -eq $cloudState -or [string]::IsNullOrEmpty($_.cloudState)) -and `
                      ($_.slaId -notmatch "UNPROTECTED")}
        foreach ($snapshot in $snapshot_list) {
            if ($DebugPreferences -match "SilentlyContinue") {
                $snapshot_list | Export-Clixml -Path snapshot_list.sqldbs.$($sql_db.Name).xml
            }
            $script:non_archived_snapshots += @{
                "Object Name" = $sql_db.Name
                "Database Instance" = $sql_db.InstanceName
                "Host Name" = $sql_db.rootProperties.rootName
                "Rubrik Cluster" = $($rubrik_cluster.ToString())
                "SLA Domain" = $sql_db.effectiveSlaDomainName
                "Backup Type" = "SQL Server Database"
                "Snapshot Date (UTC)" = $snapshot.date
                "Cloud State" = $snapshot.cloudState
                "Archive Threshold (UTC)..." = $archivalThreshold
            }
        }
    }
}

function Get-Non-Archived-MVs {
    Write-Verbose "Scanning SLA $sla for Managed Volumes archives not sent since $archivalThreshold (UTC)..."
    $all_mvs = Get-RubrikManagedVolume -SLA "$sla" -PrimaryClusterId local
    foreach ($mv in $all_mvs) {
        $snapshot_list = $mv | Get-RubrikSnapshot |
        Where-Object {($_.date -ne $null) -and `
                      ([datetime]$_.date -ge $beginDate -and [datetime]$_.date -le $archivalThreshold) -and `
                      ($_.cloudState -eq $cloudState -or [string]::IsNullOrEmpty($_.cloudState)) -and `
                      ($_.slaId -notmatch "UNPROTECTED")}
        foreach ($snapshot in $snapshot_list) {
            if ($DebugPreferences -match "SilentlyContinue") {
                $snapshot_list | Export-Clixml -Path snapshot_list.managedvolume.$($mv.Name).xml
            }
            $script:non_archived_snapshots += @{
                "Object Name" = $mv.Name
                "Database Instance" = "N/A"
                "Host Name" = "N/A"
                "Rubrik Cluster" = $($rubrik_cluster.ToString())
                "SLA Domain" = $mv.effectiveSlaDomainName
                "Backup Type" = "Managed Volume"
                "Snapshot Date (UTC)" = $snapshot.date
                "Cloud State" = $snapshot.cloudState
                "Archive Threshold (UTC)..." = $archivalThreshold
            }
        }
    }
}

$currentdate = Get-Date
foreach ($rubrik_cluster in $rubrik_clusters) {
    $cred = Import-CliXml $(".\creds\"+$rubrik_cluster.ToString())
    Write-Host " "
    write-host "Connecting to Rubrik Server $($rubrik_cluster.ToString())"
    Write-Host " "
    Connect-Rubrik -Server $($rubrik_cluster.ToString() -replace '^(.*).creds$','$1') -Credential $cred | Out-Null
    if ($MaxAge -eq 0) {
        $beginDate = (Get-Date -Year 2014 -Month 12 -Day 1 -Hour 00 -Minute 00 -Second 00).ToUniversalTime()
    } else {
        $secondsAgo = (0 - $MaxAge) * 24 * 3600
        $beginDate = ($currentdate).AddSeconds($secondsAgo).ToUniversalTime()
    }
    if ([string]::IsNullOrEmpty($SLAs)) {
        $archive_slas = Get-RubrikSLA | where-object {$_.archivalSpecs -ne $null} 
    } else {
        foreach ($getsla in $SLAs) {
            $archive_slas += Get-RubrikSLA -SLA "$getsla"
        }
    }
    foreach ($sla_data in $archive_slas) {
        $secondsAgo = 0 - [int]$sla_data.archivalSpecs.archivalThreshold
        $archivalThreshold = ($currentdate).AddSeconds($secondsAgo).ToUniversalTime()
        $sla = $sla_data.name
        if ($beginDate -ge $archivalThreshold) {
            Write-Host "Max Age $beginDate (UTC) is on or after the archive threshold $archivalThreshold (UTC) for SLA $sla, skipping..."
        } else {
            Write-Host "Scanning SLA $sla for snapshots not sent to the archive before $archivalThreshold (UTC) but are no older than $beginDate (UTC)..."
            Get-Non-Archived-VMwareVMs
            Get-Non-Archived-HyperVVMs
            Get-Non-Archived-NutanixVMs
            Get-Non-Archived-Filesets
            Get-Non-Archived-SQL-DBs
            Get-Non-Archived-MVs
        }
    }
    Disconnect-Rubrik -Confirm:$false
    if ($non_archived_snapshots) {
        if ($auto) {
            Write-Host " "
            Write-Host "Snapshots that have not been archived after the SLA Domain archive threshold:"
            write-host " "
        } else {
            Write-Host " "
            Write-Host "Snapshots that are not archived since $($archivalThreshold) (UTC):"
            write-host " "
        }
    } else {
        Write-Host " "
        Write-Host "No snapshots found that have not been archived."
        Write-Host " "
    }
    if ($DebugPreferences -match "SilentlyContinue") {
        Export-Clixml -InputObject $non_archived_snapshots -Path ./non_archived_snapshots.$rubrik_cluster.xml
    }
    $non_archived_snapshots.ForEach({[PSCustomObject]$_}) | 
        Sort-Object -Property "Rubrik Cluster","Host Name","Snapshot Date (UTC)" | 
        Format-Table -AutoSize  -GroupBy "Host Name" `
        -Property "Host Name","Database Instance","Object Name","Rubrik Cluster","SLA Domain","Backup Type","Cloud State","Archive Threshold (UTC)...","Snapshot Date (UTC)" 
    $non_archived_snapshots = @()
}