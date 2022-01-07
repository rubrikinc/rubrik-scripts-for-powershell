<#
.SYNOPSIS
    Get-RubrikM365SizingInfo.ps1 returns statistics on number of accounts, sites and how much storage they are using in a Micosoft 365 Tenant
.DESCRIPTION
    Get-RubrikM365SizingInfo.ps1 returns statistics on number of accounts, sites and how much storage they are using in a Micosoft 365 Tenant
    In this script, Rubrik uses Microsoft Graph APIs to return data from the customer's M365 Tenant. Data is collected via the Graph API
    and then downloaded to the customer's machine. The downloaded reports can be found in the customers $systemTempFolder folder. This data is left 
    behind and never sent to Rubrik or viewed by Rubrik. 

.EXAMPLE
    PS C:\> .\Get-RubrikM365SizingInfo.ps1
    Will connect to customer's M365 Tenant. A browser page will open up linking to the customer's M365 Tenant authorization page. The 
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
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Reports
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
    
    $AverageGrowth = ($StorageUsage | Measure-Object -Property Growth -Average).Average
    # AverageGrowth is based on 180 days. This is not annual growth. To provide an annual growth we will take the value of AverageGrowth * 2 and then round up to the nearest whole percentage. While this is not exact, it should be close enough for our purposes.
    $AverageGrowth = [math]::Ceiling(($AverageGrowth * 2)) 
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
    switch ($Section) {
        'Sharepoint' { $M365Sizing.$($Section).NumberOfSites = $SummarizedData.Count }
        Default {$M365Sizing.$($Section).NumberOfUsers = $SummarizedData.Count}
    }
    $M365Sizing.$($Section).TotalSizeGB = [math]::Round(($SummarizedData.Sum / 1GB), 2, [MidPointRounding]::AwayFromZero)
    $M365Sizing.$($Section).SizePerUserGB = [math]::Round((($SummarizedData.Average) / 1GB), 2)
}


Connect-MgGraph -Scopes @("Reports.Read.All")

$M365Sizing = [ordered]@{
    Exchange = [ordered]@{
        NumberOfUsers = 0
        TotalSizeGB   = 0
        SizePerUserGB = 0
        AverageGrowthPercentage = 0
    }
    OneDrive = [ordered]@{
        NumberOfUsers = 0
        TotalSizeGB   = 0
        SizePerUserGB = 0
        AverageGrowthPercentage = 0
    }
    Sharepoint = [ordered]@{
        NumberOfSites = 0
        TotalSizeGB   = 0
        SizePerUserGB = 0
        AverageGrowthPercentage = 0
    }
    Licensing = [ordered]@{
        # Commented out for now, but we can get the number of licensed users if required (Not just activated).
        # Exchange         = 0
        # OneDrive         = 0
        # SharePoint       = 0
        # Teams            = 0
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
# from the customers M365 Tenant. It should not be counted in the sizing reports as We will not backup those objects. 
$UsageDetailReports = @{}
$UsageDetailReports.Add('Exchange', 'getMailboxUsageDetail')
$UsageDetailReports.Add('OneDrive', 'getOneDriveUsageAccountDetail')
$UsageDetailReports.Add('Sharepoint', 'getSharePointSiteUsageDetail')
foreach($Section in $UsageDetailReports.Keys){
    $ReportCSV = Get-MgReport -ReportName $UsageDetailReports[$Section] -Period $Period
    ProcessUsageReport -ReportCSV $ReportCSV -ReportName $UsageDetailReports[$Section] -Section $Section
}
Remove-Item -Path $ReportCSV
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
    $AverageGrowth = Measure-AverageGrowth -ReportCSV $ReportCSV -ReportName $StorageUsageReports[$Section]
    $M365Sizing.$($Section).AverageGrowthPercentage = [math]::Round($AverageGrowth,2)
    Remove-Item -Path $ReportCSV
}
#endregion

#region License usage
$licenseReportPath = Get-MgReport -ReportName getOffice365ActiveUserDetail -Period 180
$licenseReport = Import-Csv -Path $licenseReportPath | Where-Object 'is deleted' -eq 'FALSE'

# Clean up temp CSV
Remove-Item -Path $licenseReportPath

$assignedProducts = $licenseReport | ForEach-Object {$_.'Assigned Products'.Split('+')} | Group-Object | Select-Object Name,Count
$assignedProducts | ForEach-Object {$M365Sizing.Licensing.Add($_.name, $_.count)}

# We can add these back in if we want total licensed users for each feature.
# $M365Sizing.Licensing.Exchange   = ($licenseReport | Where-Object 'Has Exchange License' -eq 'True' | measure-object).Count
# $M365Sizing.Licensing.OneDrive   = ($licenseReport | Where-Object 'Has OneDrive License' -eq 'True' | measure-object).Count
# $M365Sizing.Licensing.SharePoint = ($licenseReport | Where-Object 'Has Sharepoint License' -eq 'True' | measure-object).Count
# $M365Sizing.Licensing.Teams      = ($licenseReport | Where-Object 'Has Teams License' -eq 'True' | measure-object).Count
#endregion

Disconnect-MgGraph
foreach($Section in $M365Sizing | Select-Object -ExpandProperty Keys){
    Write-Output $Section | Out-File -FilePath .\RubrikMS365Sizing.txt -Append
    Write-Output $M365Sizing.$($Section) |Format-Table -AutoSize | Out-File -FilePath .\RubrikMS365Sizing.txt -Append
    Write-Output "==========================================================================" | Out-File -FilePath .\RubrikMS365Sizing.txt -Append
}

Write-Output "`n`nM365 Sizing information has been written to $((Get-ChildItem RubrikMS365Sizing.txt).FullName)`n`n"
if ($OutputObject) {
    return $M365Sizing
}
 