# Rubrik Reporting - Events Report

# Version Control:
# -- 1.0 Initial Script Creation

# Pre-Requisites:
# -- Rubrik Powershell Module:
# -- Install from PoSh Gallery - Install-Module Rubrik

Import-Module Rubrik

# Configure Credentials
$rubrik_ip = 'rubrik.demo.com'
$rubrik_user = 'notauser'
$rubrik_pass = 'notapass'

# Configure Script Settings
$hours_to_check = 72
$_VMConfig = $false
$_MSSQLConfig = $true
$_FilesetConfig = $false
$_PhyHost = $false

# Declare Arrays for use
$csv_data = @()

# Connect to Rubrik with Basic Auth
Connect-Rubrik -Server $rubrik_ip -Username $rubrik_user -Password $(ConvertTo-SecureString -String $rubrik_pass -AsPlainText -Force) | Out-Null

# Configure ISO Standard Date Format - Today minus hours specified in $hours_to_check Variable
$date_iso_string = Get-Date $($(Get-Date).AddHours(-$hours_to_check).ToUniversalTime()) -UFormat '+%Y-%m-%dT%H:%M:%S.000Z'

# Function to get Events Data for specific Rubrik ID
function getEventsData([string]$rubrik_id){

    # If SQL, we can't filter events full vs transactional - get last 50 events then filter out by string checks
    # This may need tuned depending on number of transactional backups per DB

    if($rubrik_id.StartsWith('MssqlDatabase')){
        $result_size = '50'
    } else {
        $result_size = '1'
    }

    $formatted_endpoint = 'event?object_ids='+$rubrik_id+'&event_type=Backup&limit='+$result_size+'&after_date='+$date_iso_string
    $my_data = Invoke-RubrikRESTCall -Endpoint $formatted_endpoint -Method GET -api "internal"
    return $my_data

}

# Function to Get Last Successful Backup from Events - Today minus hours specified in $hours_to_check Variable
function getLastSuccessBackup([string]$rubrik_id){

    $formatted_endpoint = 'event?object_ids='+$rubrik_id+'&event_type=Backup&limit=1&status=Success&show_only_latest=true'
    $last_success = Invoke-RubrikRESTCall -Endpoint $formatted_endpoint -Method GET -api "internal"
    $info = $last_success.data.time
    return $info

}

# Start Script against VMware VMs
if($_VMConfig -eq $true){

    write-host "Starting Gather for VMs"
    $vmhosts = Get-RubrikVM
    
    foreach($vm in $vmhosts){

        $events_data = getEventsData($vm.id)

        foreach($event in $events_data.data){

            $backupDate = $event.time
            $eventVM = $vm.name
            $sla = $vm.effectiveSlaDomainName
            $vmHostname = $vm.hostName

            if($event -eq $null){

                $eventStatus = "ERROR"
                $eventInfo = "No Backups Found"

            } else {

                $eventStatus = $event.eventStatus
                $eventInfo = $event.eventInfo | ConvertFrom-Json

            }

            if($eventStatus -eq "Failure"){
                $info = getLastSuccessBackup($vm.id)
            } elseif($eventStatus -eq "Running"){
                $info = getLastSuccessBackup($vm.id)
            } elseif($eventStatus -eq "Warning"){
                $info = getLastSuccessBackup($vm.id)
            } elseif($eventStatus -eq "Canceled"){
                $info = getLastSuccessBackup($vm.id)
            } elseif($eventStatus -eq "Canceling"){
                $info = getLastSuccessBackup($vm.id)
            }

            if($eventStatus -eq "Success"){
                $info = "N/A"
            } elseif($info -eq $null){
                $infoStr = "No Successful Backup Found"
            } else {
                $infoStr = "Last Successful Backup: $($info)"
            }
        
            $csv_data+=New-Object PSObject -Property @{timestamp=$backupDate;name=$eventVM;hostname=$vmHostname;effectiveSlaDomainName=$sla;lastEventStatus=$eventStatus;lastEventMessage=$eventInfo.message;relic=$vm.isRelic;type="VM";info=$infoStr}
            
            $info = $null
            $infoStr = $null
            $eventStatus = $null
            $eventInfo = $null
            $sla = $null
            $eventVM = $null
            $backupData = $null
        }

    }

    write-host "Gathering VM Info Completed"
}

# Start Script against MSSQL Databases
if($_MSSQLConfig -eq $true){

    write-host "Starting Gather for MSSQL DBs"
    $mssql = Get-RubrikDatabase

    foreach($sqldb in $mssql){

        $events_data = getEventsData($sqldb.id)

        foreach($event in $events_data.data){
            if($event.eventInfo.Contains('transaction log')){
            } else {
                $backupDate = $event.time
                $eventDB = "$($sqldb.instanceName)\$($sqldb.name)"
                $sla = $sqldb.effectiveSlaDomainName
                $DBhostname = $sqldb.rootProperties.rootName

                if($event -eq $null){

                    $eventStatus = "ERROR"
                    $eventInfo = "No Backups Found"

                } else {

                    $eventStatus = $event.eventStatus
                    $eventInfo = $event.eventInfo | ConvertFrom-Json
                }

                if($eventStatus -eq "Failure"){
                    $info = getLastSuccessBackup($sqldb.id)
                } elseif($eventStatus -eq "Running"){
                    $info = getLastSuccessBackup($sqldb.id)
                } elseif($eventStatus -eq "Warning"){
                    $info = getLastSuccessBackup($sqldb.id)
                } elseif($eventStatus -eq "Canceled"){
                    $info = getLastSuccessBackup($sqldb.id)
                } elseif($eventStatus -eq "Canceling"){
                    $info = getLastSuccessBackup($sqldb.id)
                }

                if($eventStatus -eq "Success"){
                    $info = "N/A"
                } elseif($info -eq $null){
                    $infoStr = "No Successful Backup Found"
                } else {
                    $infoStr = "Last Successful Backup: $($info)"
                }

                $csv_data+=New-Object PSObject -Property @{timestamp=$backupDate;name=$eventDB;hostname=$DBhostname;effectiveSlaDomainName=$sla;lastEventStatus=$eventStatus;lastEventMessage=$eventInfo.message;relic=$sqldb.isRelic;type="MSSQL";info=$infoStr}
                
                $info = $null
                $infoStr = $null
                $eventStatus = $null
                $eventInfo = $null
                $sla = $null
                $eventVM = $null
                $backupData = $null
            }
        }
    }

    write-host "Gathering MSSQL Info Completed"
}

