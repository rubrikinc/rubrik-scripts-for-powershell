function Get-RubrikRequestInfo {
    param(
        # Rubrik Request Object Info
        [Parameter(Mandatory = $true)]
        [PSObject]$RubrikRequest,
        # The type of request
        [Parameter(Mandatory = $true)]
        [ValidateSet('fileset', 'mssql', 'vmware/vm', 'hyperv/vm', 'managed_volume')]
        [String]$Type
    )
    
    $ExitList = @("SUCCEEDED", "FAILED")
    do {
        $RubrikRequestInfo = Get-RubrikRequest -id $RubrikRequest.id -Type $Type
        IF ($RubrikRequestInfo.progress -gt 0) {
            Write-Debug "$($RubrikRequestInfo.id) is $($RubrikRequestInfo.status) $($RubrikRequestInfo.progress) complete"
            Write-Progress -Activity "$($RubrikRequestInfo.id) is $($RubrikRequestInfo.status)" -status "Progress $($RubrikRequestInfo.progress)" -percentComplete ($RubrikRequestInfo.progress)
        }
        else {
            Write-Progress -Activity "$($RubrikRequestInfo.id)" -status "Job Queued" -percentComplete (0)
        }
        Start-Sleep -Seconds 1
    } while ($RubrikRequestInfo.status -notin $ExitList) 	
    return Get-RubrikRequest -id $RubrikRequest.id -Type $Type
}