#
# Name:     per_org_cap_report.ps1
# Author:   Tim Hynes
# Use case: Reports FE and BE TB per Organisation
Import-Module Rubrik
$rubrik_ip = 'rubrik.demo.com'
$rubrik_user = 'admin'
$rubrik_pass = 'MyP@ss123!'
Connect-Rubrik -Server $rubrik_ip -Username $rubrik_user -Password $(ConvertTo-SecureString -String $rubrik_pass -Force -AsPlainText)
$report_id = get-rubrikreport -Type Canned | ?{$_.name -eq 'Capacity Over Time'} | select -ExpandProperty id
$report_table = Invoke-RubrikRESTCall -Endpoint $('report/'+$report_id+'/table') -api internal -Body '{"limit":9999}' -Method POST
$report_output = @()
foreach ($report_entry in $report_table.dataGrid) {
    $row = '' | select $report_table.columns
    for ($i = 0; $i -lt $report_entry.count; $i++) {
        $row.$($report_table.columns[$i]) = $($report_entry[$i])
    }
    $report_output += $row
}
$report_output | Export-CSV -Path "report.csv" -NoTypeInformation
Disconnect-Rubrik