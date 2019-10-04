#
# Title:    install_connector.ps1
# Summary:  Installs the Rubrik connector on a Windows server operating system
# Author:   Tim Hynes, DevOps SE, tim.hynes@rubrik.com
#
# Start of Variables
$rubrik_ip = 'rubrik.demo.com'
$sa_user = 'administrator'
$sa_password = 'Not@Pa55!'
# End of Variables

# Check script is running as administrator mode
If (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Warning 'Script not running as admin, exiting'
    Exit 1
}
# Check first if the connector is already Installed
if (Get-WmiObject -Class Win32_Product | ?{$_.Name -eq 'Rubrik Backup Service'}) {
  # Confirm success
  Write-Output 'Connector already installed, nothing to do'
  Exit 0
}
# Installs the Rubrik connector on a Windows OS
# We assume the file is already there, maybe dropped by GPO, although this could be pulled from the cluster with:
#
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
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if (-not $(Test-Path C:\Temp)) { New-Item -ItemType Directory C:\Temp } else { Remove-Item C:\Temp\RubrikBackupService.zip; Remove-Item C:\Temp\RubrikBackupService.msi; Remove-Item C:\Temp\backup-agent.crt }
Invoke-WebRequest -Method Get -Uri https://$rubrik_ip/connector/RubrikBackupService.zip -OutFile C:\Temp\RubrikBackupService.zip
# PS> Invoke-WebRequest https://<cluster>/connector/RubrikBackupService.zip -OutFile C:\Temp\RubrikBackupConnector.zip
$zip_file = 'C:\Temp\RubrikBackupService.zip'
# Extract the zip file
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($zip_file, 'C:\Temp\')
# Install from msi
Invoke-Expression -Command 'msiexec /i C:\Temp\RubrikBackupService.msi /qn'
# Check if connector is installed
if (Get-WmiObject -Class Win32_Product | ?{$_.Name -eq 'Rubrik Backup Service'}) {
    # Confirm success
    Write-Output 'Connector installed succesfully'
    # Change the service account and restart the Service
    $service = Get-Service -name 'Rubrik Backup Service'
    $service | Stop-Service
    $wmi_svc = gwmi win32_service -filter "name='Rubrik Backup Service'"
    $wmi_svc.change($null,$null,$null,$null,$null,$null,$sa_user,$sa_password,$null,$null,$null)
    Invoke-Command -ComputerName 'localhost' -Script {
        param([string] $username)
        $tempPath = [System.IO.Path]::GetTempPath()
        $import = Join-Path -Path $tempPath -ChildPath "import.inf"
        if(Test-Path $import) { Remove-Item -Path $import -Force }
        $export = Join-Path -Path $tempPath -ChildPath "export.inf"
        if(Test-Path $export) { Remove-Item -Path $export -Force }
        $secedt = Join-Path -Path $tempPath -ChildPath "secedt.sdb"
        if(Test-Path $secedt) { Remove-Item -Path $secedt -Force }
        try {
          Write-Host ("Granting SeServiceLogonRight to user account: {0} on host: {1}." -f $username, $computerName)
          $sid = ((New-Object System.Security.Principal.NTAccount($username)).Translate([System.Security.Principal.SecurityIdentifier])).Value
          secedit /export /cfg $export
          $sids = (Select-String $export -Pattern "SeServiceLogonRight").Line
          foreach ($line in @("[Unicode]", "Unicode=yes", "[System Access]", "[Event Audit]", "[Registry Values]", "[Version]", "signature=`"`$CHICAGO$`"", "Revision=1", "[Profile Description]", "Description=GrantLogOnAsAService security template", "[Privilege Rights]", "SeServiceLogonRight = *$sids,*$sid")){
            Add-Content $import $line
          }
          secedit /import /db $secedt /cfg $import
          secedit /configure /db $secedt
          gpupdate /force
          Remove-Item -Path $import -Force
          Remove-Item -Path $export -Force
          Remove-Item -Path $secedt -Force
        } catch {
          Write-Host ("Failed to grant SeServiceLogonRight to user account: {0} on host: {1}." -f $username, $computerName)
          $error[0]
        }
      } -ArgumentList $sa_user
    $service | Start-Service
} else {
    # Dump out with exit code
    Write-Warning 'Connector not found, something went wrong with the installation'
}
if ($(get-module Rubrik -ListAvailable) -eq $null) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    Install-Module Rubrik -Force
}
