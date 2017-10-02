#
# Title:    install_connector.ps1
# Summary:  Installs the Rubrik connector on a Windows server operating system
# Author:   Tim Hynes, DevOps SE, tim.hynes@rubrik.com
#
# --- DO NOT EDIT ANYTHING BELOW HERE ---
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
# PS> Invoke-WebRequest https://<cluster>/connector/RubrikBackupService.zip -OutFile C:\Temp\RubrikBackupConnector.zip
$zip_file = 'C:\Temp\RubrikBackupService.zip'
# Extract the zip file
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($zip_file, 'C:\Temp\')
# Install from msi
Invoke-Command -Command 'msiexec /i C:\Temp\RubrikBackupService.msi /qn'
# Check if connector is installed
if (Get-WmiObject -Class Win32_Product | ?{$_.Name -eq 'Rubrik Backup Service'}) {
  # Confirm success
  Write-Output 'Connector installed succesfully'
  Exit 0
} else {
  # Dump out with exit code
  Write-Warning 'Connector not found, something went wrong with the installation'
  Exit 1
}
# Change the service account and restart the Service
$user = 'tim.hynes@rubrik.demo'
# This hashing of the password only masks it, a more correct way to do this is discussed at:
# https://www.pdq.com/blog/secure-password-with-powershell-encrypting-credentials-part-2/
# Encrypt like this:
# PS> [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("Hello World"))
# SGVsbG8gV29ybGQ=
# Decrypt like this:
# PS> [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("SGVsbG8gV29ybGQ="))
# Hello World
$hashed_password = 'SGVsbG8gV29ybGQ='
$password = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($hashed_password))
$service = Get-Service -name 'Rubrik Backup Service'
$service | Stop-Service
$wmi_svc = gwmi win32_service -filter "name='Rubrik Backup Service'"
$wmi_svc.change($null,$null,$null,$null,$null,$null,$user,$password,$null,$null,$null)
$service | Start-Service
