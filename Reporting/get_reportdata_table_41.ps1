#
# Name:     get_reportdata_table_41.ps1
# Author:   Tim Hynes
# Use case: Provides an example of pulling out Envision report data for Rubrik CDM 4.1+
#
function Get-RubrikReportData41 () {
    [CmdletBinding()]
    Param (
        [string]$rubrik_cluster,
        [string]$rubrik_user,
        [string]$rubrik_pass,
        [string]$report_id,
        [System.Object]$report_query
    )

    $headers = @{
        Authorization = "Basic {0}" -f [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $rubrik_user,$rubrik_pass)))
        Accept = 'application/json'
    }

    # This block prevents errors from self-signed certificates
    Add-Type -TypeDefinition @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object -TypeName TrustAllCertsPolicy
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $report_output = @()
    $has_more = $true
    while ($has_more -eq $true) {
        if ($cursor -ne $null) {
            $report_query['cursor'] = $cursor
        }
        $report_response = Invoke-WebRequest -Uri $("https://"+$rubrik_cluster+"/api/internal/report/"+$report_id+"/table") -Headers $headers -Method POST -Body $(ConvertTo-Json $report_query)
        $report_data = $report_response.Content | ConvertFrom-Json
        $has_more = $report_data.hasMore
        $cursor = $report_data.cursor
        foreach ($report_entry in $report_data.dataGrid) {
            $row = '' | select $report_data.columns
            for ($i = 0; $i -lt $report_entry.count; $i++) {
                $row.$($report_data.columns[$i]) = $($report_entry[$i])
            }
            $report_output += $row
        }
    }
    return $report_output
}

$rubrik_cluster = 'rubrik.demo.com'
$rubrik_user = 'admin'
$rubrik_pass = 'MyP@ss123!'

$report_query = @{
    limit = 100
}
<# Below is the complete available list of queries, copy and add these to the $report_query hash above to enable them
@{
    limit = 0
    sortBy = "Hour"
    sortOrder = "asc"
    cursor = "sring"
    objectName = "string"
    requestFilters = @{
    organization = "string"
    slaDomain = "string"
    taskType = "Backup"
    taskStatus = "Succeeded"
    objectType = "HypervVirtualMachine"
    complianceStatus = "InCompliance"
    clusterLocation = "Local"
    }
}
#>

$report_id = 'CustomReport:::382bac60-f73c-435c-b899-6c2915a40da9'

$a = Get-RubrikReportData41 -rubrik_cluster $rubrik_cluster -rubrik_user $rubrik_user -rubrik_pass $rubrik_pass -report_query $report_query -report_id $report_id