# Start Script against Filesets
if($_FilesetConfig -eq $true){
    write-host "Starting Gather for Filesets"
    $hosts =  get-RubrikHost

    $filesets = Get-RubrikFileset

    foreach($fileset in $filesets){

        $events_data = getEventsData($fileset.id)

        foreach($event in $events_data.data){

            $backupDate = $event.time
            $eventFileset = $fileset.name
            $sla = $fileset.effectiveSlaDomainName
            $filesetHostname = $fileset.hostName

            if($event -eq $null){

                $eventStatus = "ERROR"
                $eventInfo = "No Backups Found"

            } else {

                $eventStatus = $event.eventStatus
                $eventInfo = $event.eventInfo | ConvertFrom-Json
            }

            if($eventStatus -eq "Failure"){
                $info = getLastSuccessBackup($fileset.id)
            } elseif($eventStatus -eq "Running"){
                $info = getLastSuccessBackup($fileset.id)
            } elseif($eventStatus -eq "Warning"){
                $info = getLastSuccessBackup($fileset.id)
            } elseif($eventStatus -eq "Canceled"){
                $info = getLastSuccessBackup($fileset.id)
            } elseif($eventStatus -eq "Canceling"){
                $info = getLastSuccessBackup($fileset.id)
            } else {
                $info = $eventStatus
            }

            if($eventStatus -eq "Success"){
                $info = "N/A"
            } elseif($info -eq $null){
                $infoStr = "No Successful Backup Found"
            } else {
                $infoStr = "Last Successful Backup: $($info)"
            }

            $csv_data+=New-Object PSObject -Property @{timestamp=$backupDate;name=$eventFileset;hostname=$filesetHostname;effectiveSlaDomainName=$sla;lastEventStatus=$eventStatus;lastEventMessage=$eventInfo.message;relic=$fileset.isRelic;type="Fileset";info=$infoStr}
            
            $info = $null
            $infoStr = $null
            $eventStatus = $null
            $eventInfo = $null
            $sla = $null
            $eventFileset = $null
            $backupData = $null
        }
    }

    write-host "Gathering Fileset Info Completed"
}

# Start Script against Physical Hosts

if($_PhyHost -eq $true){
    write-host "Starting Gather for Physical Hosts"
    foreach($phost in $phosts){
        $events_data = getEventsData($phost.id)

        foreach($event in $events_data.data){

            $backupDate = $event.time
            $eventpHost = $phost.name
            $sla = $fileset.effectiveSlaDomainName
            $phostHostname = $fileset.hostName

            if($event -eq $null){

                $eventStatus = "ERROR"
                $eventInfo = "No Backups Found"

            } else {

                $eventStatus = $event.eventStatus
                $eventInfo = $event.eventInfo | ConvertFrom-Json
            }

            if($eventStatus -eq "Failure"){
                $info = getLastSuccessBackup($phost.id)
            } elseif($eventStatus -eq "Running"){
                $info = getLastSuccessBackup($phost.id)
            } elseif($eventStatus -eq "Warning"){
                $info = getLastSuccessBackup($phost.id)
            } elseif($eventStatus -eq "Canceled"){
                $info = getLastSuccessBackup($phost.id)
            } elseif($eventStatus -eq "Canceling"){
                $info = getLastSuccessBackup($phost.id)
            } else {
                $info = $eventStatus
            }

            if($eventStatus -eq "Success"){
                $info = "N/A"
            } elseif($info -eq $null){
                $infoStr = "No Backup Found"
            } else {
                $infoStr = "Last Successful Backup: $($info)"
            }
        
            $csv_data+=New-Object PSObject -Property @{timestamp=$backupDate;name=$eventpHost;hostname=$phostHostname;effectiveSlaDomainName=$sla;lastEventStatus=$eventStatus;lastEventMessage=$eventInfo.message;relic=$phost.isRelic;type="Physical Host";info=$infoStr}
            
            $info = $null
            $infoStr = $null
            $eventStatus = $null
            $eventInfo = $null
            $sla = $null
            $eventpHost = $null
            $backupData = $null
        }
    }

    write-host "Gathering Physical Host Info Completed"
}

# Export Data to CSV File
$csv_data | export-csv .\rubrik_backup_status_report.csv -notype -Force

# Disconnect from Rubrik and Cleanup PS Session
Disconnect-Rubrik -Confirm:$false
Remove-Variable * -ErrorAction SilentlyContinue
Write-host "Script Finished - Cleanup Completed"