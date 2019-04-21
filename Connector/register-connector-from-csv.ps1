#
# Name:     register-connector-from-csv.ps1
# Author:   pmilano1 (Peter J. Milanese)
# Use case: Register Rubrik Connector Service from CSV (line delmited file) of hostnames
# Ex: .\register-connector-from-csv.ps1 -rubrik_host [FDQN|IP Address for Rubrik Cluster] -csv [filename.csv]

param (
    [string]$rubrik_host = $(Read-Host -Prompt 'Input your Rubrik IP or Hostname'),
    [string]$csv = $(Read-Host -Prompt "Enter relative path to csv")
)

# Check for / Install Rubrik Posh Mod
$RubrikModuleCheck = Get-Module -ListAvailable Rubrik
if ($RubrikModuleCheck -eq $null) {
    Install-Module -Name Rubrik -Scope CurrentUser -Confirm:$false
}
Import-Module Rubrik
$RubrikModuleCheck = Get-Module -ListAvailable Rubrik
if ($RubrikModuleCheck -eq $null) {
  write-host "Could not deploy Rubrik Powershell Module. Please see https://powershell-module-for-rubrik.readthedocs.io/en/latest/"
}

# Check for Credentials
$Credential = @()
$CredentialFile = "$($PSScriptRoot)\.creds\$($rubrik_host).cred"
try{
  write-host "Credentials found for $($rubrik_host)"
  $Credential = Import-CliXml -Path $CredentialFile
}
catch{
  write-host "$($CredentialFile) not found"
  $Credential = Get-Credential -Message "Credentials not found for $($rubrik_host), please enter them now."
  $Credential | Export-CliXml -Path $CredentialFile
}

$conx = ''
try {
  $conx = (Connect-Rubrik -Server $rubrik_host -Credential $Credential)
  Write-Host "Logged into $($rubrik_host)"
}
catch {
  write-host "Could not log into $($rubrik_host)"
  Write-Host $Error
}
Import-Csv $csv | Foreach-Object { 
  foreach ($element in $_.PSObject.Properties)
  {
      Write-Host -NoNewline "Register : " $element.Value 
      $out = @()
      try {
        $out = New-RubrikHost -Name "$($element.Value)" -Confirm:$false
        Write-Host " : " $out.Status
      }
      catch {
        Write-Host " : Failed"
      }
  } 
}

