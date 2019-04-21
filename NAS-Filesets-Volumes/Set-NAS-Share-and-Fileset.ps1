<#
 
  **This script comes with no warranty, use at you own risk

        .SYNOPSIS
        Create a new NAS Share and associate a Fileset and SLA Domain

        .DESCRIPTION
        This script connects to a Rubrik Cluster and completes the following tasks:

        * Adds a New NAS Share (assumes the host has already been added)
        * Associates a Fileset with the NAS Share
        * Associates the Fileset to a SLA Domain

        This process makes use of both the Rubrik PowerShell Module and 
        (https://github.com/rubrikinc/PowerShell-Module) Invoke-WebRequest.
        
        .Notes
        Written by Drew Russell - Rubrik Ranger Team
        Twitter @drusse11

        .EXAMPLES:
        #Execute Script
        ./Set-NAS-Share-and-Fileset.ps1
        
#>

###################################################
############### User Variables ####################

$RubrikAddress = ""
$Hostname = ''
$ShareType = '' #NFS or SMB
$SharePath = ''
$SLA = ''
$Fileset =  ''


# Examples
# $RubrikAddress = "172.17.2.76"
# $Hostname = '172.17.25.11'
# $ShareType = 'NFS' #NFS or SMB
# $SharePath = '/home'
# $SLA = 'Gold'
# $Fileset =  'EVERYTHING'



###################################################
####### No User Modification Required Below #######
###################################################



try {
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
}
catch {}


# Prompt the user for credentials
$RubrikCredential = Get-Credential

# Conver Username and Password to Base64
$RubrikRESTHeader = @{
		"Authorization" = "Basic " + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($RubrikCredential.UserName+':'+$RubrikCredential.GetNetworkCredential().Password))
	}

# Define the Rubrik API Version
$RubrikApi = "/api/v1"

# Validate Authentication to Rubrik
try {
    $result = Invoke-WebRequest -Uri ("https://$RubrikAddress$RubrikApi" + "/cluster/me") -Headers $RubrikRESTHeader -Method "GET" -ErrorAction Stop
    
    if($result.StatusCode -ne 200) {
        throw "Bad status code returned from Rubrik cluster at $RubrikAddress"
    }
    else {
        Write-Host 'Executing Script...'
    }
}
catch {
    throw $_
}

# User the Credentials provided earlier for Connect-Rubrik
$Username = $RubrikCredential.UserName
$Password = ConvertTo-SecureString $RubrikCredential.GetNetworkCredential().Password -AsPlainText -Force

Connect-Rubrik -Server $RubrikAddress -Username $Username -Password $Password | Out-Null

# Add a New NAS Share
$HostId = (Get-RubrikHost -PrimaryClusterID 'local' -Hostname $Hostname).id 

$RESTBody = @{
    "hostId" = "$HostId"
    "shareType" = "$ShareType"
    "exportPoint" = "$SharePath"
}

$RubrikApi = "/api/internal"
$AddShareEndpoint = '/host/share'

$uri = "https://$RubrikAddress$RubrikApi$AddShareEndpoint"

try {
    $result = Invoke-WebRequest -Uri $uri -Headers $RubrikRESTHeader -Method POST -Body (ConvertTo-Json -InputObject $RESTBody) -ErrorAction Stop
}
catch {
    throw $_
}

# Assign a Fileset to the NAS Share
$ShareId = (ConvertFrom-Json -InputObject $result.Content -ErrorAction Stop).id
$FilesetTemplateId = (Get-RubrikFilesetTemplate -Name $Fileset).id

$RESTBody = @{
    "hostId" = "$HostId"
    "shareId" = "$ShareId"
    "templateId" = "$FilesetTemplateId"
}


$AddFilesetTemplateEndpoint = '/fileset/bulk'

$RubrikApi = "/api/internal"

$uri = "https://$RubrikAddress$RubrikApi$AddFilesetTemplateEndpoint"

$body = '[ ' + (ConvertTo-Json -InputObject $RESTBody) + ']'


try {
    $result = Invoke-WebRequest -Uri $uri -Headers $RubrikRESTHeader -Method POST -Body $body -ErrorAction Stop
}
catch {
    throw $_
}

# Associate a SLA Domain to the NAS Share/Fileset
Get-RubrikFileset $Fileset -HostName $Hostname | Where-Object {$_.isRelic -ne 'True'} | Protect-RubrikFileset -SLA $SLA -Confirm:$False | Out-Null


