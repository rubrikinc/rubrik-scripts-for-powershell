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
#requires -modules RubrikSecurityCloud, PSDscResources
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

    # Parameter help description
    [Parameter(Mandatory=$false)]
    [string]$OutFile = "c:\temp\RubrikBackupService.zip"
)
$OutputPath = ".\MOF\"
Import-Module RubrikSecurityCloud
Import-Module PSDscResources
Connect-Rsc

#region Download the Rubrik Connector 
$RscCluster = Get-RscCluster -Name $RubrikCluster
$query = New-RscQueryCluster -Operation Cluster -AddField ClusterNodeConnection, ClusterNodeConnection.Nodes.ipAddress
$query.var.clusterUuid = $RscCluster.id
$RscClusterNodeConnection = ($query.invoke()).ClusterNodeConnection.Nodes | Where-Object {$_.Status -eq "OK"} | Select-Object -First 1

$url =  "https://$($RscClusterNodeConnection.IpAddress)/connector/RubrikBackupService.zip"

Invoke-WebRequest -Uri $url -OutFile $OutFile -SkipCertificateCheck
#endregion

configuration RubrikService{
    param( 
        [Parameter(Mandatory=$true)] 
        [String]$Server
    ) 
    Import-DscResource -ModuleName "PSDscResources"
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
	    [String]$Server,
        [String]$UserName
	) 
    Import-DscResource -ModuleName "PSDscResources"
    Node $Server{
        GroupSet LocalAdministrators
        {
            GroupName        = @( "Administrators" )
            Ensure           = "Present"
            MembersToInclude = @( "$($UserName)" )
        }
    }
}

#validating the Servername and if it is online
$ValidComputerList=@()
foreach($Computer in $ComputerName){
    $isValidComputer = (Test-Connection -ComputerName $Computer -Count 1 -ErrorAction SilentlyContinue)
    if ($isValidComputer){
        Write-Verbose "$Computer, is up"
        # $ValidComputerList +=$isValidComputer | ForEach-Object{ [System.Net.Dns]::Resolve($($_.ProtocolAddress)).HostName}
        $ValidComputerList += $Computer
    }
    else{
        Write-Warning "Could not connect to server $Computer, the RBS will not be installed on this server!" 
    }  
}

foreach($Computer in $ValidComputerList){
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

    Install-Module PSDscResources

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
                RubrikServiceAccount = $RBSCredential
            }
        )
    }

    #Configure the Local Administrators
    LocalAdministrators -Server $Computer -UserName $RBSCredential.UserName -ConfigurationData $ConfigurationData -OutputPath $OutputPath
    Start-DscConfiguration  -ComputerName $Computer -Path $OutputPath -Verbose -Wait -Force

    #Configure the Rubrik Backup Service
    $RBSCredential
    RubrikService -Server $Computer -ConfigurationData $ConfigurationData -OutputPath $OutputPath 
    Start-DscConfiguration  -ComputerName $Computer -Path $OutputPath -Verbose -Wait -Force

    Invoke-Command -ComputerName $Computer -Scriptblock {Get-Service -Name "Rubrik Backup Service" | Stop-Service} -Verbose
    Invoke-Command -ComputerName $Computer -Scriptblock {Get-Service -Name "Rubrik Backup Service" | Start-Service} -Verbose

    #Add the host to Rubrik 
    $query = New-RscMutation -GqlMutation bulkRegisterHost -AddField Data, Data.HostSummary
    $query.Var.input = New-Object -TypeName RubrikSecurityCloud.Types.BulkRegisterHostInput
    $query.Var.input.clusterUuid = $RscCluster.Id
    $query.Var.input.hosts = @()
    $hostInput = New-Object -TypeName RubrikSecurityCloud.Types.HostRegisterInput
    $hostInput.Hostname = $ComputerName
    $query.Var.input.hosts += $hostInput
    
    ($query.Invoke()).data.HostSummary

}