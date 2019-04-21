<#
.SYNOPSIS
Install the Rubrik Backup Service on a remote machine

.DESCRIPTION
Script will download the Rubrik Backup Service from the RubrikCluster provided. The script will then push the msi, perform a quiet install 
and then configure the service to start under a specific service account. 

.PARAMETER RubrikCluster
Represents the IP Address or Name of the Rubrik Cluster

.PARAMETER OutFile
Download location of the RubrikBackupService.zip from the RubrikCluster

.PARAMETER ComputerName
Server to install the Rubrik Backup Service On

.EXAMPLE
.\Install-RubrikBackupService.ps1 -RubrikCluster 172.21.8.51 -computername cl-sql2012-1a

.NOTES
    Name:               Install Rubrik Backup Service
    Created:            1/03/2019
    Author:             Chris Lumnah
   
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$RubrikCluster,
    
    [Parameter(Mandatory=$false)]
    [string]$OutFile,

    [Parameter(Mandatory=$true)]
    [String]$ComputerName
)
$OutputPath = ".\MOF"
#region Download the Rubrik Connector 
$url =  "https://$($RubrikCluster)/connector/RubrikBackupService.zip"

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


[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
if (Test-Path -Path $OutFile)
{
    Remove-Item -Path $OutFile -Force
}
Invoke-WebRequest -Uri $url -OutFile $OutFile
#endregion

#region Push the RubrikBackupService.zip to remote computer
if (Test-Path -Path $OutFile)
{
    $Destination = "\\$($ComputerName)\C$\Temp\" #RubrikBackupService.zip"
    if (!(test-path -path $Destination))
    {
        New-Item -Path $Destination -ItemType Directory
    }
    $Destination = "\\$($ComputerName)\C$\Temp\RubrikBackupService.zip"
    Copy-Item -Path $OutFile -Destination $Destination -Force
}
#endregion

#region Unzip the RubrikBackupService on the remote computer
$Session = New-PSSession -ComputerName $ComputerName
Enter-PSSession -Session $Session

Expand-Archive -LiteralPath $OutFile -DestinationPath "\\$($ComputerName)\C$\Temp\RubrikBackupService" -Force

Exit-PSSession
#endregion

#region Install the RBS on the Remote Computer
Invoke-Command -ComputerName $ComputerName -ScriptBlock {
    Start-Process -FilePath "C:\Temp\RubrikBackupService\RubrikBackupService.msi" -ArgumentList "/quiet" -Wait
}
#endregion

configuration RubrikService
{
  param( 
	    [Parameter(Mandatory=$true)] 
	    [String]$Server
	  ) 
	

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Node $Server
    {
        ServiceSet Rubrik
        {
            Name        = "Rubrik Backup Service"
            StartupType = "Automatic"
            State       = "Running"
            Credential  = $Node.RubrikServiceAccount
        }
    }
}

configuration LocalAdministrators
{
    param( 
	    [Parameter(Mandatory=$true)] 
	    [String]$Server
	  ) 
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Node $Server
    {
        GroupSet LocalAdminTest
        {
            GroupName        = "Administrators"
            Ensure           = "Present"
            MembersToInclude = $Node.RubrikServiceAccount.UserName
        }
    }
}


$ConfigurationData = @{
    AllNodes = @(
        @{
            NodeName = $ComputerName
            PSDscAllowPlainTextPassword = $true
            PSDscAllowDomainUser =$true
            RubrikServiceAccount = Get-Credential -UserName "$($env:UserDomain)\Rubrik$" -Message "Credentials to run Rubrik Backup Service As"
        }
    )
}

#Configure the Local Administrators
LocalAdministrators -Server $ComputerName -ConfigurationData $ConfigurationData -OutputPath $OutputPath 
Start-DscConfiguration  -ComputerName $ComputerName -Path $OutputPath -Verbose -Wait -Force

#Configure the Rubrik Backup Service
RubrikService -Server $ComputerName -ConfigurationData $ConfigurationData -OutputPath $OutputPath 
Start-DscConfiguration  -ComputerName $ComputerName -Path $OutputPath -Verbose -Wait -Force

Get-Service -Name "Rubrik Backup Service" -ComputerName $ComputerName | Stop-Service 
Get-Service -Name "Rubrik Backup Service" -ComputerName $ComputerName | Start-Service