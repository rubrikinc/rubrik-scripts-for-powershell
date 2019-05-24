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
$vCDHost = "notavcdcell.rubrik.com"
$orgId = $null

$Global:vCDURL = "https://$($vCDHost)/api"
$Global:Authorization = ""
$Global:Accept = "application/*+xml;version=30.0"
$Global:xvCloudAuthorization
$Global:WebResp = ""
$Global:protectedMetadata = New-Object System.Data.DataTable

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$protectedMetadata.Columns.Add("vCDCell", "System.String") | Out-Null
$protectedMetadata.Columns.Add("vAppName", "System.String") | Out-Null
$protectedMetadata.Columns.Add("vAppId", "System.String") | Out-Null
$protectedMetadata.Columns.Add("vmName", "System.String") | Out-Null
$protectedMetadata.Columns.Add("vmId", "System.String") | Out-Null
$protectedMetadata.Columns.Add("Metadata", "System.String") | Out-Null
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
    $Global:WebResp = Invoke-WebRequest -Method Post -Headers $headers -Uri "$($Global:vCDURL)/sessions"
    $Global:xvCloudAuthorization = $Global:WebResp.Headers["x-vcloud-authorization"]

}

Function Get-vCloudRequest($endpoint, $contenttype, $orgId){
    $reqHeaders = @{}
    
    if($null -eq $orgId){
        $reqHeaders['x-vcloud-authorization'] = $Global:xvCloudAuthorization
        $reqHeaders['Accept'] = $Global:Accept
    } else {
        $reqHeaders['x-vcloud-authorization'] = $Global:xvCloudAuthorization
        $reqHeaders['Accept'] = $Global:Accept
        $reqHeaders['X-VMWARE-VCLOUD-TENANT-CONTEXT'] = $orgId
    }
    
    if($null -eq $contenttype){
        $reqHeaders['Content-Type'] = "text/plain"
    } else {
        $reqHeaders['Content-Type'] = $contenttype
    }

    [xml]$Response = Invoke-WebRequest -Method GET -Headers $reqHeaders -Uri "$($Global:vCDURL)/$endpoint"
    Return $Response
}

Function Get-VMMetadata($vAppID, $vAppName, $orgID){

    $vAppNoVapp = $vAppID.replace("vapp-","")
    
    $VMRecords = Get-vCloudRequest -endpoint "query?type=vm&filter=container==$($vAppNoVapp)" -orgId $orgID

    foreach($VMRecord in $VMRecords.QueryResultRecords.VMRecord){

        $vmHref = $VMRecord.href
        $VMID = $vmHref.Substring($vmHref.LastIndexOf("/") + 1)

        Write-Output "Grabbing VM Metadata for VM: $($VMRecord.name)"
        $VMMetadata = Get-vCloudRequest -endpoint "vApp/$($VMID)/metadata" -orgId $ID -contenttype "application/vnd.vmware.vcloud.metadata+xml;version=5.5"

        foreach($VMMeta in $VMMetadata.Metadata.MetadataEntry){
    
            $nRow = $protectedMetadata.NewRow()
            $nRow.vCDCell = $vCDHost
            $nRow.vAppName = $vAppName
            $nRow.vAppId = $vAppID
            $nRow.vmName = $VMRecord.name
            $nRow.vmId = $VMID
            $nRow.Metadata = "VM"
            $nRow.MetadataKey = $VMMeta.Key
            $nRow.MetadataDomain = $VMMeta.Domain.visibility
            $nRow.MetadataType = $VMMeta.TypedValue.type
            $nRow.MetadataValue = $VMMeta.TypedValue.Value
            $protectedMetadata.Rows.Add($nRow)

        }

    }
}

New-vCloudLogin –Username "$($Username)@SYSTEM” –Password $Password
$Orgs = Get-vCloudRequest -endpoint "org"

foreach($Org in $Orgs.OrgList.Org){
    
    $orgHref = $Org.href
    $ID = $orgHref.Substring($orgHref.LastIndexOf("/") + 1)

    $vApps = Get-vCloudRequest -endpoint "vApps/query" -orgId $ID

    foreach($vApp in $vApps.QueryResultRecords.VAppRecord){
        
        Write-Output "Running for $($vApp.name)"

        $vAppHref = $vApp.href
        $vAppID_substring = $vAppHref.Substring($vAppHref.LastIndexOf("/") + 1)
        
        Write-Output "Grabbing vApp Metadata"
        $vAppMetadata = Get-vCloudRequest -endpoint "vApp/$($vAppID_substring)/metadata" -orgId $ID -contenttype "application/vnd.vmware.vcloud.metadata+xml;version=5.5"

        foreach($vAppMeta in $vAppMetadata.Metadata.MetadataEntry){

            $nRow = $protectedMetadata.NewRow()
            $nRow.vCDCell = $vCDHost
            $nRow.vAppName = $vApp.name
            $nRow.vAppId = $vAppID_substring
            $nRow.vmID = ""
            $nRow.vmName = ""
            $nRow.Metadata = "vApp" 
            $nRow.MetadataKey = $vAppMeta.Key
            $nRow.MetadataDomain = $vAppMeta.Domain.visibility
            $nRow.MetadataType = $vAppMeta.TypedValue.type
            $nRow.MetadataValue = $vAppMeta.TypedValue.Value
            $protectedMetadata.Rows.Add($nRow)

        }

        Get-VMMetadata -vAppID $vAppID_substring -vAppName $vApp.name -orgID $ID
        
    }

}
Write-Output $protectedMetadata.Rows.Count

Write-Output $protectedMetadata | Format-Table -Force
$date = Get-Date -format "yyyyMMddHHmmss"
Write-Output "Exporting to vcd_metadata_export_$($date).csv"
$protectedMetadata | Export-Csv ./exports/vcd_metadata_export_$($date).csv -NoType