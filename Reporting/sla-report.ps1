#Requires -Modules Rubrik
#Requires -Version 5
#Requires -PSEdition Desktop
# --------------------
# SLA Reporting Script
# --------------------
# This script will report on all SLA Domains on a Rubrik cluster, detailing:
#  - SLA Domain Name
#  - Frequency and retention settings
#  - Replication settings
#  - Archival settings
#  - Member objects
# --------------------
# Written by: Tim Hynes <tim.hynes@rubrik.com>
# --------------------
Import-Module Rubrik
# Replace variables here:
$rubrik_cluster = 'rubrik.demo.com'
$rubrik_user = 'admin'
$rubrik_pass = 'MyP@ss123!'
$output_type = 'text' # enter 'html' for an html report, 'csv' for a CSV based-report, or 'text' for a plain text report
$output_folder = '.' # this can be modified to 'C:\temp' or whatever is required, leave as '.' to write to script path, do not include trailing slash on folder path
# Do not change anything after this point
# Set up web headers for certain API calls
$headers = @{
    Authorization = "Basic {0}" -f [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $rubrik_user,$rubrik_pass)))
    Accept = 'application/json'
}
# Connect to Rubrik cluster
$rk_connection = Connect-Rubrik -Server $rubrik_cluster -Username $rubrik_user -Password $(ConvertTo-SecureString -String $rubrik_pass -AsPlainText -Force)
# Get list of all local SLAs
$rk_all_slas = Get-RubrikSla -PrimaryClusterID local
# Create our object which will contain all our output information
$output_object = @()
Write-Output "$($rk_all_slas.count) SLA Domains found on Rubrik cluster..."
# Now gather all the data we will use for the report
foreach ($rk_sla in $rk_all_slas) {
    Write-Output "Working on SLA Domain: $($rk_sla.name)"
    $this_sla_object = @{}
    $this_sla_object['name'] = $rk_sla.name
    $this_sla_object['frequencies'] = $rk_sla.frequencies
    if ($rk_sla.replicationSpecs -ne $null) {
        $this_sla_object['replication'] = @{}
        $rep_target_info = Invoke-WebRequest -Uri $("https://"+$rubrik_cluster+"/api/internal/replication/target/"+$rk_sla.replicationSpecs.locationId) -Headers $headers -Method GET
        $this_sla_object['replication']['target'] = $($rep_target_info.Content | ConvertFrom-Json).targetClusterName
        $this_sla_object['replication']['retention'] = $rk_sla.replicationSpecs.retentionLimit
    }
    if ($rk_sla.archivalSpecs -ne $null) {
        $this_sla_object['archive'] = @{}
        $archive_locations = Invoke-WebRequest -Uri $("https://"+$rubrik_cluster+"/api/internal/archive/location") -Headers $headers -Method GET
        $archive_locations = $($archive_locations.Content | ConvertFrom-Json).data
        $this_sla_object['archive']['target'] = $archive_locations | Where-Object -Property id -eq $rk_sla.archivalSpecs.locationId | Select-Object -ExpandProperty name
        $this_sla_object['archive']['instantArchive'] = $rk_sla.archivalSpecs.archivalThreshold
        $this_sla_object['archive']['retentionOnBrik'] = $rk_sla.localRetentionLimit
    }
    $this_sla_object['vms'] = @()
    $this_sla_vms = Get-RubrikVM -SLA $rk_sla.name
    foreach ($vm in $this_sla_vms) {
        $this_sla_object['vms'] += $vm.name
    }
    $this_sla_object['filesets'] = @()
    $this_sla_filesets = Get-RubrikFileset -SLA $rk_sla.name
    foreach ($fileset in $this_sla_filesets) {
        $this_sla_object['filesets'] += $($fileset.hostName + ":::" + $fileset.name)
    }
    $this_sla_object['databases'] = @()
    $this_sla_databases = Get-RubrikDatabase -Sla $rk_sla.name
    foreach ($db in $this_sla_databases) {
        $this_sla_object['databases'] += $($db.rootProperties.rootName + ":::" + $db.instanceName + "\" + $db.name)
    }
    $output_object += $this_sla_object
}
# Now we output the report
if ($output_type -eq 'text') {
    $output_file_name = $output_folder + "\" + $(get-date -uFormat "%Y%m%d-%H%M%S") + "-RubrikSLAReport.txt"
    Write-Output "============================================" | Tee-Object -FilePath $output_file_name -Append
    Write-Output "SLA Domain Report" | Tee-Object -FilePath $output_file_name -Append
    Write-Output "Rubrik Cluster: $rubrik_cluster" | Tee-Object -FilePath $output_file_name -Append
    Write-Output "Date/Time: $(Get-Date)" | Tee-Object -FilePath $output_file_name -Append
    Write-Output "# of SLA Domains: $($rk_all_slas.count)" | Tee-Object -FilePath $output_file_name -Append
    Write-Output "============================================" | Tee-Object -FilePath $output_file_name -Append
    foreach ($sla_domain in $output_object) {
        Write-Output "Name: $($sla_domain.name)" | Tee-Object -FilePath $output_file_name -Append
        Write-Output "" | Tee-Object -FilePath $output_file_name -Append
        Write-Output "Retention Settings:" | Tee-Object -FilePath $output_file_name -Append
        $retention_output = @()
        $retention_output | Select-Object -Property Take,Keep
        if ($sla_domain.frequencies.timeUnit.Contains("Hourly")) {
            $policy = $sla_domain.frequencies | Where-Object -Property timeUnit -eq "Hourly"
            $this_policy = New-Object PSObject
            $this_policy | Add-Member -type NoteProperty -Name 'Take' -Value "Every $($policy.frequency) Hour(s)"
            $this_policy | Add-Member -type NoteProperty -Name 'Keep' -Value "for $($policy.retention / 24) Day(s)"
            $retention_output += $this_policy
        }
        if ($sla_domain.frequencies.timeUnit.Contains("Daily")) {
            $policy = $sla_domain.frequencies | Where-Object -Property timeUnit -eq "Daily"
            $this_policy = New-Object PSObject
            $this_policy | Add-Member -type NoteProperty -Name 'Take' -Value "Every $($policy.frequency) Day(s)"
            $this_policy | Add-Member -type NoteProperty -Name 'Keep' -Value "for $($policy.retention) Day(s)"
            $retention_output += $this_policy
        }
        if ($sla_domain.frequencies.timeUnit.Contains("Monthly")) {
            $policy = $sla_domain.frequencies | Where-Object -Property timeUnit -eq "Monthly"
            $this_policy = New-Object PSObject
            $this_policy | Add-Member -type NoteProperty -Name 'Take' -Value "Every $($policy.frequency) Month(s)"
            $this_policy | Add-Member -type NoteProperty -Name 'Keep' -Value "for $($policy.retention / 12) Year(s)"
            $retention_output += $this_policy
        }
        if ($sla_domain.frequencies.timeUnit.Contains("Yearly")) {
            $policy = $sla_domain.frequencies | Where-Object -Property timeUnit -eq "Yearly"
            $this_policy = New-Object PSObject
            $this_policy | Add-Member -type NoteProperty -Name 'Take' -Value "Every $($policy.frequency) Year(s)"
            $this_policy | Add-Member -type NoteProperty -Name 'Keep' -Value "for $($policy.retention) Year(s)"
            $retention_output += $this_policy
        }
        Write-Output $($retention_output | ft) | Tee-Object -FilePath $output_file_name -Append
        Write-Output "Archival Settings:" | Tee-Object -FilePath $output_file_name -Append
        if ($sla_domain.archive -ne $null) {
            if ($sla_domain.archive.instantArchive -eq 1) {
                if (0 -eq $sla_domain.archive.retentionOnBrik % 31536000 -and $sla_domain.archive.retentionOnBrik -eq 1) {
                    Write-Output "The SLA domain is archived to $($sla_domain.archive.target) with Instant Archive enabled, and is kept on the local cluster for $($sla_domain.archive.retentionOnBrik / 31536000) years" | Tee-Object -FilePath $output_file_name -Append
                } else {
                    Write-Output "The SLA domain is archived to $($sla_domain.archive.target) with Instant Archive enabled, and is kept on the local cluster for $($sla_domain.archive.retentionOnBrik / 86400) days" | Tee-Object -FilePath $output_file_name -Append
                }
            } else {
                if (0 -eq $sla_domain.archive.retentionOnBrik % 31536000) {
                    Write-Output "The SLA domain is archived to $($sla_domain.archive.target), and is kept on the local cluster for $($sla_domain.archive.retentionOnBrik / 31536000) years" | Tee-Object -FilePath $output_file_name -Append
                } else {
                    Write-Output "The SLA domain is archived to $($sla_domain.archive.target), and is kept on the local cluster for $($sla_domain.archive.retentionOnBrik / 86400) days" | Tee-Object -FilePath $output_file_name -Append
                }
            }
        } else {
            Write-Output "  (none)" | Tee-Object -FilePath $output_file_name -Append
        }
        Write-Output "" | Tee-Object -FilePath $output_file_name -Append
        Write-Output "Replication Settings:" | Tee-Object -FilePath $output_file_name -Append
        if ($sla_domain.replication -ne $null) {
            if (0 -eq $sla_domain.replication.retention % 31536000) {
                Write-Output "The SLA domain is replicated to $($sla_domain.replication.target), and is kept on the remote cluster for $($sla_domain.replication.retention / 31536000) years" | Tee-Object -FilePath $output_file_name -Append
            } else {
                Write-Output "The SLA domain is replicated to $($sla_domain.replication.target), and is kept on the remote cluster for $($sla_domain.replication.retention / 86400) days" | Tee-Object -FilePath $output_file_name -Append
            }
        } else {
            Write-Output "  (none)" | Tee-Object -FilePath $output_file_name -Append
        }
        Write-Output "" | Tee-Object -FilePath $output_file_name -Append
        if ($sla_domain.vms.count -gt 0) {
            Write-Output "Protected Virtual Machines:" | Tee-Object -FilePath $output_file_name -Append
            foreach ($vm in $sla_domain.vms) {
                Write-Output "  $vm" | Tee-Object -FilePath $output_file_name -Append
            }
        } else {
            Write-Output "Protected Virtual Machines:" | Tee-Object -FilePath $output_file_name -Append
            Write-Output "  (none)" | Tee-Object -FilePath $output_file_name -Append
        }
        if ($sla_domain.databases.count -gt 0) {
            Write-Output "Protected Databases:" | Tee-Object -FilePath $output_file_name -Append
            foreach ($database in $sla_domain.databases) {
                Write-Output "  $database" | Tee-Object -FilePath $output_file_name -Append
            }
        } else {
            Write-Output "Protected Databases:" | Tee-Object -FilePath $output_file_name -Append
            Write-Output "  (none)" | Tee-Object -FilePath $output_file_name -Append
        }
        if ($sla_domain.filesets.count -gt 0) {
            Write-Output "Protected Filesets:" | Tee-Object -FilePath $output_file_name -Append
            foreach ($fileset in $sla_domain.filesets) {
                Write-Output "  $fileset"
            }
        } else {
            Write-Output "Protected Filesets:" | Tee-Object -FilePath $output_file_name -Append
            Write-Output "  (none)" | Tee-Object -FilePath $output_file_name -Append
        }

        Write-Output "============================================" | Tee-Object -FilePath $output_file_name -Append
    }
}
if ($output_type -eq 'html') {
    $output_file_name = $output_folder + "\" + $(get-date -uFormat "%Y%m%d-%H%M%S") + "-RubrikSLAReport.html"
    $output_html = @()
    $style_head = @"
<head><style>
P {font-family: Calibri, Helvetica, sans-serif;}
H1 {font-family: Calibri, Helvetica, sans-serif;}
H3 {font-family: Calibri, Helvetica, sans-serif;}
TABLE {border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse;}
TH {border-width: 1px; padding: 3px; border-style: solid; border-color: black; background-color: #00cccc; font-family: Calibri, Helvetica, sans-serif;}
TD {border-width: 1px; padding: 3px; border-style: solid; border-color: black; font-family: Calibri, Helvetica, sans-serif;}
</style></head>
"@
    $output_html += $style_head
    $output_html += "<hr>"
    $output_html += "<h1>SLA Domain Report</h1>"
    $output_html += "<h3>Rubrik Cluster: $rubrik_cluster</h3>"
    $output_html += "<h3>Date/Time: $(Get-Date)</h3>"
    $output_html += "<h3># of SLA Domains: $($rk_all_slas.count)</h3>"
    $output_html += "<hr>"
    foreach ($sla_domain in $output_object) {
        $output_html += "<p><b>Name: </b>$($sla_domain.name)</p>"
        $output_html += "<p><b>Retention Settings:</b></p>"
        $retention_output = @()
        $retention_output | Select-Object -Property Take,Keep
        if ($sla_domain.frequencies.timeUnit.Contains("Hourly")) {
            $policy = $sla_domain.frequencies | Where-Object -Property timeUnit -eq "Hourly"
            $this_policy = New-Object PSObject
            $this_policy | Add-Member -type NoteProperty -Name 'Take' -Value "Every $($policy.frequency) Hour(s)"
            $this_policy | Add-Member -type NoteProperty -Name 'Keep' -Value "for $($policy.retention / 24) Day(s)"
            $retention_output += $this_policy
        }
        if ($sla_domain.frequencies.timeUnit.Contains("Daily")) {
            $policy = $sla_domain.frequencies | Where-Object -Property timeUnit -eq "Daily"
            $this_policy = New-Object PSObject
            $this_policy | Add-Member -type NoteProperty -Name 'Take' -Value "Every $($policy.frequency) Day(s)"
            $this_policy | Add-Member -type NoteProperty -Name 'Keep' -Value "for $($policy.retention) Day(s)"
            $retention_output += $this_policy
        }
        if ($sla_domain.frequencies.timeUnit.Contains("Monthly")) {
            $policy = $sla_domain.frequencies | Where-Object -Property timeUnit -eq "Monthly"
            $this_policy = New-Object PSObject
            $this_policy | Add-Member -type NoteProperty -Name 'Take' -Value "Every $($policy.frequency) Month(s)"
            $this_policy | Add-Member -type NoteProperty -Name 'Keep' -Value "for $($policy.retention / 12) Year(s)"
            $retention_output += $this_policy
        }
        if ($sla_domain.frequencies.timeUnit.Contains("Yearly")) {
            $policy = $sla_domain.frequencies | Where-Object -Property timeUnit -eq "Yearly"
            $this_policy = New-Object PSObject
            $this_policy | Add-Member -type NoteProperty -Name 'Take' -Value "Every $($policy.frequency) Year(s)"
            $this_policy | Add-Member -type NoteProperty -Name 'Keep' -Value "for $($policy.retention) Year(s)"
            $retention_output += $this_policy
        }
        $output_html += $($retention_output | ConvertTo-Html -Fragment)
        $output_html += "<p><b>Archival Settings:</b></p>"
        if ($sla_domain.archive -ne $null) {
            if ($sla_domain.archive.instantArchive -eq 1) {
                if (0 -eq $sla_domain.archive.retentionOnBrik % 31536000 -and $sla_domain.archive.instantArchive -eq 1) {
                    $output_html += "<p>The SLA domain is archived to $($sla_domain.archive.target) with Instant Archive enabled, and is kept on the local cluster for $($sla_domain.archive.retentionOnBrik / 31536000) years</p>"
                } else {
                    $output_html += "<p>The SLA domain is archived to $($sla_domain.archive.target) with Instant Archive enabled, and is kept on the local cluster for $($sla_domain.archive.retentionOnBrik / 86400) days</p>"
                }
            } else {
                if (0 -eq $sla_domain.archive.retentionOnBrik % 31536000 -and $sla_domain.archive.retentionOnBrik -ne 0) {
                    $output_html += "<p>The SLA domain is archived to $($sla_domain.archive.target), and is kept on the local cluster for $($sla_domain.archive.retentionOnBrik / 31536000) years</p>"
                } else {
                    $output_html += "<p>The SLA domain is archived to $($sla_domain.archive.target), and is kept on the local cluster for $($sla_domain.archive.retentionOnBrik / 86400) days</p>"
                }
            }
        } else {
            $output_html += "<p>(none)</p>"
        }
        $output_html += "<p><b>Replication Settings:</b></p>"
        if ($sla_domain.replication -ne $null) {
            if (0 -eq $sla_domain.replication.retention % 31536000) {
                $output_html += "<p>The SLA domain is replicated to $($sla_domain.replication.target), and is kept on the remote cluster for $($sla_domain.replication.retention / 31536000) years</p>"
            } else {
                $output_html += "<p>The SLA domain is replicated to $($sla_domain.replication.target), and is kept on the remote cluster for $($sla_domain.replication.retention / 86400) days</p>"
            }
        } else {
            $output_html += "<p>(none)</p>"
        }
        if ($sla_domain.vms.count -gt 0) {
            $output_html += "<p><b>Protected Virtual Machines:</b></p>"
            $output_html += "<table>"
            foreach ($vm in $sla_domain.vms) {
                $output_html += "<tr><td>$vm</td></tr>"
            }
            $output_html += "</table>"
        } else {
            $output_html += "<p><b>Protected Virtual Machines:</b></p>"
            $output_html += "<p>(none)</p>"
        }
        if ($sla_domain.databases.count -gt 0) {
            $output_html += "<p><b>Protected Databases:</b></p>"
            $output_html += "<table>"
            foreach ($database in $sla_domain.databases) {
                $output_html += "<tr><td>$database</td></tr>"
            }
            $output_html += "</table>"
        } else {
            $output_html += "<p><b>Protected Databases:</b></p>"
            $output_html += "<p>(none)</p>"
        }
        if ($sla_domain.filesets.count -gt 0) {
            $output_html += "<p><b>Protected Filesets:</b></p>"
            $output_html += "<table>"
            foreach ($fileset in $sla_domain.filesets) {
                $output_html += "<tr><td>$fileset</td></tr>"
            }
            $output_html += "</table>"
        } else {
            $output_html += "<p><b>Protected Filesets:</b></p>"
            $output_html += "<p>(none)</p>"
        }
        $output_html += "<hr>"
    }
    $output_html > $output_file_name
}
if ($output_type -eq 'csv') {
    $output_file_name = $output_folder + "\" + $(get-date -uFormat "%Y%m%d-%H%M%S") + "-RubrikSLAReport.csv"
    $output_csv = @()
    $output_array = @()
    foreach ($sla_domain in $output_object) {
        $row = '' | select name,cluster,timedate,policy_hourly,policy_daily,policy_monthly,policy_yearly,archival_location,archival_instant,archival_local_retention,replication_location,replication_target_retention,protected_vms,protected_dbs,protected_filesets
        $row.name = $sla_domain.name
        $row.cluster = $rubrik_cluster
        $row.timedate = $(Get-Date)
        if ($sla_domain.frequencies.timeUnit.Contains("Hourly")) {
            $policy = $sla_domain.frequencies | Where-Object -Property timeUnit -eq "Hourly"
            $row.policy_hourly = "Take every $($policy.frequency) Hour(s), keep for $($policy.retention / 24) Day(s)"
        }
        if ($sla_domain.frequencies.timeUnit.Contains("Daily")) {
            $policy = $sla_domain.frequencies | Where-Object -Property timeUnit -eq "Daily"
            $row.policy_daily = "Take every $($policy.frequency) Day(s), keep for $($policy.retention) Day(s)"
        }
        if ($sla_domain.frequencies.timeUnit.Contains("Monthly")) {
            $policy = $sla_domain.frequencies | Where-Object -Property timeUnit -eq "Monthly"
            $row.policy_monthly = "Take every $($policy.frequency) Month(s), keep for $($policy.retention / 12) Year(s)"
        }
        if ($sla_domain.frequencies.timeUnit.Contains("Yearly")) {
            $policy = $sla_domain.frequencies | Where-Object -Property timeUnit -eq "Yearly"
            $row.policy_yearly = "Take every $($policy.frequency) Year(s), keep for $($policy.retention) Year(s)"
        }
        if ($sla_domain.archive.target) {
            $row.archival_location = $sla_domain.archive.target
        }
        if ($sla_domain.archive.instantArchive -eq 1) {
            $row.archival_instant = $true
        } else {
            $row.archival_instant = $false
        }
        if ($sla_domain.archive.retentionOnBrik) {
            if (0 -eq $sla_domain.archive.retentionOnBrik % 31536000) {
                $row.archival_local_retention = "$($sla_domain.archive.retentionOnBrik / 31536000) years"
            } else {
                $row.archival_local_retention = "$($sla_domain.archive.retentionOnBrik / 86400) days"
            }
        }
        if ($sla_domain.replication) {
            $row.replication_location = $sla_domain.replication.target
            if (0 -eq $sla_domain.replication.retention % 31536000 -and $sla_domain.replication.retention -ne 0) {
                $row.replication_target_retention = "$($sla_domain.replication.retention / 31536000) years"
            } else {
                $row.replication_target_retention = "$($sla_domain.replication.retention / 86400) days"
            }
        }
        $row.protected_vms = $($sla_domain.vms -join ';')
        $row.protected_dbs = $($sla_domain.databases -join ';')
        $row.protected_filesets =  $($sla_domain.filesets -join ';')
        $output_array += $row
    }
    $output_csv += $output_array | ConvertTo-Csv
    $output_csv > $output_file_name
}