param (
    [string]$rubrik = $(Read-Host -Prompt 'Input your Rubrik IP or Hostname'),
    [string]$SLA = $(Read-Host -Prompt "Enter SLAs ['SLA1','SLA2,'etc'] or just hit enter to report on all")
)

#$items_to_report = ('VmwareVirtualMachine','Mssql','LinuxFileset','WindowsFileset','NasFileset')
$items_to_report = @{
 "VmwareVirtualMachine" = @{"url" = "/v1/vmware/vm/{0}/snapshot"; "array"  = "data"}
 "Mssql" = @{"url" = "/v1/mssql/db/{0}/snapshot"; "array" = "data"}
 "LinuxFileset" = @{"url" = "/v1/fileset/{0}"; "array" = "snapshot"}
 "WindowsFileset" = @{"url" = "/v1/fileset/{0}"; "array" = "snapshot"}
 "NasFileset" = @{"url" = "/v1/fileset/{0}"; "array" = "snapshot"}
 "ManagedVolume" = @{"url" = "/internal/managed_volume/{0}/snapshot"; "array" = "data"}
}
$selected = ( "Location", "ObjectName", "ObjectId", "SlaDomain")


[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if (-not("dummy" -as [type])) {
    add-type -TypeDefinition @"
using System;
using System.Net;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

public static class Dummy {
    public static bool ReturnTrue(object sender,
        X509Certificate certificate,
        X509Chain chain,
        SslPolicyErrors sslPolicyErrors) { return true; }

    public static RemoteCertificateValidationCallback GetDelegate() {
        return new RemoteCertificateValidationCallback(Dummy.ReturnTrue);
    }
}
"@
}

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = [dummy]::GetDelegate()

$limit = 100
$object_report_name = "Object Protection Summary"

# Check for Credentials
New-Item -ItemType Directory -Force -Path "$($PSScriptRoot)\.creds" | out-null
$Credential = ''
$CredentialFile = "$($PSScriptRoot)\.creds\$($rubrik).cred"
if (Test-Path $CredentialFile){
  write-host "Credentials found for $($rubrik)"
  $Credential = Import-CliXml -Path $CredentialFile
}
else {
  write-host "$($CredentialFile) not found"
  $Credential = Get-Credential -Message "Credentials not found for $($rubrik), please enter them now."
  $Credential | Export-CliXml -Path $CredentialFile
}

$auth = [System.Text.Encoding]::UTF8.GetBytes(("{0}:{1}" -f $Credential.UserName.ToString(),([Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)))))
$auth = [System.Convert]::ToBase64String($auth)
$headers = @{
  Authorization = "Basic {0}" -f $auth
  Accept = 'application/json'
}
function get-rubrik-objects ($rubrik, $object_report_id, $SLA) {
  $out = @{}
  $out.report_data = @()
  $payload = @{
    "limit" = $limit
  }
  $uri = [uri]::EscapeUriString("https://$($rubrik)/api/internal/report/$($object_report_id)/table")
  $hasMore = $true
  while ($hasMore -eq $true){
    if ($null -ne $cursor){
      $payload['cursor'] = $cursor
    }
    $report_results = Invoke-RestMethod -Headers $headers -Method POST -Uri $($uri) -Body $(convertto-json $payload) 
    $cursor = $report_results.cursor
    $hasMore = $report_results.hasMore
    $out.report_columns = $report_results.columns
    if ($SLA){
      foreach ($l in $report_results.dataGrid){
        if ($SLA -contains $l[$report_results.columns.indexOf('SlaDomain')]){
          $out.report_data += ,$l
        }
      }
    }
    else{
      $out.report_data += $report_results.dataGrid
    }
  }
  return ($out)
}

try{
  $uri = [uri]::EscapeUriString("https://$($rubrik)/api/internal/report?name=$($object_report_name)")
  $object_report_list = Invoke-RestMethod -Headers $headers -Method GET -Uri $uri 
  foreach($object_report in $object_report_list.data){
    if ($object_report_name -eq $object_report.name){
      $object_report_id = $object_report.id
    }
  }
}
catch{
  write-host "Failed to call $($uri)"
  write-host "Got : $($_.Exception)"
}

if ($object_report_id){
  $rr = get-rubrik-objects $rubrik $object_report_id $SLA
}

$columns = $selected
$columns += "LastSnapshot"
$columns += "LastSnapshotStatus"
$columns += "LastArchive"
$columns += "LastArchiveStatus"
$columns_out = '"{0}"' -f ($columns -join '","')
Write-Host $columns_out

foreach ($report_line in $rr.report_data){
  $last_status = ''
  if ($items_to_report.Keys -notcontains $report_line[$($rr.report_columns.indexOf("ObjectType"))]){ continue }
  $report_out = @()
  foreach($f in $selected){
    $report_out += $report_line[$($rr.report_columns.indexOf($f))]
  }
  $object_id = [uri]::EscapeDataString($report_line[$rr.report_columns.indexOf('ObjectId')])
  $uri = "https://$($rubrik)/api/internal/event?limit=1&event_type=Backup&object_ids=$($object_id)"
  $event_results = (Invoke-RestMethod -Headers $headers -Method GET -Uri $($uri)) 
  if (($event_results.data).count -eq 0){
    $report_out += "None Found"
    $report_out += "None Found"
  }
  else{
    $report_out += "$($event_results.data.time)"
    $report_out += "$($event_results.data.eventStatus)"
  }
  $uri = "https://$($rubrik)/api/internal/event?limit=1&event_type=Archive&object_ids=$($object_id)"
  $event_results = (Invoke-RestMethod -Headers $headers -Method GET -Uri $($uri)) 
  if (($event_results.data).count -eq 0){
    $report_out += "None Found"
    $report_out += "None Found"
  }
  else{
    $report_out += "$($event_results.data.time)"
    $report_out += "$($event_results.data.eventStatus)"
  }
  $report_out = '"{0}"' -f ($report_out -join '","')
  Write-Host $report_out
}

exit