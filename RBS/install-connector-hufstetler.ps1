<#
 
  **This script comes with no warranty, use at you own risk

    .SYNOPSIS
    Allows Users to automaticate the Registration Process Windows Hosts on Rubrik Clusters

    .DESCRIPTION
    This script downloads the Rubrik Service Installation Files, installs the service,
    and registers the Windows Hosts with the Rubrik Cluster.
    This process makes use of both the Rubrik PowerShell Module 
    (https://github.com/rubrikinc/PowerShell-Module).

    This script requires Rubrik Admin Credentials in order to register the Windows Hosts with the cluster.

    .Notes
    Written by Ryan Hufstetler for Community Use
    Twitter @Ryanhuf
    
    .EXAMPLES:

    #Prompt for Rubrik Node IP or Host Name
    ./Install_Register_RubrikService.ps1

    #Include Rubrik Node IP or Host Name in the command parameters
    ./Install_Register_RubrikService.ps1 -RubrikCluster 'Cluster-IP'


#>

[CmdletBinding(SupportsShouldProcess = $true,ConfirmImpact = 'High')]
param(
     [string]$LocalServer = $env:COMPUTERNAME
    ,[parameter(Mandatory=$true)]
     [string]$RubrikCluster
    ,[pscredential]$RubrikCred=(Get-Credential -Message "Please enter your Rubrik credential:")
)

#Create URL used for Rubrik Service Download, download the file, and extract it to a temo directory
Write-Output "Downloading and Extracting Rubrik Service"
$url = "https://" + $RubrikCluster + "/connector/RubrikBackupService.zip"
$downloadFileName = "C:\RubrikTemp\RubrikBackupService.zip"
$zipDir = "C:\RubrikTemp\RubrikBackupService"
$web = New-Object Net.WebClient
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
md c:\RubrikTemp
$web.DownloadFile($url,$downloadFileName)
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = $null
Expand-Archive $downloadFileName -DestinationPath $zipDir

#Install Rubrik Service
Write-Output "Installing Rubrik Service"
$pathvargs = {C:\RubrikTemp\RubrikBackupService\RubrikBackupService.msi /qn}
Invoke-Command -ScriptBlock $pathvargs

Start-Sleep -Seconds 7

#Connect to the Rubrik Cluster 
Write-Output "Authenticating to Rubrik Cluster"
Connect-Rubrik -Server $RubrikCluster -Credential $RubrikCred | Out-Null

#Register the Windows Host with the Rubrik Cluster
Write-Output "Registering Host with Rubrik Cluster"
New-RubrikHost -Name $LocalServer -Server $RubrikCluster -Confirm:$false

#Remove The temp files and directories
Write-Output "Removing Rubrik Installation Files and Directories"
Remove-Item C:\RubrikTemp -Recurse

Write-Output "Registration Script is complete. The Rubrik Backup Service is running using the Local System Account"
Write-Output "If backing up MSSQL please ensure the User Running the Rubrik Backup Service has the Required Permissions"
Write-Output "Please Refer to the Rubrik CDM User Guide for Details"



