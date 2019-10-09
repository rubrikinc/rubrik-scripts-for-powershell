<#

.SYNOPSIS
A script to automate user and managed volume creation for SAP

.DESCRIPTION
Prompts for SAP DB, User account, Managed Volume Settings. Creates the user and Managed Volumes, attaches permissions for MVs to User, and create a 365 API token

.EXAMPLE
./sap-workflow.ps1

.NOTES
Name:               SAP Workflow Script
Version:            1.0
Created:            10/9/2019
Author:             Andrew Draper
CDM:                5.0.2
#>

Import-Module Rubrik

function Get-RubrikAPIToken () {
    # Function required as we need to impersonate the user after creation
    # This will login as the newly created user, send a request to the session endpoint for a 365 day API Token

    [CmdletBinding()]
    Param (
        [string]$rubrik_ip,
        [string]$rubrik_user,
        [string]$rubrik_pass,
        [string]$rubrik_token_name,
        [string]$rubrik_global_org_id
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

    $api_token_query = @{
        initParams = @{
            apiToken = @{
                expiration = 525600
                tag = $rubrik_token_name
            }
            organizationId = $rubrik_global_org_id
        }
    }

    if ($psversiontable.PSVersion.Major -le 5) {
        $token_response = Invoke-WebRequest -Uri $("https://"+$rubrik_ip+"/api/internal/session") -Headers $headers -Method POST -Body $(ConvertTo-Json $api_token_query)
    } else {
        $token_response = Invoke-WebRequest -Uri $("https://"+$rubrik_ip+"/api/internal/session") -Headers $headers -Method POST -Body $(ConvertTo-Json $api_token_query) -SkipCertificateCheck
    }
    return $token_response
}

# Connect to Rubrik
$credPath = ".\RubrikCred.xml"
$cred = Get-Credential -Message "Please provide Rubrik Credentials"
$cred | Export-Clixml $credPath -Force
$rubrikCluster = Read-Host -Prompt "Please enter the Rubrik IP or DNS Address"
Connect-Rubrik -Server $rubrikCluster -Credential (Import-Clixml $credPath)

Write-Host "Starting SAP Configuration" -ForegroundColor Yellow
$sapDBName = Read-Host -Prompt "Please enter the SAP Database to protect"
$sapUsername = Read-Host -Prompt "Please provide a new Rubrik username for this SAP Database"
$sapUserEmail = Read-Host -Prompt "Please provide an email address for this user"
$sapPassword = Read-Host -Prompt "Please provide a password for this user" -AsSecureString

Write-Host "Managed Volume Configuration - Data" -ForegroundColor Yellow
$sapDataMV = Read-Host -Prompt "Please enter the Name of the new Rubrik Managed Volume for SAP Data"
[Int32]$sapDataMVSize = Read-Host -Prompt "Please enter the size of for this Managed Volume (GB)"
$sapDataChannels = Read-Host -Prompt "Please enter the number of Channels (Default 1)"
$sapDataClientIP = Read-Host -Prompt "Please enter the SAP Client IPs for access to this Managed Volume (Multiples can be seperated with a comma)"
$sapDataSLA = Read-Host -Prompt "Please provide the SLA Name for the Data Managed Volume"

Write-Host "Managed Volume Configuration - Archive" -ForegroundColor Yellow
$sapArchiveMV = Read-Host -Prompt "Please enter the Name of the new Rubrik Managed Volume for SAP Data Archive"
[Int32]$sapArchiveMVSize = Read-Host -Prompt "Please enter the size of for this Managed Volume (GB)"
$sapArchiveChannels = Read-Host -Prompt "Please enter the number of Channels (Default 1)"
$sapArchiveClientIP = Read-Host -Prompt "Please enter the SAP Client IPs for access to this Managed Volume (Multiples can be seperated with a comma)"
$sapArchiveSLA = Read-Host -Prompt "Please provide the SLA Name for the Archive Managed Volume"

if(!$sapDataChannels){
    $sapDataChannels = 1
}

if(!$sapArchiveChannels){
    $sapArchiveChannels = 1
}

$BSTR = `
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sapPassword)

Write-Host "Creating Rubrik User" -ForegroundColor Yellow
$userObject = @{
    username = $sapUsername
    password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    emailAddress = $sapUserEmail
}
$createRubrikUser = Invoke-RubrikRESTCall -Endpoint 'user' -api internal -Method POST -Body $userObject
Write-Host "$($createRubrikUser.username) Successfully Created - ID: $($createRubrikUser.id)" -ForegroundColor Green

Write-Host "Creating Managed Volumes for Data & Archive" -ForegroundColor Yellow
$sapDataExportConfig = @{
    hostPatterns = @(
        $sapDataClientIP
    )
}

$sapArchiveExportConfig = @{
    hostPatterns = @(
        $sapArchiveClientIP
    )
}
$sapDataMVObject = New-RubrikManagedVolume -Name $sapDataMV -VolumeSize ($sapDataMVSize * 1GB) -Channels $sapDataChannels -applicationTag SapHana -exportConfig $sapArchiveExportConfig
$sapArchiveMVObject = New-RubrikManagedVolume -Name $sapArchiveMV -VolumeSize ($sapArchiveMVSize * 1GB) -Channels $sapArchiveChannels -applicationTag SapHana -exportConfig $sapArchiveExportConfig
do{

    $DataMV = Invoke-RubrikRESTCall -Endpoint "managed_volume/$($sapDataMVObject.id)" -api internal -Method GET

} while (!$DataMV.mainExport)

do {

    $ArchiveMV = Invoke-RubrikRESTCall -Endpoint "managed_volume/$($sapArchiveMVObject.id)" -api internal -Method GET

} while (!$ArchiveMV.mainExport)
Write-Host "Successfully created Managed Volumnes - Data: $($sapDataMVObject.id) Archive: $($sapArchiveMVObject.id)" -ForegroundColor Green

Write-host "Protecting New Managed Volumes with SLA: $($sapDataSLA)" -ForegroundColor Yellow
$SLADataObj = Get-RubrikSLA -Name $sapDataSLA
$SLAArchiveObj = Get-RubrikSLA -Name $sapArchiveSLA
$DataSLAPayload = @{
    managedIds = @(
        $sapDataMVObject.id
    )
}
$ArchiveSLAPayload = @{
    managedIds = @(
        $sapArchiveMVObject.id
    )
}
Invoke-RubrikRESTCall -Endpoint "sla_domain/$($SLADataObj.id)/assign" -Method POST -api internal -Body $DataSLAPayload
Invoke-RubrikRESTCall -Endpoint "sla_domain/$($SLAArchiveObj.id)/assign" -Method POST -api internal -Body $ArchiveSLAPayload
Write-host "Protecting New Managed Volumes with SLA: $($sapDataSLA) completed" -ForegroundColor Green

Write-host "Applying Managed Volume Permissions to User $($createRubrikUser.username)" -ForegroundColor Yellow
$userPermissions = @{
    principals = @(
        $createRubrikUser.id
    )
    privileges = @{
        destructiveRestore = @()
        restore = @(
            $sapDataMVObject.id
            $sapArchiveMVObject.id
        )
        onDemandSnapshot = @()
        restoreWithoutDownload = @()
        viewEvent = @()
        provisionOnInfra = @()
        viewReport = @()
    }
}

$applyPermissions = Invoke-RubrikRESTCall -Endpoint 'authorization/role/end_user' -Method POST -api internal -Body $userPermissions
Write-host "Permissions applied to user for Managed Volumes - Data: $($DataMV.name) Archive: $($ArchiveMV.name)" -ForegroundColor Green

$mvRole = @{
    principals = @(
        $createRubrikUser.id
    )
    privileges = @{
        basic = @(
            $sapDataMVObject.id
            $sapArchiveMVObject.id
        )
    }
}

$applyMVRole = Invoke-RubrikRESTCall -Endpoint 'authorization/role/managed_volume_user' -Method POST -api internal -Body $mvRole

Write-Host "Generating 365 Day API Token for User $($createRubrikUser.username)" -ForegroundColor Yellow
$gloablOrg = Get-RubrikOrganization -isGlobal:$true
$userToken = Get-RubrikAPIToken -rubrik_ip $rubrikCluster -rubrik_user $sapUsername -rubrik_pass ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)) -rubrik_token_name "SAP_Test" -rubrik_global_org_id $gloablOrg.id
$userTokenObj = $userToken.Content | ConvertFrom-JSON
Write-Host "Successfully Created Token for User: $($sapUsername)" -ForegroundColor Green
Write-Host "Script Completed:" -ForegroundColor Green

$results = "
SAP Database Name: $($sapDBName)

Login Details:
Rubrik Cluster: $($global:rubrikConnection.server)
Rubrik Username: $($createRubrikUser.username)
API Token: $($userTokenObj.session.token)

Managed Volume Data Details:
Managed Volume Name (Data): $($sapDataMVObject.name)
Managed Volume ID (Data): $($sapDataMVObject.id)
Managed Volume Size (Data): $($sapDataMVObject.volumeSize / 1GB) GB
Managed Volume IP (Data): $($DataMV.mainExport.channels.ipAddress)
Managed Volume Channel (Data): $($DataMV.mainExport.channels.mountPoint)

Managed Volume Archive Details:
Managed Volume Name (Archive): $($sapArchiveMVObject.name)
Managed Volume ID (Archive): $($sapArchiveMVObject.id)
Managed Volume Size (Archive): $($sapArchiveMVObject.volumeSize / 1GB) GB
Managed Volume IP (Archive): $($ArchiveMV.mainExport.channels.ipAddress)
Managed Volume Channel (Archive): $($ArchiveMV.mainExport.channels.mountPoint)
"

write-host $results -ForegroundColor Green

$output_folder = '.'
$output_file_name = $output_folder + "\" + $(get-date -uFormat "%Y%m%d-%H%M%S") + "-$($sapDBName)-MV_Creation.txt"

$results > $output_file_name