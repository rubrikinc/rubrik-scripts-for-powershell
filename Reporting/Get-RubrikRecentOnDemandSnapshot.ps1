function Get-RubrikRecentOnDemandSnapshot {
  <#
.SYNOPSIS
Retrieve the events related to on-demand snapshots

.DESCRIPTION
The Get-RubrikRecentOnDemandSnapshot function is used to pull a event data in regards to on-demand snapshots taken and returns the event information

.NOTES
Written by Jaap Brasser for community usage
Twitter: @jaap_brasser
GitHub: jaapbrasser

.EXAMPLE
. .\Get-RubrikRecentOnDemandSnapshot.ps1

Load the function into memory so it can be executed in the current PowerShell session

.EXAMPLE
Get-RubrikRecentOnDemandSnapshot

Retrieve the on-demand snapshots for the last day

.EXAMPLE
Get-RubrikRecentOnDemandSnapshot -Days 7

Retrieve the on-demand snapshots for the last 7 days
#>
    param(
        # Specify the amount of days on-demand backups should be retrieved for
        [decimal] $Days = 1
    )

    $SplatEvent = @{
        ObjectType = 'UserActionAudit'
        Limit = 150
    }
    
    $backupEvents = do {
        ($CurrentEvents = Get-RubrikEvent @SplatEvent)
        $SplatEvent.AfterId = $CurrentEvents[-1].id
    } while ($CurrentEvents[-1].Date -ge (Get-Date).AddMonths(-1))
    
    $backupEvents | Where-Object {
        $_.eventInfo -match 'started a job to create an on-demand'
    } | Select-Object -Property Date,EventInfo
}


