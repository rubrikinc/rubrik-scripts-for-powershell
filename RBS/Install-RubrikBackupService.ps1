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

   Pre-Requisites: This scripts requires WinRM and DSC to be supported inside a domain environment to work.
#>

param(
    # Rubrik Cluster name or ip address
    [Parameter(Mandatory=$true)]
    [string]$RubrikCluster,
    
    # Computer(s) that should have the Rubrik Backup Service installed onto and then added into Rubrik
    [Parameter(Mandatory=$true)]
    [String[]]$ComputerName,

    # Credential to run the Rubrik Backup Service on the Computer
    [Parameter(Mandatory=$false)]
    [pscredential]$RBSCredential,

    # Credential to log into Rubrik Cluster
    [Parameter(Mandatory=$false)]
    [pscredential]$RubrikCredential,

    # Parameter help description
    [Parameter(Mandatory=$false)]
    [string]$OutFile = "c:\temp\RubrikBackupService.zip"

    
)

if ($RBSCredential){
    $RubrikServiceAccount = $RBSCredential    
}
else{
    $RubrikServiceAccount = Get-Credential -UserName "$($env:UserDomain)\Rubrik$" -Message "Enter user name and password for the service account that will run the Rubrik Backup Service"
}


if ($RubrikCredential){
    $RubrikConnection = @{
        Server = $RubrikCluster
        Credential = $RubrikCredential
    }
}
else{
    $RubrikConnection = @{
        Server = $RubrikCluster
        Credential = Get-Credential -Message "Enter user name and password for your Rubrik Cluster"
    }
}

$OutputPath = ".\MOF\"
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
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $url -OutFile $OutFile
#endregion

configuration RubrikService{
    param( 
        [Parameter(Mandatory=$true)] 
        [String]$Server
    ) 
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Node $Server{
        ServiceSet Rubrik{
            Name        = "Rubrik Backup Service"
            StartupType = "Automatic"
            State       = "Running"
            Credential  = $Node.RubrikServiceAccount
        }
    }
}

configuration LocalAdministrators{
    param( 
	    [Parameter(Mandatory=$true)] 
	    [String]$Server
	) 
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Node $Server{
        GroupSet LocalAdminTest
        {
            GroupName        = "Administrators"
            Ensure           = "Present"
            MembersToInclude = $Node.RubrikServiceAccount.UserName
        }
    }
}

#validating the Servername and if it is online
$ValidComputerList=@()
foreach($Computer in $ComputerName){
    $isValidComputer = (Test-Connection -ComputerName $Computer -Count 1 -ErrorAction SilentlyContinue)
    if ($isValidComputer){
        Write-Verbose "$Computer, is up"
        $ValidComputerList +=$isValidComputer | ForEach-Object{ [System.Net.Dns]::Resolve($($_.ProtocolAddress)).HostName}
    }
    else{
        Write-Warning "Could not connect to server $Computer, the RBS will not be installed on this server!" 
    }  
}

foreach($Computer in $ValidComputerList){
    $Computer
    #region Push the RubrikBackupService.zip to remote computer
    if (Test-Path -Path $OutFile)
    {
        $Destination = "\\$($Computer)\C$\Temp\" #RubrikBackupService.zip"
        if (!(test-path -path $Destination))
        {
            New-Item -Path $Destination -ItemType Directory
        }
        $Destination = "\\$($Computer)\C$\Temp\RubrikBackupService.zip"
        Copy-Item -Path $OutFile -Destination $Destination -Force
    }
    #endregion

    #region Unzip the RubrikBackupService on the remote computer
    $Session = New-PSSession -ComputerName $Computer
    Enter-PSSession -Session $Session

    Expand-Archive -LiteralPath $OutFile -DestinationPath "\\$($Computer)\C$\Temp\RubrikBackupService" -Force

    Exit-PSSession
    #endregion

    #region Install the RBS on the Remote Computer
    Invoke-Command -ComputerName $Computer -ScriptBlock {
        Start-Process -FilePath "C:\Temp\RubrikBackupService\RubrikBackupService.msi" -ArgumentList "/quiet" -Wait
    }
    #endregion

    $ConfigurationData = @{
        AllNodes = @(
            @{
                NodeName = $Computer
                PSDscAllowPlainTextPassword = $true
                PSDscAllowDomainUser =$true
                RubrikServiceAccount = $RubrikServiceAccount
            }
        )
    }

    #Configure the Local Administrators
    LocalAdministrators -Server $Computer -ConfigurationData $ConfigurationData -OutputPath $OutputPath 
    Start-DscConfiguration  -ComputerName $Computer -Path $OutputPath -Verbose -Wait -Force

    #Configure the Rubrik Backup Service
    RubrikService -Server $Computer -ConfigurationData $ConfigurationData -OutputPath $OutputPath 
    Start-DscConfiguration  -ComputerName $Computer -Path $OutputPath -Verbose -Wait -Force

    Get-Service -Name "Rubrik Backup Service" -ComputerName $Computer | Stop-Service 
    Get-Service -Name "Rubrik Backup Service" -ComputerName $Computer | Start-Service

    #Add the host to Rubrik 
    Import-Module Rubrik
    Connect-Rubrik @RubrikConnection | Out-Null

    New-RubrikHost -Name $Computer -Confirm:$false

}