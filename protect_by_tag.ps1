#
# Title:    protect_by_tag.ps1
# Summary:  Protects vSphere Virtual Machines based on their assigned tag and category.
#           This will get all VMs in the vCenter defined in vcenter_creds.json with tags
#           set as per settings below, and add them to the given Rubrik SLA domain
# Author:   Tim Hynes, DevOps SE, tim.hynes@rubrik.com
#
# --- SETTINGS HERE CAN BE ALTERED ---
$sla_domain_name = 'Gold'
$tag_category = 'Rubrik'
$tag_name = 'Tier1'
# --- DO NOT EDIT ANYTHING BELOW HERE ---
# Import our PowerShell modules
Import-Module VMware.VimAutomation.Core,Rubrik
# Function to get cluster ID as this is not in the current Rubrik PS module
function Get-RubrikCluster {
  process {
    $url = $('https://' + $rubrik_creds.name + '/api/v1/cluster/me')
    $pair = "$($rubrik_creds.username):$($rubrik_creds.password)"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64 = [System.Convert]::ToBase64Striang($bytes)
    $basicAuthValue = "Basic $base64"
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add('Authorization',$basicAuthValue)
    $headers.Add('Accept','application/json')
    $cluster_id = Invoke-RestMethod -Method Get -Uri $url -Headers $headers
    Return $cluster_id.id
  }
}
# Function to ignore self-signed SSL certs
function Ignore-BadCerts {
  process {
    add-type @"
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
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
  }
}
Ignore-BadCerts
# Import credentials
$rubrik_creds = Get-Content -Raw -Path rubrik_creds.json | ConvertFrom-Json
$vcenter_creds = Get-Content -Raw -Path vcenter_creds.json | ConvertFrom-Json
# Connect to vCenter and Rubrik cluster
$rubrik_conn = Connect-Rubrik -Server $rubrik_creds.name -Username $rubrik_creds.username -Password $(ConvertTo-SecureString -AsPlainText -String $rubrik_creds.password -Force)
$vcenter_conn = Connect-VIServer -Server $vcenter_creds.name -User $vcenter_creds.username -Password $vcenter_creds.password 3>$null
# Get our tag, and VMs belonging to it
$tag_object = Get-TagCategory -Name $tag_category | Get-Tag -Name $tag_name
$tagged_vms = Get-VM -Tag $tag_object
# Get our Rubrik SLA Domain, making sure this is the one from the local cluster
$rubrik_cluster_id = Get-RubrikCluster
$rubrik_sla = Get-RubrikSLA -Name $sla_domain_name | ?{$_.primaryClusterId -eq $rubrik_cluster_id}
# Iterate through each of our tagged VMs
foreach ($tagged_vm in $tagged_vms) {
  # Get our VM by name
  $rubrik_vm = Get-RubrikVM | ?{$_.Name -eq $tagged_vm.Name}
  # Check the VM is the correct one, by checking it's moid
  if ($rubrik_vm.moid -eq $tagged_vm.ExtensionData.Summary.Vm.Value) {
    # Check if our VM is already protected by this SLA, if it is then do nothing, otherwise add it to the
    # correct SLA domain
    if ($rubrik_vm.configuredSlaDomainId -eq $rubrik_sla.id) {
      Write-Output $('VM '+ $rubrik_vm.Name + ' is already protected by SLA domain ' + $rubrik_sla.name)
    } else {
      Write-Output $('Protecting VM '+ $rubrik_vm.Name + ' by SLA domain ' + $rubrik_sla.name)
      #$rubrik_vm | Protect-RubrikVM -SLA $rubrik_sla -Confirm:$false
    }
  }
}
# Disconnect everything
Disconnect-Rubrik -Confirm:$false
Disconnect-VIServer * -Confirm:$false
