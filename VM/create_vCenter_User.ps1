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
  [CmdletBinding()]

  [Parameter(Mandatory = $true)]
  # Hostname, FQDN or IP of the vCenter server.
  [string]$vCenter,

  [Parameter(Mandatory = $false)]
  # vCenter user with with admin privileges to create the Role and assign that role.
  [string]$vCenterAdminUser = $null,

  [Parameter(Mandatory = $false)]
  # Password for vCenter admin user.
  [string]$vCenterAdminPassword = $null,

  [Parameter(Mandatory = $true)]
  # Rubrik Service Account in vSphere to assign Rubrik privileges to.
  [string]$Username,

  [Parameter(Mandatory = $true)]
  # Domain of Rubrik Service Account in vSphere to assign Rubrik privileges to. 
  # The -Domain parameter format is expected to be SAM; do not use the FQDN of 
  # your domain name (e.g., RUBRIK)
  [string]$Domain,

  [Parameter(Mandatory = $false)]
  # Role name to create. Default: Rubrik_Backup_Service
  [string]$RubrikRole = 'Rubrik_Backup_Service',

  [Parameter(Mandatory = $true)]
  #Select the type of vCenter to add privileges for.
  [ValidateSet('ONPREM', 'VMC', 'AVS', 'GCVE')]
  [string]$vCenterType,

  [Parameter(Mandatory = $false)]
  # vCenter credential file to use. Default is ./vcenter_cred.xml.
  [string]$vCenterCredFile = './vcenter_cred.xml'
)

Import-Module VMware.VimAutomation.Core

clear-host

Write-Host "PowerCLI script to create Rubrik Role which includes required privileges and assigns the designated Rubrik Service Account to Role" `
  -ForeGroundColor Cyan 

# Rubrik Service Account User
# The Rubrik User account is a non-login, least-privileged, vCenter Server account that you specify during deployment.
$RubrikUser = "$Domain\$Username"

#Baseline Privileges to assign to role
#See the Rubrik Administrators Guide for Required Permissions
$Rubrik_AVS_Privileges = @(
  'Datastore.AllocateSpace'
  'Datastore.Browse'
  'Datastore.Config'
  'Datastore.FileManagement'
  'Global.ManageCustomFields' # Added for newer versions of CDM
  'Global.SetCustomField' #Added for newer versions of CDM
  'InventoryService.Tagging.AttachTag' # Added for newer versions of CDM.
  'Network.Assign'
  'Resource.AssignVMToPool'
  'Resource.ColdMigrate'
  'Resource.HotMigrate'
  'Resource.QueryVMotion' # Added for newer versions of CDM
  'Sessions.ValidateSession'
  'StorageProfile.View'
  'StorageViews.View'
  'System.Anonymous'
  'System.Read'
  'System.View'
  'VirtualMachine.Config.AddExistingDisk'
  'VirtualMachine.Config.AddNewDisk'
  'VirtualMachine.Config.AddRemoveDevice'
  'VirtualMachine.Config.AdvancedConfig'
  'VirtualMachine.Config.ChangeTracking'
  'VirtualMachine.Config.CPUCount' # Added for AppFlows support
  'VirtualMachine.Config.DiskLease'
  'VirtualMachine.Config.EditDevice' 
  'VirtualMachine.Config.Memory' # Added for AppFlows support
  'VirtualMachine.Config.RemoveDisk'
  'VirtualMachine.Config.Rename'
  'VirtualMachine.Config.Resource'
  'VirtualMachine.Config.SwapPlacement'
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
  'VirtualMachine.Inventory.CreateFromExisting' # Added for AppFlows support
  'VirtualMachine.Inventory.Delete'
  'VirtualMachine.Inventory.Move'
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

# These privileges are not allowed in AVS but are allowed in VMC and GCVE
$Rubrik_VMC_GCVE_Privileges = $Rubrik_AVS_Privileges + @(
  'StorageProfile.Update' # Added for newer versions of CDM. Not allowed in AVS at this time.
  'VApp.Import' # Required for HotAdd proxies (VMC/GCVE/AVS only)
)

# These Privileges are noy allowed in VMC, AVS or GCVE
$Rubrik_OnPrem_Privileges = $Rubrik_VMC_GCVE_Privileges + @(
  'Cryptographer.Access' # Added for vSphere 6.7?
  'Datastore.Move'
  'Datastore.Delete'
  'Global.DisableMethods' # Added for AppFlows
  'Global.EnableMethods' # Added for AppFlows
  'Global.Licenses'
  'Host.Config.Image'
  'Host.Config.Maintenance'
  'Host.Config.Patch'
  'Host.Config.Storage'
  'Sessions.TerminateSession'
)

if ($vCenterType -eq 'ONPREM') {
  $Rubrik_Privileges = $Rubrik_OnPrem_Privileges
} 
elseif ($vCenterType -eq 'AVS') {
  $Rubrik_Privileges = $Rubrik_AVS_Privileges
}
elseif ($vCenterType -eq 'GCVE') {
  $Rubrik_Privileges = $Rubrik_VMC_GCVE_Privileges
}
elseif ($vCenterType -eq 'VMC') {
  $Rubrik_Privileges = $Rubrik_VMC_GCVE_Privileges
}

Write-Host "Connecting to vCenter at $vCenter."`n -ForeGroundColor Cyan
# If no credential file and no vCenter username/password provided then prompt for creds
if (((Test-Path $vCenterCredFile) -eq $false) -and (!$vCenterAdminUser) -and (!$vCenterAdminPassword)) {
  Write-Host ""
  Write-Host "No credential file found ($vCenterCredFile), please provide vCenter credentials"
  Connect-VIServer -Server $vCenter -Force | Out-Null
}
# Else if user is provided use the username and password
elseif ($vCenterAdminUser) {
  if ($vCenterAdminPassword) {
    #        $vCenterAdminPassword = ConvertTo-SecureString $vCenterAdminPassword -AsPlainText -Force

    Connect-VIServer -Server $vCenter -Username $vCenterAdminUser -Password $vCenterAdminPassword -Force | Out-Null
  }
  # If username provided but not password, prompt for password
  else {
    Write-Host "Password not specified."
    $credential = Get-Credential -Username $vCenterAdminUser

    Connect-VIServer -Server $vCenter -Credential $credential -Force | Out-Null
  }
}
# Else if credential file is found then use it
elseif (Test-Path $vCenterCredFile) {

  # Import Credential file
  $credential = Import-Clixml -Path $vCenterCredFile

  Connect-VIServer -Server $vCenter -Credential $credential -Force | Out-Null
}

Write-Host "Creating a new role called $RubrikRole "`n -ForeGroundColor Cyan 
New-VIRole -Name $RubrikRole -Privilege (Get-VIPrivilege -id $Rubrik_Privileges) | Out-Null

#Get the Root Folder
$rootFolder = Get-Folder -NoRecursion
#Create the Permission
Write-Host "Granting permissions on object $rootFolder to $RubrikUser as role $RubrikRole with Propagation = $true"`n -ForeGroundColor Cyan
New-VIPermission -Entity $rootFolder -Principal $RubrikUser -Role $RubrikRole -Propagate:$true | Out-Null

#Disconnect from the vCenter Server
Write-Host "Disconnecting from vCenter at $vCenter"`n -ForeGroundColor Cyan
Disconnect-VIServer $vCenter -Confirm:$false