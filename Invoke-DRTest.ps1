#Requires -Version 3 -Module Pester,VMware.VimAutomation.Core,Rubrik
<#
  .Example
  .\Invoke-DRTest.ps1 -Rubrik 172.21.8.51 -vCenter devops-vcsa.rangers.lab -VMName msf-sql2016 -SandboxNetwork '172.21.12.0-dr'
#>
param(
  [String]$Rubrik
  ,[String]$vCenter
  ,[String]$VMName
  ,[String]$SandboxNetwork
  ,[PSCredential]$RubrikCred       = (Get-Credential -Message 'Rubrik Credentials')
  ,[PSCredential]$vCenterCred      = (Get-Credential -Message 'vCenter Credentials')
)
$MountName = "$VMName-test" 

Describe -Name 'Establish Connectivity' -Fixture {
  # Connect to Rubrik
  It -name 'Connect to Rubrik Cluster' -test {
    Connect-Rubrik -Server $Rubrik -Credential $RubrikCred
    $rubrikConnection.token | Should Be $true
  }
  # Connect to vCenter
  It -name 'Connect to vCenter Server' -test {
    Connect-VIServer -Server $vCenter -Credential $vCenterCred
    $global:DefaultVIServer.SessionId | Should Be $true
  }
}

Describe -Name 'Create Live Mount for Sandbox' -Fixture {
  # Spin up Live Mount
  It -name 'Request Live Mount' -test {
  #Populate initial variables
    $VMID = (Get-RubrikVM -name $VMName -PrimaryClusterID 'local' |  Where-Object {$_.isRelic -ne 'TRUE'}).id
      
    (Get-RubrikSnapshot -id $VMID -Date (Get-Date) |
        New-RubrikMount -MountName $MountName -PowerOn -RemoveNetworkDevices:$false -DisableNetwork:$false -Confirm:$false).id | Should Be $true
    Start-Sleep -Seconds 1
  }
  # Wait for Live Mount to become available in vSphere
  It -name 'Verify Live Mount is Powered On' -test {
    while ((Get-VM -Name $MountName -ErrorAction:SilentlyContinue).PowerState -ne 'PoweredOn') 
    {
      Start-Sleep -Seconds 1
    }
    (Get-VM -Name $MountName).PowerState | Should Be 'PoweredOn'
  }
  # Wait for VMware Tools to Start
  It -name 'Verify VMware Tools are Running' -test {
    while ((Get-VM $MountName).ExtensionData.Guest.ToolsRunningStatus -ne 'guestToolsRunning') 
    {
      Start-Sleep -Seconds 1
    }
    (Get-VM $MountName).ExtensionData.Guest.ToolsRunningStatus | Should Be 'guestToolsRunning'
  }
  
  # Connect Live Mount to Sandbox Network
  It -name 'Move vNIC to Sandbox Network' -test {
    (Get-NetworkAdapter -VM $MountName | Set-NetworkAdapter -NetworkName $SandboxNetwork -Connected:$true -Confirm:$false).NetworkName | Should Be $SandboxNetwork
    #Sleep for IP to be assigned
    Start-Sleep -Seconds 30
  }

}


Describe -Name 'Sandbox Tests' -Fixture {
  # Make sure VM is alive
  It -name "$MountName Test 1 - Network Responds to Ping" -test {
    Test-Connection -ComputerName (Get-VM -Name $MountName).Guest.IPAddress[0] -Quiet | Should Be 'True'
  }
}

Describe -Name 'Remove Mount' -Fixture {
  It -name "Unmounting $MountName" -test{
    $req = Get-RubrikMount -VMID $VMID | Remove-RubrikMount -Confirm:$false
  }
    
}
