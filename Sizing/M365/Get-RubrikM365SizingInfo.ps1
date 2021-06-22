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
        [string]$ReportCSV, 
        [Parameter(Mandatory)]
        [string]$ReportName

    )
    if ($ReportName -eq 'getOneDriveUsageStorage'){
        $UsageReport = Import-Csv -Path $ReportCSV | Where-Object {$_.'Site Type' -eq 'OneDrive'} |Sort-Object -Property "Report Date"
    }else{
        $UsageReport = Import-Csv -Path $ReportCSV | Sort-Object -Property "Report Date"
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

function ProcessUsageReport {
    param (
        [Parameter(Mandatory)]
        [string]$ReportCSV, 
        [Parameter(Mandatory)]
        [string]$ReportName,
        [Parameter(Mandatory)]
        [string]$Section
    )

    $ReportDetail = Import-Csv -Path $ReportCSV | Where-Object {$_.'Is Deleted' -eq 'FALSE'}
    $SummarizedData = $ReportDetail | Measure-Object -Property 'Storage Used (Byte)' -Sum -Average
    $M365Sizing.$($Section).NumberOfUsers = $SummarizedData.Count
    $M365Sizing.$($Section).TotalSizeGB = [math]::Round(($SummarizedData.Sum / 1GB), 2, [MidPointRounding]::AwayFromZero)
    $M365Sizing.$($Section).SizePerUserGB = [math]::Round((($SummarizedData.Average) / 1GB), 2)
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
    # Skype = @{
    #     NumberOfUsers = 0
    #     TotalSizeGB = 0
    #     SizePerUserGB = 0
    #     AverageGrowthPercentage = 0
    # }
    # Yammer = @{
    #     NumberOfUsers = 0
    #     TotalSizeGB = 0
    #     SizePerUserGB = 0
    #     AverageGrowthPercentage = 0
    # }
    # Teams = @{
    #     NumberOfUsers = 0
    #     TotalSizeGB = 0
    #     SizePerUserGB = 0
    #     AverageGrowthPercentage = 0
    # }
}


#region Usage Detail Reports
# Run Usage Detail Reports for different sections to get counts, total size of each section and average size. 
# We will only capture data that [Is Deleted] is equal to false. If [Is Deleted] is equal to True then that account has been deleted 
# from the customers M365 tennant. It should not be counted in the sizing reports as We will not backup those objects. 
$UsageDetailReports = @{}
$UsageDetailReports.Add('Exchange', 'getMailboxUsageDetail')
$UsageDetailReports.Add('OneDrive', 'getOneDriveUsageAccountDetail')
$UsageDetailReports.Add('Sharepoint', 'getSharePointSiteUsageDetail')
foreach($Section in $UsageDetailReports.Keys){
    $ReportCSV = Get-MgReport -ReportName $UsageDetailReports[$Section] -Period $Period
    ProcessUsageReport -ReportCSV $ReportCSV -ReportName $UsageDetailReports[$Section] -Section $Section
}
#endregion

#region Storage Usage Reports
# Run Storage Usage Reports for each section get get a trend of storage used for the period provided. We will get the growth percentage
# for each day and then average them all across the period provided. This way we can take into account the growth or the reduction 
# of storage used across the entire period. 
$StorageUsageReports = @{}
$StorageUsageReports.Add('Exchange', 'getMailboxUsageStorage')
$StorageUsageReports.Add('OneDrive', 'getOneDriveUsageStorage')
$StorageUsageReports.Add('Sharepoint', 'getSharePointSiteUsageStorage')
foreach($Section in $StorageUsageReports.Keys){
    $ReportCSV = Get-MgReport -ReportName $StorageUsageReports[$Section] -Period $Period
    $AverageGowth = Measure-AverageGrowth -ReportCSV $ReportCSV -ReportName $StorageUsageReports[$Section]
    $M365Sizing.$($Section).AverageGrowthPercentage = [math]::Round($AverageGowth.Average ,2)
}
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
 