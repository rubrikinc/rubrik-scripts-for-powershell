#requires -modules VMware.VimAutomation.Core

# https://build.rubrik.com
# https://github.com/rubrikinc/rubrik-scripts-for-powershell

<#
.SYNOPSIS
Creates a new role in vSphere with the restricted privileges needed to run Rubrik CDM. Assigns role to 
Rubrik Service Account at the root of Hosts and Clusters.

.DESCRIPTION
The create_vCenter_User.ps1 cmdlet will create a new role in a vCenter with the minimum privileges to 
allow Rubrik CDM to perform data protection in vSphere. The new role will be assigned to a specified
user in vCenter. Options are provided for creating roles in on-prem vCenters, VMware Cloud on AWS (VMC)
vCenters, Azure VMware Cloud Solution (AVS) and  Google VMware Cloud Engine (GCVE).

.NOTES
Updated by Damani Norman for community usage
GitHub: DamaniN

You can use a vCenter credential file for authentication
Default $vCenterCredFile = './vcenter_cred.xml'
To create one: Get-Credential | Export-CliXml -Path ./vcenter_cred.xml

.EXAMPLE
create_vCenter_User.ps1 

Create the restricted permissions and prompt for all of the variables.

.EXAMPLE
create_vCenter_User.ps1 -vCenter <vcenter_server> -vCenterAdminUser <vcenter_admin_user> -vCenterAdminPassword <vcenter_admin_password> -Username <username_for_rubrik_role> -Domain <domain_of_rubrik_role_username> -RubrikRole <role_name> -vCenterType ONPREM

Create the restricted permissions in an On-Prem vCenter using a username and password specified on the command line.

.EXAMPLE
create_vCenter_User.ps1 -vCenter <vcenter_server> -vCenterCredFile <credential_file> -Username <username_for_rubrik_role> -Domain <domain_of_rubrik_role_username> -RubrikRole <role_name> -vCenterType VMC

Create the restricted permissions in an VMC vCenter using a specific vCenter credential file.

.EXAMPLE
create_vCenter_User.ps1 -vCenter <vcenter_server> -Username <username_for_rubrik_role> -Domain <domain_of_rubrik_role_username> -RubrikRole <role_name> -vCenterType AVS

Create the restricted permissions in an AVS vCenter and prompt for the vCenter username and password.
#>

param (
 [string]$vCenter,
 [string]$Username,
 [string]$Domain
)

clear-host

$usage = ".\create_vCenter_User.ps1 -vCenter vCenterFQDNorIP -Username RubrikServiceAccountName -Domain SAMAuthenticationDomain"
$example = '.\create_vCenter_User.ps1 -vCenter "vcenter.rubrik.local" -Username svc_rubrik -Domain Rubrik.com' 

