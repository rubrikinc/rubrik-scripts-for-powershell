<#
.SYNOPSIS
    Get-RubrikM365SizingInfo.ps1 returns statistics on number of accounts, sites and how much storage they are using in a Micosoft 365 Tennant
.DESCRIPTION
    Get-RubrikM365SizingInfo.ps1 returns statistics on number of accounts, sites and how much storage they are using in a Micosoft 365 Tennant
    In this script, Rubrik uses Microsoft Graph APIs to return data from the customer's M365 tennant. Data is collected via the Graph API
    and then downloaded to the customer's machine. The downloaded reports can be found in the customers $systemTempFolder folder. This data is left 
    behind and never sent to Rubrik or viewed by Rubrik. 

.EXAMPLE
    PS C:\> .\Get-RubrikM365SizingInfo.ps1
    Will connect to customer's M365 tennant. A browser page will open up linking to the customer's M365 tennant authorization page. The 
    customer will need to provide authorization. The script will gather data for 180 days. Once this is done output will be written to the current working directory as a file called 
    RubrikM365Sizing.txt
.INPUTS
    Inputs (if any)
.OUTPUTS
    RubrikM365Sizing.txt containing the below data. 
    Exchange

    Name                           Value
    ----                           -----
    AverageGrowthPercentage        0.16
    SizePerUserGB                  0.01
    NumberOfUsers                  12
    TotalSizeGB                    0.16

    ==========================================================================
    OneDrive

    Name                           Value
    ----                           -----
    AverageGrowthPercentage        446.78
    SizePerUserGB                  3.2
    NumberOfUsers                  6
    TotalSizeGB                    19.22

    ==========================================================================
    Sharepoint

    Name                           Value
    ----                           -----
    AverageGrowthPercentage        11.23
    NumberOfSites                  18
    SizePerUserGB                  1.07
    TotalSizeGB                    19.33

    ==========================================================================

    We will also output an object with the above information that can be used for further integration.
.NOTES
    Author:         Chris Lumnah
    Created Date:   6/17/2021
#>
#Requires -Module Microsoft.Graph
[CmdletBinding()]
param (
    [Parameter()]
    [ValidateSet("7","30","90","180")]
    [string]$Period = '180',
    # Parameter help description
    [Parameter()]
    [Switch]
    $OutputObject
)

# Provide OS agnostic temp folder path for raw reports
$systemTempFolder = [System.IO.Path]::GetTempPath()

