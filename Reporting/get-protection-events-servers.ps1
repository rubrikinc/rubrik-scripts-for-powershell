
<#
.SYNOPSIS
Creates and Polls Rubrik Reports to build a custom HTML Report

.DESCRIPTION
Takes either a defined list of hosts and outputs a custom HTML report or runs against all hosts

.EXAMPLE
.\Get-Protection-Events.ps1

.NOTES
    Name:               Get Protection Events
    Created:            9/30/2019
    Author:             Andrew Draper
#>

Import-Module Rubrik
#### User Defined Variables ####
$cluster_ip = 'notacluster.rubrik.com' #Rubrik Cluster
$report_name = 'Protection-Tasks-Detailed' #Rubrik Report Name to generate HTML Report from
$RubrikUser = "notauser@rubrik.com" #Rubrik Username - Suggested using read-only user account
$rubrik_pass = "notapassword" #Rubrik Password - Suggested using read-only user account
$output_folder = '.' #Use local path to output HTML Report To
$output_file_name = $output_folder + "\" + $(get-date -uFormat "%Y%m%d-%H%M%S") + "-RubrikReport.html" #Name of HTML Report

# Server List is a defined list of hosts to report against, add you list of hosts using commas and new lines e.g. these names need to match to what they are inside of Rubrik
# $serverList = @(
#     'host1.domain.com',
#     'host1',
#     'host2.domain.com',
# )
$serverList = @(
    'em2-andrdrap-w1.rubrikdemo.com',
    'em2-andrdrap-w1'
)
#### User Defined Variables ####
$rubrikPW = ConvertTo-SecureString $rubrik_pass -asplaintext -force

# Define function to get all information from the Report
function Get-RubrikReportDataFull () {
    [CmdletBinding()]
    Param (
        [string]$rubrik_ip,
        [string]$rubrik_user,
        [string]$rubrik_pass,
        [string]$report_id,
        [string]$object_type
    )

    $headers = @{
        Authorization = "Basic {0}" -f [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $rubrik_user,$rubrik_pass)))
        Accept = 'application/json'
    }
    if ($psversiontable.PSVersion.Major -le 5) {
        try {
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
        }
        catch {

        }
    }
    $report_output = @()
    $report_query = @{
        limit = 9999
    }

    $has_more = $true
    while ($has_more -eq $true) {
        if ($null -ne $cursor) {
            $report_query['cursor'] = $cursor
        }
        if ($psversiontable.PSVersion.Major -le 5) {
            $report_response = Invoke-WebRequest -Uri $("https://"+$rubrik_ip+"/api/internal/report/"+$report_id+"/table") -Headers $headers -Method POST -Body $(ConvertTo-Json $report_query)
        } else {
            $report_response = Invoke-WebRequest -Uri $("https://"+$rubrik_ip+"/api/internal/report/"+$report_id+"/table") -Headers $headers -Method POST -Body $(ConvertTo-Json $report_query) -SkipCertificateCheck
        }
        $report_data = $report_response.Content | ConvertFrom-Json
        $has_more = $report_data.hasMore
        $cursor = $report_data.cursor
        foreach ($report_entry in $report_data.dataGrid) {
            $row = '' | Select-Object $report_data.columns
            for ($i = 0; $i -lt $report_entry.count; $i++) {
                $row.$($report_data.columns[$i]) = $($report_entry[$i])
            }
            $report_output += $row
        }
    }
    return $report_output
}

