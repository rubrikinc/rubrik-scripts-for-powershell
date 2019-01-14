#
# Name:     get_failed_backups_basic.ps1
# Author:   Tim Hynes
# Use case: Basic report on failed backups for the last 24 hours
#
Import-Module Rubrik

$rubrik_clusters = Get-ChildItem .\creds
$hours_to_check = 24

foreach ($rubrik_cluster in $rubrik_clusters) {
    $cred = Import-CliXml $(".\creds\"+$rubrik_cluster.ToString())
    Connect-Rubrik -Server $($rubrik_cluster.ToString() -replace '^(.*).creds$','$1') -Credential $cred | Out-Null
    $date_iso_string = Get-Date $($(Get-Date).AddHours(-$hours_to_check).ToUniversalTime()) -UFormat '+%Y-%m-%dT%H:%M:%S.000Z'
    $uri = 'event?limit=20000&status=Failure&event_type=Backup&after_date='+$date_iso_string
    $events = Invoke-RubrikRESTCall -Endpoint $uri -Method GET -api internal
    $events = $events.data

    #
    # Resulting object should contain enough detail for each event to raise ticket, sample event below:
    #
    <#
    id            : 2018-10-30:19:1:::1540926911144-a211811c-6e7e-4944-9714-79a4bd211681
    objectId      : MssqlDatabase:::f301b2fc-62c8-4fb2-930b-f014326baf96
    objectType    : Mssql
    objectName    : msdb
    eventInfo     : {"message":"Failed  backup of Microsoft SQL Server Database 'msdb' from 'MF-SQL14N1\\MSSQLSERVER'. Reason: Could not open a connection to MF-SQL14N1:12800.
                    Error while creating socket","id":"Snapshot.BackupFromLocationFailed","params":{"${backupType}":"","${snappableName}":"msdb","${reason}":"Could not open a
                    connection to MF-SQL14N1:12800. Error while creating socket","${snappableType}":"Microsoft SQL Server
                    Database","${locationType}":"","${locationName}":"MF-SQL14N1\\MSSQLSERVER"},"cause":{"message":"Could not open a connection to MF-SQL14N1:12800. Error while
                    creating socket","id":"Connection.OpenFailure","params":{"${host}":"MF-SQL14N1","${reason}":"Error while creating socket","${port}":"12800"}}}
    time          : Tue Oct 30 19:15:11 UTC 2018
    eventType     : Backup
    eventStatus   : Failure
    eventSeriesId : 2e2f8b54-c0ce-493f-9668-21846b6157da
    relatedIds    : {MssqlDatabase:::f301b2fc-62c8-4fb2-930b-f014326baf96}
    #>

    Disconnect-Rubrik -Confirm:$false
}