function Get-MgReport {
    [CmdletBinding()]
    param (
        # MS Graph API report name
        [Parameter(Mandatory)]
        [String]$ReportName,

        # Report Period (Days)
        [Parameter(Mandatory)]
        [ValidateSet("7","30","90","180")]
        [String]$Period
    )
    
    process {
        try {
            Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/reports/$($ReportName)(period=`'D$($Period)`')" -OutputFilePath "$systemTempFolder\$ReportName.csv"

            "$systemTempFolder\$ReportName.csv"
        }
        catch {
            throw $_.Exception
        }
        
    }
}
function Measure-AverageGrowth {
    param (
        [Parameter(Mandatory)]
        [string]$UsageReportCSV, 
        [Parameter(Mandatory)]
        [string]$ReportName

    )
    if ($ReportName -eq 'getOneDriveUsageStorage'){
        $UsageReport = Import-Csv -Path $UsageReportCSV | Where-Object {$_.'Site Type' -eq 'OneDrive'} |Sort-Object -Property "Report Date"
    }else{
        $UsageReport = Import-Csv -Path $UsageReportCSV | Sort-Object -Property "Report Date"
    }
    
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

Connect-MgGraph -Scopes @("Reports.Read.All")

$M365Sizing = @{
    Exchange = @{
        NumberOfUsers = 0
        TotalSizeGB = 0
        SizePerUserGB = 0
        AverageGrowthPercentage = 0
    }
    OneDrive = @{
        NumberOfUsers = 0
        TotalSizeGB = 0
        SizePerUserGB = 0
        AverageGrowthPercentage = 0
    }
    Sharepoint = @{
        NumberOfSites = 0
        TotalSizeGB = 0
        SizePerUserGB = 0
        AverageGrowthPercentage = 0
    }
}

#region Exchange Sizing Info
$Section = 'Exchange'
$UsageCountReport = Get-MgReport -ReportName 'getMailboxUsageMailboxCounts' -Period $Period
$UsageCounts = Import-Csv -Path $UsageCountReport | Sort-Object -Property 'Report Date' -Descending | Select-Object -First 1

$UsageStorageReport = Get-MgReport -ReportName 'getMailboxUsageStorage' -Period $Period
$UsageStorage = Import-Csv -Path $UsageStorageReport | Sort-Object -Property 'Report Date' -Descending | Select-Object -First 1
$MailboxAverageGowth = Measure-AverageGrowth -UsageReportCSV $UsageStorageReport -ReportName 'getMailboxUsageStorage'

$M365Sizing.$($Section).NumberOfUsers = $UsageCounts.Total
$M365Sizing.$($Section).TotalSizeGB = [math]::Round(($UsageStorage.'Storage Used (Byte)' / 1GB), 2)
$M365Sizing.$($Section).SizePerUserGB = [math]::Round((($UsageStorage.'Storage Used (Byte)' / $M365Sizing.$($Section).NumberOfUsers) / 1GB), 2)
$M365Sizing.$($Section).AverageGrowthPercentage = [math]::Round($MailboxAverageGowth.Average ,2)
#endregion

#region OneDrive Sizing Info
$Section = 'OneDrive'
$UsageCountReport = (Get-MgReport -ReportName 'getOneDriveUsageAccountCounts' -Period $Period)
$UsageCounts = Import-Csv -Path $UsageCountReport | Sort-Object -Property 'Report Date' -Descending | Select-Object -First 1

$UsageStorageReport = Get-MgReport -ReportName 'getOneDriveUsageStorage' -Period $Period
$UsageStorage = Import-Csv -Path $UsageStorageReport | Sort-Object -Property 'Report Date' -Descending | Select-Object -First 1
$MailboxAverageGowth = Measure-AverageGrowth -UsageReportCSV $UsageStorageReport -ReportName 'getOneDriveUsageStorage'

$M365Sizing.$($Section).NumberOfUsers = $UsageCounts.Total
$M365Sizing.$($Section).TotalSizeGB = [math]::Round(($UsageStorage.'Storage Used (Byte)' / 1GB), 2)
$M365Sizing.$($Section).SizePerUserGB = [math]::Round((($UsageStorage.'Storage Used (Byte)' / $M365Sizing.$($Section).NumberOfUsers) / 1GB), 2)
$M365Sizing.$($Section).AverageGrowthPercentage = [math]::Round($MailboxAverageGowth.Average ,2)
#endregion

#region Sharepoint Sizing Info
$Section = 'Sharepoint'
$UsageCountReport = (Get-MgReport -ReportName 'getSharePointSiteUsageSiteCounts' -Period $Period)
$UsageCounts = Import-Csv -Path $UsageCountReport | Sort-Object -Property 'Report Date' -Descending | Select-Object -First 1

$UsageStorageReport = Get-MgReport -ReportName 'getSharePointSiteUsageStorage' -Period $Period
$UsageStorage = Import-Csv -Path $UsageStorageReport | Sort-Object -Property 'Report Date' -Descending | Select-Object -First 1
$MailboxAverageGowth = Measure-AverageGrowth -UsageReportCSV $UsageStorageReport -ReportName 'getSharePointSiteUsageStorage'

$M365Sizing.$($Section).NumberOfSites = $UsageCounts.Total
$M365Sizing.$($Section).TotalSizeGB = [math]::Round(($UsageStorage.'Storage Used (Byte)' / 1GB), 2)
$M365Sizing.$($Section).SizePerUserGB = [math]::Round((($UsageStorage.'Storage Used (Byte)' / $M365Sizing.$($Section).NumberOfSites) / 1GB), 2)
$M365Sizing.$($Section).AverageGrowthPercentage = [math]::Round($MailboxAverageGowth.Average ,2)
#endregion


Disconnect-MgGraph
foreach($Section in $M365Sizing | Select-Object -ExpandProperty Keys){
        
    Write-Output $Section | Out-File -FilePath .\RubrikMS365Sizing.txt -Append
    Write-Output $M365Sizing.$($Section)  | Out-File -FilePath .\RubrikMS365Sizing.txt -Append
    Write-Output "==========================================================================" | Out-File -FilePath .\RubrikMS365Sizing.txt -Append
}

Write-Output "`n`nM365 Sizing information has been written to $((Get-ChildItem RubrikMS365Sizing.txt).FullName)`n`n"
if ($OutputObject) {
    return $M365Sizing
}
 