# Set HTML Header
$output_html = @()
$style_head = @"
<head><style>
P {font-family: Calibri, Helvetica, sans-serif;}
H1 {font-family: Calibri, Helvetica, sans-serif;}
H3 {font-family: Calibri, Helvetica, sans-serif;}
TABLE {border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse;}
TH {border-width: 1px; position: sticky; padding: 3px; border-style: solid; border-color: black; background-color: #00cccc; font-family: Calibri, Helvetica, sans-serif;}
TD {border-width: 1px; padding: 3px; border-style: solid; border-color: black; font-family: Calibri, Helvetica, sans-serif;}
</style></head>
"@

# Connect to Rubrik
$null = Connect-Rubrik -Server $cluster_ip -Username $RubrikUser -Password $rubrikPW
Write-Host 'Connected to Rubrik Cluster:'$global:rubrikConnection.server

#Get Report ID by Report Name
$reports = Invoke-RubrikRESTCall -Endpoint "report?name=$($report_name)" -api internal -Method GET

# Deal with Multiple Report Results
if($reports.total -gt 1){

    # Multiple Reports with same name
    foreach($reportName in $reports){
        if($reports.data.name -eq $report_name){
            $report = $reportName
        }
    }

# Create the report if it doesn't exist
} elseif($reports.total -lt 1){
    # Create Report
    $createReportPayload = @{
        "name" = "$($report_name)"
        "reportTemplate" = "ProtectionTasksDetails"
    }
    $createReport = Invoke-RubrikRESTCall -Endpoint "report" -api internal -Method POST -Body $createReportPayload

    write-host "Report Not Found with Name $($report_name). Creating Report in Rubrik..."
    do{
        $createReport = Invoke-RubrikRESTCall -Endpoint "report/$($createReport.id)" -api internal -Method GET
        write-host "Generating $($report_name). This may take a few minutes. Current Status: $($createReport.updateStatus)"
        start-sleep 10
    }while($createReport.updateStatus -ne 'Ready')

    $patchReportPayload = @{
        "name" = $report_name
        "filters" = @{
            "dateConfig" = @{
                "period" = "PastDay"
             }
        }
        "chart0" = @{
            "id" = "chart0"
            "name" = "Daily Protection Tasks by Status"
            "chartType" = "Donut"
            "attribute" = "TaskStatus"
            "measure" = "TaskCount"
        }
        "chart1" = @{
            "id" = "chart1"
            "name" = "Daily Failed Tasks by Object Name"
            "chartType" = "VerticalBar"
            "attribute" = "ObjectName"
            "measure" = "FailedTaskCount"
        }
        "table" = @{
            "columns" = @("TaskStatus","TaskType","ObjectName","ObjectType","Location","SlaDomain","FailureReason","StartTime","EndTime","Duration","DataTransferred","LogicalDataProtected","DataStored","NumFilesTransferred","EffectiveThroughput")
        }
    }
    write-host "Customizing Report with Additional Fields"
    $report = Invoke-RubrikRESTCall -Endpoint "report/$($createReport.id)" -Method PATCH -api internal -Body $patchReportPayload
    do{
        $report = Invoke-RubrikRESTCall -Endpoint "report/$($createReport.id)" -api internal -Method GET
        write-host "Generating $($report_name). This may take a few minutes. Current Status: $($createReport.updateStatus)"
        start-sleep 10
    } while($report.updateStatus -ne 'Ready')

    $report = Invoke-RubrikRESTCall -Endpoint "report/$($createReport.id)" -api internal -Method GET
}

# Get the Table contents for the report
$report_data = Get-RubrikReportDataFull -rubrik_ip $cluster_ip -rubrik_user $RubrikUser -rubrik_pass $rubrik_pass -report_id $report.id

# Create HTML File contents, with Report Header and Table Headers
$output_html += $style_head
$output_html += "<hr>"
$output_html += '<IMG style="padding: 0 15px; float: left;" SRC="data:image/gif;base64,iVBORw0KGgoAAAANSUhEUgAAAXUAAAC0CAMAAABc4ExfAAAARVBMVEUlsaMlsKMlsZwnr7ckspImr7Aoq5QmsKo5kn9jZmtjZmtjZmtjZmtjZmtjZmtjZmtjZmtjZmsmr7YlsaUkspkkso8nrsJo0+JyAAAAEXRSTlOCn1/NxzgAEgEWPVuApL/V7xQTl6oAAAphSURBVHja7d3pdqowEABgFgmHQNisvv+jXnayTBZCkKtn5l9bxfYzDVlmYkQwPh8REqA6qmOgOqpjoDqqY6A6qmOgOqqjOgaqozoGqqM6BqqjOgaqozqqY6A6qmOgOqpjoDqqY6A6qmOcVM+zHOk+rZ68Xq8E7T6rPqIj+7XqSm8yoyvs2OuEU8/i1+sBosvsj7+/OEPQAOrZY+KF0SX2vzEe6H5WfTEX1Hn0v79EVkf3s+r5xqtDF9hn9Ofzid37GfVMVZfRefYV/YmN/VQPE8vqKjrHvqLHiHrubhqL6hD6zo7oocYwMa8Oo2/siB5svB7v6jr0lR3Rw82S4lVdj76w/3/oRVmNUXzuFecXpOdXBOJZ3YQ+s/9/LZ11U7SfQ59fsCtOq4/sNvSJ/f/rXmpXhFBRLS9Iz6uTKLKiv57J+LD/VJ1+o/oQDxv68/Ef3rO+Sj2LxEjyzIr+TIdeSHpejuru6vlLjohENvTn8JinHDmqO6tHivprmy5p0eN55ChGhOrn1Gd2EzqqX6A+shvRUf0KdRKb0VH9EnWInUNH9WvUVXYeXVXvf1m9ZE3Dyk+oy+wCuqLe/7B6sSzx1MUpdS6ZxaAusovoREHf1W9KlblOfUHvOnZGfZh8PnIHdZ5dQicK+qaep32f/ZI67bagJ9THdZaV3ai+s8voREFf1Uf0Pv4l9WpXr/zV50WAhd2svrIr6ERBX9Qn9L7Pf1O99ldf5vszu6r+RxR2FZ0o6LP6gn5HY/+EOvNW39a7JnZF/U9UH9kBdKKgT+or+h2N/TL1clcvvdW3vJeJPZLNZfXh8dAeqYI+qu/oNzT268YwzYreFr7q/NLuwB4p6LI6iaE9UgV9UOfQb2js16nTdkGn3iPHjFd+iF9O6GorTSK1ZiCWzMfRYip++TtzUzpdu6Yn5qbRY4/h6+QhRuzWSPM4FWN4YyLuy+iHephxekopDbcOk8SheoI8vrmI5ntWvxJulnoSfeheElR3UU+46dJ59JvZv0U94adLAdDvZf8S9USYLoVAv5X9O9QTYdweBv1O9q9QF9LqTrELk6P72L9BXcplPMEuot/H/gXqSgKpN7uM3r8TVIfVgaxdT3YV/e3BTqf8+5KGVS+Gy7KaDRd2z65eag9cnnFUHUyV9mKH0J3YaVUPMRc6lNuiXkOhn8tRsulnhVG9qJp9hbZrDCUV1Xg5Nl2uqNptKb2Af1mrejE9uOZSCiI9uhc7jO7C3m7bBAXjdLacf1PlRQvtHYvq4kU7aPFqI91356jwRu0PaYCdJJ160SibrJEB3YNdh+7Avm2JFY1gQyVD43O16lUHRV2Y1Wnbweod+MuA6tyfI6gbKjEOsuvR7ewbhIhekwDq0jX3aEuTuojO70y7q3MvXfM9jLH85RC7Cd3Kvv5qdQc29TPqVIcub/KL6kxEb4iHOofeFJy6peboALsZ3cYOozByXr1qu+4IO4UfWHqow+gkshZ6ObPb0C3s8h/ZSPVz/ur8Retx6NhqNWH1Rm7qruoadGGXVJMq7boJFNvQ329X9XYakw0jrpIEVK+3MTcVOg9qUm+mJ1HG6HF1HTqvrstPdy2vS63oruqsMMx5fNUbcWTBDWqaQq9emX9Zo7oWnUQPa6GX68QysqKnburMONP0VFf4uAFKpVUvyQl1pn1fo+xlL/Ty6GIg9HfmpN6QC9QBPq4pFhr1ipxQ16MPY5gsFDrPfhyd2NrXKXXwmkUL/3dROMfooLoBfc2HCYK+s3ugE0tTP6XOzFN/iZdanuakbkKf5qZZKPSV3Qed2P7UE+raNluB/wvU1qs7qBvR53WYLBT6zO6FTmx/6gl1bfe89TEMVC+81c3oa61GKPSR3Q+ddJbFaX91ffe8N3ZQnfiqW9DX9fUsFPrA7odObA3MX50Ztiyg95rCl3NXbyzo215SFgodZHdJLLU1MH/10vCqDdAJnVa3oe/7plkodIDdKZv3OvXCYdONXaGuQ+dyBLJQ6Aq7Wwr1ZeqN6VVL4KnUdhN2VNffT7ilrSwUusTumLduGa77q9fG3doL1fU3FH5BMQuFLrC7FgvY/q291dnRf7Fg6torCMu4WSh0jt25QuMy9eo+dd2NXFw8z0Khb+zuZTE/qa6ZfUhbFlm4E0jjY+jXqTv1681F6i11UCdZ/AhVQBS/0yMFYPeqh72bsso8kLmyRuvY2YKXqRtPjK2uUGcuq1+PdaA+n8sYS2eOOLbYTJ4bDZdOXTeSzqkX/rMkZpibeqtTYZkZXunNOPRnRBLlUCPFK49TtVIvBVICouPr6z7q1H9FoAUeE0Sd26lipra+3EjV0zCfMvq4L53K7OrqSySM20O1dXpYndm7dXD165S6kX2q8uXR7epL3ovMDqpz7Mlt6oYuhkEz4jDqhu3w+cwM4YNIbOpbspHEDqvv7Hkg9cptCYtXZ9aFXnaBOs9eAmOYiP9MDIs6l+ElsmvUV3brYMmmXukJGcxUd7bGzsDJTCh1/kQTqqrn/GdimNWFtDqBXae+sOeh1Bu3W6I4jDAvOEo/D6bOsYuzpWiTXmekqnqvQRfZteoTu31eYFPX7yGXmul3bVn923uA8iJ1opktLWdzPfZsxkg9mFGHLrDr1YcBZJqfVt9atDz+3QYLDdGqQ+w7ekOuUtfMloBTNNWDGbXob47ToB5kbqo7RHH/fmVQV3Mn9fe6kOqkgbo5q3q/q4Op0hv75eoFWNiizZtTsksFW75MqSYXqoPDdpt6v6tr8tNX9svVuf/Wbs1r5nIgVCQ5k3ovuyuZaaMtqDqX17ezW9T7XV1bFLCwX69e8Enn7VhM2Bq3hrd8GOlZtWUtNqw61JWZ1ftd3VCJMbNfry6VxFkXsrd1mMZUIVOSi9WBzGyjer+rG8tfJvYPqPPTDofdg20NoWgOPS+0ujpbMqn3u7ql5mhk/4S6trWDWzZc5SPToDeUfECdG7bP/aAqkyjoqb3Qa2BPjxV/+amTonav1uXX1+E6vMo4H7Ort47q3ECAwup5Kp+Gmdir6wb2BHgnjkTjkkdB+DMG4DGhgtAoQ0VT+RM3RDWsy8NJH6V+044JAyaoF8jEyF2q694xyaXnHdzvGw9IBM5IhNz5CrqW6Z8yX3E1EE9vqA2fwGn/VTSPEF8Q+NHyM6e+N7ejvz97HuxyfMiRE0dmrCrACSgBdpTt5GlKst5e6JWmt3/w3ddEZEcfxzCZvbrucEeO6kb0cbyeWavr3sgeSn0evZCdXV/+8kb2QOrLkJFs7Iaaozeyh1Ffx+lkZTcVer2RPYj6Njlax/HG6ro3sgdRT3tRHWTfJkOu2UYYRvWsl9UB9n0Gerg4A9Xd2rrKzgljWw/Ur0eKusTON+vFPMJ+/fR4PUkldYFd6Esm8wRFg6wIDO5S7ZKmA4/QPJw6cJfFu+YN6gs7on9WnWTpsUIvjBDqGKiO6hiojuoYqI7qqI6B6qiOgeqojoHqqI6B6qiO6hiojuoYqI7qGKiO6hiojuoYqI7qqI6B6qiOgeqojoHqqI6B6qiO6hiojuoYqP4z8Q92ktUsazqmOgAAAABJRU5ErkJggg==">'
$output_html += '<p style="margin-top: 20px;">'
$output_html += "<h1>Server Backups - last 24 hours</h1>"
$output_html += "<h3>Rubrik Cluster: $($global:rubrikConnection.server)</h3>"
$output_html += "<h3>Date/Time: $(Get-Date)</h3>"
$output_html += "</p>"
$output_html += "</br>"
$output_html += "<hr>"
$output_html += "<table>"
$output_html += "<th>Task Type</th>"
$output_html += "<th>SLA</th>"
$output_html += "<th>Object Type</th>"
$output_html += "<th>Hostname</th>"
$output_html += "<th>Location</th>"
$output_html += "<th>Object Name</th>"
$output_html += "<th>Job Start Time</th>"
$output_html += "<th>Job End Time</th>"
$output_html += "<th>Job File Count</th>"
$output_html += "<th>Job Throughput (Kb/s)</th>"
$output_html += "<th>Job Protected Size (GB)</th>"
$output_html += "<th>Logical Data Protected (GB)</th>"
$output_html += "<th>Job Status</th>"
$output_html += "<th>Failure Reason</th>"

# Loop through table data
foreach($report_row in $report_data){

    # Format report values
    $rubrikHostname = $report_row.Location.split('\')[0]
    $EffectiveThroughput = [math]::round($report_row.EffectiveThroughput / 1Kb, 3)
    $DataStored = [math]::round($report_row.DataStored / 1Gb, 3)
    $ObjectSize = [math]::round($report_row.LogicalDataProtected / 1Gb, 3)

    # Remove Replication events
    if(($report_row.TaskType -ne 'Replication') -and ($report_row.TaskType -ne 'LogReplication')){

        #Filter against hostnames
        ### v -- disable this block to get all events
        if($report_row.ObjectType -eq 'VmwareVirtualMachine'){
            if($serverList -contains $report_row.ObjectName){
                $output_html += "<tr>"
                $output_html += "<td>$($report_row.TaskType)</td>"
                $output_html += "<td>$($report_row.SlaDomain)</td>"
                $output_html += "<td>$($report_row.ObjectType)</td>"
                $output_html += "<td>$($rubrikHostname)</td>"
                $output_html += "<td>$($report_row.Location)</td>"
                $output_html += "<td>$($report_row.ObjectName)</td>"
                $output_html += "<td>$($report_row.StartTime)</td>"
                $output_html += "<td>$($report_row.EndTime)</td>"
                $output_html += "<td>$($report_row.NumFilesTransferred)</td>"
                $output_html += "<td>$($EffectiveThroughput)</td>"
                $output_html += "<td>$($DataStored)</td>"
                $output_html += "<td>$($ObjectSize)</td>"
                $output_html += "<td>$($report_row.TaskStatus)</td>"
                $output_html += "<td>$($report_row.FailureReason)</td>"
                $output_html += "</tr>"
            }
        } else {
            if($rubrikHostname -in $serverList){
                $output_html += "<tr>"
                $output_html += "<td>$($report_row.TaskType)</td>"
                $output_html += "<td>$($report_row.SlaDomain)</td>"
                $output_html += "<td>$($report_row.ObjectType)</td>"
                $output_html += "<td>$($rubrikHostname)</td>"
                $output_html += "<td>$($report_row.Location)</td>"
                $output_html += "<td>$($report_row.ObjectName)</td>"
                $output_html += "<td>$($report_row.StartTime)</td>"
                $output_html += "<td>$($report_row.EndTime)</td>"
                $output_html += "<td>$($report_row.NumFilesTransferred)</td>"
                $output_html += "<td>$($EffectiveThroughput)</td>"
                $output_html += "<td>$($DataStored)</td>"
                $output_html += "<td>$($ObjectSize)</td>"
                $output_html += "<td>$($report_row.TaskStatus)</td>"
                $output_html += "<td>$($report_row.FailureReason)</td>"
                $output_html += "</tr>"
            }
        }


        ### ^ -- disable this block

        ### v -- enable this block to get all events
        <#
        $output_html += "<tr>"
        $output_html += "<td>$($report_row.TaskType)</td>"
        $output_html += "<td>$($report_row.SlaDomain)</td>"
        $output_html += "<td>$($report_row.ObjectType)</td>"
        $output_html += "<td>$($rubrikHostname)</td>"
        $output_html += "<td>$($report_row.Location)</td>"
        $output_html += "<td>$($report_row.ObjectName)</td>"
        $output_html += "<td>$($report_row.StartTime)</td>"
        $output_html += "<td>$($report_row.EndTime)</td>"
        $output_html += "<td>$($report_row.NumFilesTransferred)</td>"
        $output_html += "<td>$($EffectiveThroughput)</td>"
        $output_html += "<td>$($DataStored)</td>"
        $output_html += "<td>$($ObjectSize)</td>"
        $output_html += "<td>$($report_row.TaskStatus)</td>"
        $output_html += "<td>$($report_row.FailureReason)</td>"
        $output_html += "</tr>"
        #>
        ### ^ -- enable this block
    }

}

# Close and output HTML Report
$output_html += "</table>"
$output_html > $output_file_name

# Disconnect Session from Rubrik
Write-Host 'Disconnecting from Rubrik'
Disconnect-Rubrik -Confirm:$false

write-host "Script completed, results in output file: $(output_file_name)"

# Use this block to email report out (requires a working SMTP server) (remove # at the start of the lines)
#$SmtpServer = "stmp.demo.lab"
#Send-MailMessage -BodyAsHtml -SmtpServer $SmtpServer -To "to@demo.com" -From "reports@demo.com" -Body ($output_html | out-string) -Subject "Rubrik Report - 24 Hour Audit Report"