<#
    .SYNOPSIS
        Will restore vCD Metadata to vApps from a file which is created by a pre-script on a management VM

    .DESCRIPTION
        Will loop through all CSV Data provided confirming if the vApp Metadata is to be restore
        We will check if the vApp ID already exists and restore to that vAppID
        If not, we will ask for the name of the vApp to restore and find it by name

    .PARAMETER JobFile
        None

    .INPUTS
        Required to updated the following parameters:
            $Username - This will be a vCD Admin User
            $Password - This will be a vCD Admin User Password
            $vCDHost - The address of the vCD Cell you want to export the metadata for

    .OUTPUTS
        None

    .EXAMPLE
        ./restore_vcd_vapp_metadata.ps1

    .LINK
        None

    .NOTES
        Name:       Restore vApp Metadata
        Created:    16th May 2019
        Author:     Andy Draper (Draper1)

#>
$Username = "notauser"
$Password = "notapass"
$vCDHost = "notavcdcell.rubrik.com"

$Global:vCDURL = "https://$($vCDHost)/api"
$Global:Authorization = ""
$Global:Accept = "application/*+xml;version=30.0"
$Global:xvCloudAuthorization = ""
$Global:WebResp = ""

Function New-vCloudLogin($Username, $Password){
    
    $Pair = "$($Username):$($Password)"
    $Bytes = [System.Text.Encoding]::ASCII.GetBytes($Pair)
    $Base64 = [System.Convert]::ToBase64String($Bytes)
    $Global:Authorization = "Basic $base64"
    $headers = @{ Authorization = $Global:Authorization; Accept = $Global:Accept; "Content-Type" = "text/plain"}
    try{
        $Global:WebResp = Invoke-WebRequest -Method Post -Headers $headers -Uri "$($Global:vCDURL)/sessions" -SkipCertificateCheck
    } catch {
        $_.Exception | format-list -force
    }
    
    $Global:xvCloudAuthorization = $Global:WebResp.Headers["x-vcloud-authorization"]

}

Function Get-vCloudRequest($endpoint, $contenttype, $orgId){
    $reqHeaders = @{}
    
    if($orgId -eq $null){
        $reqHeaders['x-vcloud-authorization'] = $Global:xvCloudAuthorization[0]
        $reqHeaders['Accept'] = $Global:Accept
    } else {
        $reqHeaders['x-vcloud-authorization'] = $Global:xvCloudAuthorization[0]
        $reqHeaders['Accept'] = $Global:Accept
        $reqHeaders['X-VMWARE-VCLOUD-TENANT-CONTEXT'] = $orgId
    }
    
    if($contenttype -eq $null){
        $reqHeaders['Content-Type'] = "text/plain"
    } else {
        $reqHeaders['Content-Type'] = $contenttype
    }

    [xml]$Response = Invoke-RestMethod -Method GET -Headers $reqHeaders -Uri "$($Global:vCDURL)/$endpoint" -SkipCertificateCheck
    Return $Response
}

Function Post-vCloudRequest($endpoint, $payload, $contenttype, $orgId){
    $reqHeaders = @{}
    
    if($orgId -eq $null){
        $reqHeaders['x-vcloud-authorization'] = $Global:xvCloudAuthorization[0]
        $reqHeaders['Accept'] = $Global:Accept
    } else {
        $reqHeaders['x-vcloud-authorization'] = $Global:xvCloudAuthorization[0]
        $reqHeaders['Accept'] = $Global:Accept
        $reqHeaders['X-VMWARE-VCLOUD-TENANT-CONTEXT'] = $orgId
    }
    
    if($contenttype -eq $null){
        $reqHeaders['Content-Type'] = "text/plain"
    } else {
        $reqHeaders['Content-Type'] = $contenttype
    }

    [xml]$Response = Invoke-RestMethod -Method POST -Headers $reqHeaders -body $payload -Uri "$($Global:vCDURL)/$endpoint" -SkipCertificateCheck
    
    Return $Response
}

