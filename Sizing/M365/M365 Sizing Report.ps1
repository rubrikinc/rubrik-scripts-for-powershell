[CmdletBinding()]
param (
    [Parameter()]
    [string]$Period = 'D180'
)
function Measure-AverageGrowth {
    param (
        [string]$UsageReportCSV
    )
    $UsageReport = Import-Csv -Path $UsageReportCSV | Sort-Object -Property "Report Date"
    $Record = 1
    $StorageUsage = @()
    foreach ($item in $UsageReport) {
        if ($Record -eq 1){
            $StorageUsed = $Item."Storage Used (Byte)"
        }else {
            $StorageUsage += (
                New-Object psobject -Property @{
                    Growth =  [math]::Round(((($Item.'Storage Used (Byte)' / $StorageUsed) -1) * 100),2)
                }
            )
            $StorageUsed = $Item."Storage Used (Byte)"
        }
        $Record = $Record + 1
    }
    $AverageGrowth = $StorageUsage | Measure-Object -Property Growth -Average
    return $AverageGrowth
}

# Connect-MgGraph -Scopes @("Reports.Read.All")

#region Go get data from Microsoft
Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/reports/getMailboxUsageDetail(period='$($Period)')" -OutputFilePath ./getMailboxUsageDetail.csv
Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/reports/getMailboxUsageStorage(period='$($Period)')" -OutputFilePath ./getMailboxUsageStorage.csv
Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/reports/getOneDriveUsageAccountDetail(period='$($Period)')" -OutputFilePath ./getOneDriveUsageAccountDetail.csv
Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/reports/getOneDriveUsageStorage(period='$($Period)')" -OutputFilePath ./getOneDriveUsageStorage.csv
Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/reports/getSharePointSiteUsageDetail(period='$($Period)')" -OutputFilePath ./getSharePointSiteUsageDetail.csv
Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/reports/getSharePointSiteUsageStorage(period='$($Period)')" -OutputFilePath ./getSharePointSiteUsageStorage.csv
#endregion

#region Exchange Sizing Info
$MailboxUsageDetails = Import-Csv -Path ./getMailboxUsageDetail.csv
$ExchangeStats = $MailboxUsageDetails | Measure-Object -Property "Storage Used (Byte)" -Sum -Average
$MailboxAverageGowth = Measure-AverageGrowth -UsageReportCSV ./getMailboxUsageStorage.csv
$ExchangeInfo = [PSCustomObject]@{
    'NumberOfMailboxes'             = $ExchangeStats.Count
    'TotalSizeOfAllMailboxesGB'     = [math]::Round(($ExchangeStats.Sum / 1GB),2)
    'AverageSizeOfAllMailboxesGB'   = [math]::Round(($ExchangeStats.Average /1GB),2)
    'AverageGrowthPercentage'       = [math]::Round($MailboxAverageGowth.Average ,2)
}
#endregion


#region OneDrive Sizing Info
$OneDriveUsageDetails = Import-Csv -Path ./getOneDriveUsageAccountDetail.csv
$OneDriveStats = $OneDriveUsageDetails | Measure-Object -Property "Storage Used (Byte)" -Sum -Average
$OneDriveAverageGowth = Measure-AverageGrowth -UsageReportCSV ./getOneDriveUsageStorage.csv
$OneDriveInfo = [PSCustomObject]@{
    'NumberOfUsers'             = $OneDriveStats.Count
    'TotalSizeOfAllUsersGB'     = [math]::Round(($OneDriveStats.Sum / 1GB),2)
    'AverageSizeOfAllUsersGB'   = [math]::Round(($OneDriveStats.Average /1GB),2)
    'AverageGrowthPercentage'   = [math]::Round($OneDriveAverageGowth.Average ,2)
}
#endregion

#region Sharepoint Sizing Info
$SharepointUsageDetails = Import-Csv -Path ./getSharePointSiteUsageDetail.csv
$SharepointStats = $SharepointUsageDetails | Measure-Object -Property "Storage Used (Byte)" -Sum -Average
$SharepointAverageGowth = Measure-AverageGrowth -UsageReportCSV ./getSharePointSiteUsageStorage.csv
$SharepointInfo = [PSCustomObject]@{
    'NumberOfSites'             = $SharepointStats.Count
    'TotalSizeOfAllSitesGB'     = [math]::Round(($SharepointStats.Sum / 1GB),2)
    'AverageSizeOfAllSitesGB'   = [math]::Round(($SharepointStats.Average /1GB),2)
    'AverageGrowthPercentage'   = [math]::Round($SharepointAverageGowth.Average ,2)
}
#endregion
Write-Output $ExchangeInfo | Tee-Object .\RubrikMS365Sizing.txt
Write-Output $OneDriveInfo | Tee-Object .\RubrikMS365Sizing.txt -Append
Write-Output $SharepointInfo | Tee-Object .\RubrikMS365Sizing.txt -Append

# TODO: for detail report calls, do we need to see things over 180 days or would 7 suffice?

# TODO: Need number of exchange users
# TODO: Need average size of all mailboxes
# TODO: need average size of all mailboxes not deleted
# TODO: Need total size of all mailboxes
# TODO: need total size of all mailboxes not deleted
# TODO: Need annual growth of all mailboxes over the 180 days

# TODO: for the above, we need to do the same for onedrive and sharepoint
# TODO: do we need a parse only option?
# Disconnect-MgGraph
$ExchangeInfo


