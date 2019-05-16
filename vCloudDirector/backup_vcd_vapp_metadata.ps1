<#
    .SYNOPSIS
        Will export all vCD Metadata from vApps to a file which is best executed as a pre-script on a management VM

    .DESCRIPTION
        Will Loop through all Orgs and grab all vApps and then read the vApp Metadata. Once Gathered, it will be written to a datatable
        Once complete, the script will output the values to a datatable

    .PARAMETER JobFile
        None

    .INPUTS
        Required to updated the following parameters:
            $Username - This will be a vCD Admin User
            $Password - This will be a vCD Admin User Password
            $vCDHost - The address of the vCD Cell you want to export the metadata for

    .OUTPUTS
        Datatable - view of all metadata
        CSV File - Content of the aformentioned Datatable

    .EXAMPLE
        ./backup_vcd_vapp_metadata.ps1

    .LINK
        None

    .NOTES
        Name:       Backup vApp Metadata
        Created:    16th May 2019
        Author:     Andy Draper (Draper1)

#>
$Username = "notauser"
$Password = "notapass"
$vCDHost = "notacell.rubrik.com"
$orgId = $null

$Global:vCDURL = "https://$($vCDHost)/api"
$Global:Authorization = ""
$Global:Accept = "application/*+xml;version=30.0"
$Global:xvCloudAuthorization
$Global:WebResp = ""
$Global:protectedMetadata = New-Object System.Data.DataTable

if (-not ([System.Management.Automation.PSTypeName]'ServerCertificateValidationCallback').Type)
{
$certCallback = @"
    using System;
    using System.Net;
    using System.Net.Security;
    using System.Security.Cryptography.X509Certificates;
    public class ServerCertificateValidationCallback
    {
        public static void Ignore()
        {
            if(ServicePointManager.ServerCertificateValidationCallback ==null)
            {
                ServicePointManager.ServerCertificateValidationCallback += 
                    delegate
                    (
                        Object obj, 
                        X509Certificate certificate, 
                        X509Chain chain, 
                        SslPolicyErrors errors
                    )
                    {
                        return true;
                    };
            }
        }
    }
"@
    Add-Type $certCallback
 }
[ServerCertificateValidationCallback]::Ignore()

$protectedMetadata.Columns.Add("vCDCell", "System.String") | Out-Null
$protectedMetadata.Columns.Add("vAppName", "System.String") | Out-Null
$protectedMetadata.Columns.Add("vAppId", "System.String") | Out-Null
$protectedMetadata.Columns.Add("MetadataKey", "System.String") | Out-Null
$protectedMetadata.Columns.Add("MetadataDomain", "System.String") | Out-Null
$protectedMetadata.Columns.Add("MetadataType", "System.String") | Out-Null
$protectedMetadata.Columns.Add("MetadataValue", "System.String") | Out-Null

Function New-vCloudLogin($Username, $Password){
    
    $Pair = "$($Username):$($Password)"
    $Bytes = [System.Text.Encoding]::ASCII.GetBytes($Pair)
    $Base64 = [System.Convert]::ToBase64String($Bytes)
    $Global:Authorization = "Basic $base64"
    $headers = @{ Authorization = $Global:Authorization; Accept = $Global:Accept; "Content-Type" = "text/plain"}
    $Global:WebResp = Invoke-WebRequest -Method Post -Headers $headers -Uri "$($Global:vCDURL)/sessions" #-SkipCertificateCheck

    $Global:xvCloudAuthorization = $Global:WebResp.Headers["x-vcloud-authorization"]
    Write-Host $Global:WebResp.Headers["x-vcloud-authorization"]

}

Function Get-vCloudRequest($endpoint, $contenttype, $orgId){
    $reqHeaders = @{}
    
    if($orgId -eq $null){
        $reqHeaders['x-vcloud-authorization'] = $Global:xvCloudAuthorization
        $reqHeaders['Accept'] = $Global:Accept
    } else {
        $reqHeaders['x-vcloud-authorization'] = $Global:xvCloudAuthorization
        $reqHeaders['Accept'] = $Global:Accept
        $reqHeaders['X-VMWARE-VCLOUD-TENANT-CONTEXT'] = $orgId
    }
    
    if($contenttype -eq $null){
        $reqHeaders['Content-Type'] = "text/plain"
    } else {
        $reqHeaders['Content-Type'] = $contenttype
    }

    foreach($header in $reqHeaders){
        $header
    }

    [xml]$Response = Invoke-RestMethod -Method GET -Headers $reqHeaders -Uri "$($Global:vCDURL)/$endpoint" #-SkipCertificateCheck
    Return $Response
}

$NewAuth = New-vCloudLogin –Username "$($Username)@SYSTEM” –Password $Password
$Orgs = Get-vCloudRequest -endpoint "org"


foreach($Org in $Orgs.OrgList.Org){
    
    $orgHref = $Org.href
    $ID = $orgHref.Substring($orgHref.LastIndexOf("/") + 1)

    $vApps = Get-vCloudRequest -endpoint "vApps/query" -orgId $ID

    foreach($vApp in $vApps.QueryResultRecords.VAppRecord){
        
        Write-Output "Running for $($vApp.name)"

        $vAppHref = $vApp.href
        $vAppID_substring = $vAppHref.Substring($vAppHref.LastIndexOf("/") + 1)
        
        Write-Output "Grabbing Metadata"
        $vAppMetadata = Get-vCloudRequest -endpoint "vApp/$($vAppID_substring)/metadata" -orgId $ID -contenttype "application/vnd.vmware.vcloud.metadata+xml;version=5.5"

        foreach($vAppMeta in $vAppMetadata.Metadata.MetadataEntry){

            $nRow = $protectedMetadata.NewRow()
            $nRow.vCDCell = $vCDHost
            $nRow.vAppName = $vApp.name
            $nRow.vAppId = $vAppID_substring
            $nRow.MetadataKey = $vAppMeta.Key
            $nRow.MetadataDomain = $vAppMeta.Domain.visibility
            $nRow.MetadataType = $vAppMeta.TypedValue.type
            $nRow.MetadataValue = $vAppMeta.TypedValue.Value
            $protectedMetadata.Rows.Add($nRow)

        }

    }
}

Write-Output $protectedMetadata | Format-Table -Force
$date = Get-Date -format "yyyyMMddHHmmss"
Write-Output "Exporting to vcd_metadata_export_$($date).csv"
$protectedMetadata | Export-Csv ./exports/vcd_metadata_export_$($date).csv -NoType