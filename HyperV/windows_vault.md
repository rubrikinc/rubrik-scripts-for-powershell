The windows vault is used to store secrets securely. Follow the below instructions to install and use the Windows vault. These need to be run in a Powershell 6.0+ window:

Install the required PowerShell modules (check installing Nuget section if you run into Nuget errors):
    
    Install-Module -Name Microsoft.PowerShell.SecretManagement 
    Install-Module -Name Microsoft.PowerShell.SecretStore 

Create a vault with the Register-SecretVault cmdlet with a name, module name, and other details if you do not want to use the default configuration. To create a default vault, run the following command:
    
    Register-SecretVault -Name <vault_name> -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
To create a secret, run Set-Secret with a name and value. For example, to add a secret, execute the following command:
    
    Set-Secret -Name <secret_name> -Secret <secret>
Because this is the first secret to be saved in the vault, PowerShell will prompt you for a password to add, retrieve, remove and save secrets.
To retrieve the value, call the Get-Secret command with the name of the item secret:
    
    Get-Secret -Name <secret_name>

### Installing Nuget provider:
Follow the below instructions to install the NuGet provider:
    
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-PackageProvider -Name NuGet
### Example:
    Register-SecretVault -Name Rubrik -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
    Set-Secret -Name rubrik_user -Secret User:::145a3679-dc83-472e-9839-0f27351ecf6e 
    Set-Secret -Name rubrik_key -Secret ktBpxACj078d83a3k22hLcC/eVbUCnJa6H5CUee/auJ0AlQ9TrlxjGwr5u73UI2RF2Ut0j7QmUOkweP7wKc2
Share the names of the secret which in this case are rubrik_user and rubrik_key and the password of the vault as used in step 4