Write-Host "PowerCLI script to create Rubrik Role which includes required privileges and assigns the designated Rubrik Service Account to Role" `
  -ForeGroundColor Cyan 

if ( !$vCenter -or !$Username -or !$Domain ) {
  write-host `n "Missing Required Parameter - vCenter, Username, and Domain are required."`
  `n "The -Domain parameter format is expected to be SAM; do not use the FQDN of your domain name (e.g., RUBRIK)." `n -ForeGroundColor Red
  write-host "Usage: $usage" `n
  write-host "Example: $example" `n
  exit
}

# Rubrik Service Account User
#The Rubrik User account is a non-login, least-privileged, vCenter Server account that you specify during deployment.
$Rubrik_User = "$Domain\$Username"

# Rubrik Role Name
$Rubrik_Role = "Rubrik_Backup_Service"

#Privileges to assign to role
#See the Rubrik Administrators Guide for Required Permissions
$Rubrik_Privileges = @(
  'Datastore.AllocateSpace'
  'Datastore.Browse'
  'Datastore.Config'
  'Datastore.Delete'
  'Datastore.FileManagement'
  'Datastore.Move'
  'Global.DisableMethods'
  'Global.EnableMethods'
  'Global.Licenses'
  'Host.Config.Image'  
  'Host.Config.Storage'
  'Network.Assign'
  'Resource.AssignVMToPool'
  'Resource.ColdMigrate'
  'Resource.HotMigrate'
  'Sessions.TerminateSession'
  'Sessions.ValidateSession'
  'StorageProfile.View'
  'StorageViews.View'
  'System.Anonymous'
  'System.Read'
  'System.View'
  'VirtualMachine.Config.AddExistingDisk'
  'VirtualMachine.Config.AddNewDisk'
  'VirtualMachine.Config.AdvancedConfig'
  'VirtualMachine.Config.ChangeTracking'
  'VirtualMachine.Config.DiskLease'
  'VirtualMachine.Config.Rename'
  'VirtualMachine.Config.Resource'
  'VirtualMachine.Config.Settings'
  'VirtualMachine.Config.SwapPlacement'
  'VirtualMachine.Config.RemoveDisk'
  'VirtualMachine.Config.CPUCount' # Added for AppFlows support
  'VirtualMachine.Config.Memory' # Added for AppFlows support
  'VirtualMachine.Config.AddRemoveDevice'
  'VirtualMachine.Config.EditDevice'
  'VirtualMachine.GuestOperations.Execute'
  'VirtualMachine.GuestOperations.Modify'
  'VirtualMachine.GuestOperations.Query'
  'VirtualMachine.Interact.AnswerQuestion'
  'VirtualMachine.Interact.Backup'
  'VirtualMachine.Interact.DeviceConnection'
  'VirtualMachine.Interact.GuestControl'
  'VirtualMachine.Interact.PowerOff'
  'VirtualMachine.Interact.PowerOn'
  'VirtualMachine.Interact.Reset'
  'VirtualMachine.Interact.Suspend'
  'VirtualMachine.Interact.ToolsInstall'
  'VirtualMachine.Inventory.Create'
  'VirtualMachine.Inventory.Delete'
  'VirtualMachine.Inventory.Move'
  'VirtualMachine.Inventory.CreateFromExisting' # Added for AppFlows support
  'VirtualMachine.Inventory.Register'
  'VirtualMachine.Inventory.Unregister'
  'VirtualMachine.Provisioning.Clone' # Added for AppFlows support
  'VirtualMachine.Provisioning.DiskRandomAccess'
  'VirtualMachine.Provisioning.DiskRandomRead'
  'VirtualMachine.Provisioning.GetVmFiles'
  'VirtualMachine.Provisioning.PutVmFiles'
  'VirtualMachine.State.CreateSnapshot'
  'VirtualMachine.State.RemoveSnapshot'
  'VirtualMachine.State.RenameSnapshot'
  'VirtualMachine.State.RevertToSnapshot'
)

Write-Host "Connecting to vCenter at $vCenter.  A prompt should be presented shortly."`n -ForeGroundColor Cyan
Write-Host "You will need to provide credentials for a vCenter account with admin privileges to create the Role and assign that role to $Rubrik_User"`n -ForeGroundColor Cyan
Connect-VIServer $vCenter -Force | Out-Null # Added '-Force' to avoid certificate warnings leading to login failures

Write-Host "Creating a new role called $Rubrik_Role "`n -ForeGroundColor Cyan 
New-VIRole -Name $Rubrik_Role -Privilege (Get-VIPrivilege -id $Rubrik_Privileges) | Out-Null

#Get the Root Folder
$rootFolder = Get-Folder -NoRecursion
#Create the Permission
Write-Host "Granting permissions on object $rootFolder to $Rubrik_User as role $Rubrik_Role with Propagation = $true"`n -ForeGroundColor Cyan
New-VIPermission -Entity $rootFolder -Principal $Rubrik_User -Role $Rubrik_Role -Propagate:$true | Out-Null

#Disconnect from the vCenter Server
Write-Host "Disconnecting from vCenter at $vCenter"`n -ForeGroundColor Cyan
Disconnect-VIServer $vCenter -Confirm:$false
