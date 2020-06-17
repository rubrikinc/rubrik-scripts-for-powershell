# $username = Read-Host -Prompt "Please enter your Rubrik Username: "
# $password = Read-Host -Prompt "Please enter your Rubrik Password: " -AsSecureString

Connect-Rubrik -Server $Rubrik.server.amer1 -Token $rubrik.token.amer1

$query = @{
    'should_include_event_series' = $true
    # 'order_by_time' = 'asc'
    'object_type' = 'Mssql'
}
$Events = (Invoke-RubrikRESTCall -Endpoint 'event/latest' -Query $query -Method GET).data

$Jobs = @()
foreach ($Event in $Events){
    $Event
    $RubrikDatabase = Get-RubrikDatabase -id $Event.latestEvent.ObjectID

    $Jobs += New-Object -TypeName PSObject -Property @{
        'EventID' = $Event.latestEvent.id
        'EventStatus' = $Event.latestEvent.EventStatus
        'eventSeriesStatus' = $Event.eventSeriesStatus
        'EventProgress' = $Event.latestEvent.EventProgress
        'Time' = $Event.latestEvent.Time
        'ObjectID' = $Event.latestEvent.ObjectID
        'ObjectName' = $Event.latestEvent.ObjectName
        'Location' = $RubrikDatabase.rootProperties.rootName
        'LocationType' = $RubrikDatabase.rootProperties.rootType
        'ConfiguredSLA' = $RubrikDatabase.configuredSLADomainName
        'EventInfo' = $Event.latestEvent.eventInfo
    }
    
}

$Jobs | select * | Where-Object Location -EQ 'MyClusterInstanceName' | Where-Object EventStatus -NE "Success" | Out-GridView