function Connect-Rubrik {
	[cmdletbinding()]
	Param (
		[Parameter(Mandatory = $true)][System.String]$RubrikAddress,
		[Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$RubrikCredential,
		[Parameter(Mandatory = $false)][System.String]$RubrikApi = "/api/v1/"
	)
	
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
	
	$global:RubrikAddress = $RubrikAddress
	$global:RubrikRESTHeader = @{
		"Authorization" = "Basic " + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($RubrikCredential.UserName+':'+$RubrikCredential.GetNetworkCredential().Password))
	}
	$global:RubrikApi = $RubrikApi

	#test authenticated connection to Rubrik
	try {
		$result = Invoke-WebRequest -Uri ("https://$RubrikAddress$RubrikApi" + "cluster/me") -Headers $RubrikRESTHeader -Method "GET" -ErrorAction Stop
		
		if($result.StatusCode -ne 200) {
			throw "Bad status code returned from Rubrik cluster at $RubrikAddress"
		}
		else {
			Write-Host "Connected to Rubrik cluster $RubrikAddress"
		}
	}
	catch {
		throw $_
	}
}

function Invoke-RubrikCmd {
	[cmdletbinding()]
	Param (
		[Parameter(Mandatory = $true,HelpMessage = 'REST Endpoint')]
        [ValidateNotNullorEmpty()]
		[System.String]$RESTEndpoint,
		[Parameter(Mandatory = $true,HelpMessage = 'REST Method')]
        [ValidateNotNullorEmpty()]
		[System.String]$RESTMethod,
		[Parameter(Mandatory = $false,HelpMessage = 'REST Content')]
        [ValidateNotNullorEmpty()]
		[System.Array]$RESTBody,
		[Parameter(Mandatory = $false,HelpMessage = 'Limit to Number of Results')]
        [ValidateNotNullorEmpty()]
		[System.Int32]$Limit = 9999,
		[Parameter(Mandatory = $false,HelpMessage = 'INTERNAL METHOD')]
        [ValidateNotNullorEmpty()]
		[System.Management.Automation.SwitchParameter]$Internal
	)
	
	#connect to Rubrik if not already connected
	if( !($global:RubrikAddress) -or !($global:RubrikRESTHeader) -or !($global:RubrikApi) ) {
		Connect-Rubrik
	}
	
	#construct uri
	if($Internal) {
		$api = "/api/internal/"
	}
	else {
		$api = $global:RubrikAPI
	}
	$address = $global:RubrikAddress
	$uri = "https://$address$api$RESTEndpoint"
	
	#add limit if provided
	if( $Limit ) {
		if($uri.Indexof('?') -eq -1) {
			$uri = $uri += "?limit=$Limit"
		}
		else {
			$uri = $uri += "&limit=$Limit"
		}
	}
	
	#execute REST operation
	try {
        Write-Verbose $uri
        if($RESTBody){
        	$result = Invoke-WebRequest -Uri $uri -Headers $global:RubrikRESTHeader -Method $RESTMethod -Body (ConvertTo-Json -InputObject $RESTBody) -ErrorAction Stop
        } else {
            $result = Invoke-WebRequest -Uri $uri -Headers $global:RubrikRESTHeader -Method $RESTMethod -ErrorAction Stop
        }
        if($result.Content){
    	    $content = ConvertFrom-Json -InputObject $result.Content -ErrorAction Stop
        } else {
            $content = $result.StatusCode
        }
	}
	catch {
		throw $_
	}
	
	#check for partial data
	if( $content.hasMore ) {
		Write-Warning "A limited amount of results have been returned.  Try using -Limit 9999 to return more data"
	}
	
	return $content
}