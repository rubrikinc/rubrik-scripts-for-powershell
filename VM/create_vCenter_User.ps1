# PowerCLI script to create Rubrik Role which includes required permissions and assign Rubrik Service Account and Role at the root of Hosts and Clusters
# Usage Create_Rubrik_Role.ps1 -vCenter vCenterFQDNorIP -Username ServiceAccountName -Domain AuthenticationDomain

# Get Commandline Parameters - All are required
param(
 [string]$vCenter,
 [string]$Username,
 [string]$Domain
)

clear-host

$usage = "Create_Rubrik_User.ps1 -vCenter vCenterFQDNorIP -Username RubrikServiceAccountName -Domain AuthenticationDomain"
$example = 'Create_Rubrik_User.ps1 -vCenter "vcenter.rubrik.local" -Username svc_rubrik -Domain Rubrik.com' 

Write-Host "PowerCLI script to create Rubrik Role which includes required privileges and assigns the Rubrik Service Account to Role" -ForeGroundColor Cyan 

if ( !$vCenter -or !$Username -or !$Domain ) {
  write-host `n `n"Missing Required Parameter - vCenter, Username, and Domain are required." `n -ForeGroundColor Red
  write-host "Usage: $usage" `n
  write-host "Example: $example" `n
  exit
}

# Rubrik Service Account User
#The Rubrik User account is a non-login, privileged, vCenter Server account that you specify during deployment.
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
  'VirtualMachine.Inventory.Register'
  'VirtualMachine.Inventory.Unregister'
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
Write-Host "You will need to provide a System Administrator account to create the Role and assign that role to $Rubrik_User"`n -ForeGroundColor Cyan
Connect-VIServer $vCenter | Out-Null

Write-Host "Creating a new role called $Rubrik_Role "`n -ForeGroundColor Cyan 
New-VIRole -Name $Rubrik_Role -Privilege (Get-VIPrivilege -id $Rubrik_Privileges) | Out-Null

#Get the Root Folder
$rootFolder = Get-Folder -NoRecursion
#Create the Permission
Write-Host "Granging permissions on object $rootFolder to $Rubrik_User as role $Rubrik_Role with Propagation = $true"`n -ForeGroundColor Cyan
New-VIPermission -Entity $rootFolder -Principal $Rubrik_User -Role $Rubrik_Role -Propagate:$true | Out-Null

#Disconnect from the vCenter Server
Write-Host "Disconnecting from vCenter at $vCenter"`n -ForeGroundColor Cyan
Disconnect-VIServer $vCenter -Confirm:$false