Function Get-FileName($initialDirectory)
{
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = $initialDirectory
    $OpenFileDialog.filter = "CSV (*.csv)| *.csv"
    $OpenFileDialog.ShowDialog() | Out-Null
    Return $OpenFileDialog.FileName
}

#Import CSV for Reading
$CSV_Data =  Get-FileName(".")
$CSV = import-csv -Path $CSV_Data

$NewAuth = New-vCloudLogin –Username "$($Username)@SYSTEM” –Password $Password

foreach($row in $CSV){

    $vAppResp = "N"
    $vAppResp = Read-Host "Would you like to restore Metadata Key: $($row.MetadataKey), Value: $($row.MetadataValue) and Domain: $($row.MetadataDomain)  for vApp $($row.vAppName)? Y/N (Default: N): "
    
    if($vAppResp -eq "Y"){

        $Orgs = Get-vCloudRequest -endpoint "org"
        foreach($Org in $Orgs.OrgList.Org){
    
            $orgHref = $Org.href
            $ID = $orgHref.Substring($orgHref.LastIndexOf("/") + 1)

            $vApps = Get-vCloudRequest -endpoint "vApps/query" -orgId $ID
            $vappFound = $false

            foreach($vApp in $vApps.QueryResultRecords.VAppRecord){

                $vAppHref = $vApp.href
                $vAppID_substring = $vAppHref.Substring($vAppHref.LastIndexOf("/") + 1)
        
                if($vAppID_substring -eq $row.vAppId){

                    $vappFound = $true
                    [xml]$payload = '<?xml version="1.0" encoding="UTF-8"?><vcloud:Metadata xmlns:vcloud = "http://www.vmware.com/vcloud/v1.5" xmlns:xsi = "http://www.w3.org/2001/XMLSchema-instance"><vcloud:MetadataEntry><vcloud:Domain visibility="$($row.MetadataDomain)">SYSTEM</vcloud:Domain><vcloud:Key>rbk-connection</vcloud:Key><vcloud:TypedValue xsi:type ="$($row.MetadataKey)"><vcloud:Value>"$($row.MetadataValue)"</vcloud:Value></vcloud:TypedValue></vcloud:MetadataEntry></vcloud:Metadata>'
                    $restoreMetadata = Post-vCloudRequest -endpoint "vApp/$($vAppID_substring)/metadata" -payload $payload -orgId $ID -contenttype "application/vnd.vmware.vcloud.metadata+xml;version=5.5"
                    Write-Output $restoreMetadata
                }
            }

            if($vappFound -eq $false){
                $notFound = Read-Host "vApp $($row.vAppName) with ID $($row.vAppId) was not found. Would you like to restore this to another vApp? Y/N"
                if($notFound -eq "Y"){

                    $vAppNameTarget = Read-Host "Enter the name of the target vApp: "

                        foreach($vApp in $vApps.QueryResultRecords.VAppRecord){
        
                            if($vApp.name.ToLower() -eq $vAppNameTarget.ToLower()){

                                $vAppHref = $vApp.href
                                $vAppID_substring = $vAppHref.Substring($vAppHref.LastIndexOf("/") + 1)
                                [xml]$payload = '<?xml version="1.0" encoding="UTF-8"?><vcloud:Metadata xmlns:vcloud = "http://www.vmware.com/vcloud/v1.5" xmlns:xsi = "http://www.w3.org/2001/XMLSchema-instance"><vcloud:MetadataEntry><vcloud:Domain visibility="$($row.MetadataDomain)">SYSTEM</vcloud:Domain><vcloud:Key>$($row.MetadataKey)</vcloud:Key><vcloud:TypedValue xsi:type ="$($row.MetadataType)"><vcloud:Value>"$($row.MetadataValue)"</vcloud:Value></vcloud:TypedValue></vcloud:MetadataEntry></vcloud:Metadata>'
                                $restoreMetadata = Post-vCloudRequest -endpoint "vApp/$($vAppID_substring)/metadata" -payload $payload -orgId $ID -contenttype "application/vnd.vmware.vcloud.metadata+xml;version=5.5"
                                Write-Output $restoreMetadata

                            }
                        }
                }
            }
        }
    }
}