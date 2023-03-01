param($path, $password_file_path, $mapping_file_path, $verbose, $dry_run)

# get timestamp and use it as log file name
$log_file_name = Get-Date -Format o | ForEach-Object { $_ -replace ":", "." }
$start_timestamp = (New-TimeSpan -Start (Get-Date "01/01/1970") -End (Get-Date)).TotalSeconds
Start-Transcript -Path "$env:LOCALAPPDATA\Rubrik\$($log_file_name).log"

# import modules
Import-Module Rubrik
Import-Module Microsoft.PowerShell.SecretStore

# constants
$max_retries = 3
$success_string = "Success"
$source = "Rubirk-Tag-SLA-Script"

function Set-SLA-Using-VMTag() {
    <#  
    .SYNOPSIS
    Gets the VMs from Rubrik & SCVMM and assigns SLA based on mapping between tags and SLAs
    
    .DESCRIPTION
    This function reads the content from the files mentioned in parameters and connects
    to Rubrik. The list of VMs are retrieved from both SCVMM and Rubrik that are then assigned
    the SLA based on the tag specified to the VM in the SCVMM.
    
    The parameter path takes a csv files which contains the list of cluster ip address, service account user and service account secret in each line for each of the cluster. Example file content:
    10.0.33.172,u1,k1
    10.0.34.121,user_1,key_1

    The parameter password_file_path takes a text file which contains the encrypted password to the vault used to store the service account user and secret. This can be created using the below command
    <"vault_password"> | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString | Out-File <"path_to_store_the_password">

    The parameter mapping_file_path takes the JSON mapping of the tags and the corresponding SLA. Example file content:
    {
    "Black": "Bronze",
    "Red": "Silver",
    "Green": "Gold",
    "Blue": "Test"
    }   

    The parameter dry_run indicates whether it is a dry run or not. True enables it and not passing it will disable it

    The parameter verbose indicates whether verbose logs need to be displayed or not. True neables it and not passing it will disable it
    
    .EXAMPLE
    Main-Function -path "C:\Users\admin\creds.csv" -password_file_path "C:\Users\admin\file.txt" -mapping_file_path "C:\Users\admin\mapping.json" 
    
    .EXAMPLE
    Main-Function -path "C:\Users\admin\creds.csv" -password_file_path "C:\Users\admin\file.txt" -mapping_file_path "C:\Users\admin\mapping.json" -verbose true
    This will display verbose logs.
    
    .EXAMPLE
    Main-Function -path "C:\Users\admin\creds.csv" -password_file_path "C:\Users\admin\file.txt" -mapping_file_path "C:\Users\admin\mapping.json" -verbose true -dry_run true
    This will only display the SLAs to be assigned.
    #>
    Param($path, $password_file_path, $mapping_file_path, $verbose, $dry_run)
    Register-Event-Source
    
    Check-Params "path" $path $dry_run
    Check-Params "password_file_path" $password_file_path $dry_run
    Check-Params "mapping_file_path" $mapping_file_path $dry_run
    
    # Get content from credentials and mapping file
    if (!(Test-Path -Path $path -PathType Leaf)) {
        Write-Output "`nERROR:::Failed to read from file at path: $path"
        if (!dry_run) {
            Write-EventLog -LogName "Application" -Source $source -EventID 3001 -EntryType Error -Message "Failed to read from file at path: $path.ERROR: $_" -Category 1
        }
        exit
    }
    $content = Get-Content -Path $path
    
    $sla_mapping = Get-SLA-Mapping $mapping_file_path $dry_run
    
    $creds = $content | ConvertFrom-String -PropertyNames cluster_ip, user_variable, secret_variable -Delimiter ","
    #Get list of VMs present in SCVMM
    $scvmm_vms = Get-SCVMM-Vms
    $hosts = Get-HostName-And-IP
    if ($verbose) {
        Write-Output "Content from path:"
        Write-Output $creds
        Write-Output "Mapping from path:"
        Write-Output $sla_mapping
        Write-Output "VMS present in SCVMM:"
        Write-Output $scvmm_vms
        Write-Output "Hosts present in SCVMM:"
        Write-Output $hosts
    }
    
    # iterate through all clusters and assign SLAVms
    $len = $creds.Length
    $i = 0
    while ($i -lt $len) {
        $vault_password_encrypted = Get-Content $password_file_path | ConvertTo-SecureString
        $vault_password = New-Object System.Net.NetworkCredential("TestUsername", $vault_password_encrypted, "TestDomain")
        $user_id = Get-Secret-From-Vault $vault_password.Password $creds[$i].user_variable
        $secret = Get-Secret-From-Vault $vault_password.Password $creds[$i].secret_variable
        $connection = Connect-To-Rubrik $creds[$i].cluster_ip $user_id.Password $secret.Password $dry_run
        if ($null -eq $connection) {
            continue
        }
        $rubrik_vms = Get-Rubrik-Vms $dry_run
        if ($null -eq $rubrik_vms) {
            continue
        }
        if ($verbose) {
            Write-Output "VMs from Rubrik for cluster $($creds[$i].cluster_ip)"
            Write-Output $rubrik_vms
        }
        Set-SLA-To-VMs $rubrik_vms $scvmm_vms $sla_mapping $hosts $verbose $dry_run
        $i = $i + 1
        
        # disconnect Rubrik connection
        Disconnect-Rubrik -Confirm:$false
    }
}

function Register-Event-Source() {
    # register the source for logging events
    if ([System.Diagnostics.EventLog]::SourceExists($source) -eq $False) {
        New-EventLog -Source $source -LogName Application 
    }
}

function Get-Secret-From-Vault() {
    Param($vault_password, $variable)
    # unlock the secret store and get the user id and secret from vault 
    Unlock-SecretStore -Password (ConvertTo-SecureString -String $vault_password -AsPlainText -Force)
    $user = Get-Secret -Name $variable
    
    $user_id = New-Object System.Net.NetworkCredential("TestUsername", $user, "TestDomain")
    return $user_id
}

function Connect-To-Rubrik() {
    Param($cluster_ip_address, $user_id, $secret, $dry_run)
    # connect to Rubrik
    $retries = 0
    $connection = $null
    while ($retries -lt $max_retries) {  
        try {
            $connection = Connect-Rubrik -Server $cluster_ip_address -Id $user_id -Secret $secret
            break;
        }
        catch {
            $retries = $retries + 1
            Write-Output "`nERROR:::Could not connect to Rubrik cluster.ERROR: $_"
            if ($retries -lt $max_retries) {
                Write-Output "Retrying the operation"
            }
            else {
                Write-Output "`nERROR:::Skipping the cluster after max retries."
                if (!$dry_run) {
                    Write-EventLog -LogName "Application" -Source $source -EventID 3001 -EntryType Error -Message "Could not connect to Rubrik cluster.ERROR: $_" -Category 1
                }
            }
        }
    }
    return $connection 
}

function Get-SCVMM-Vms() {
    # Get list of VMs from SCVMM machine
    $scvmmVMs = powershell.exe -command 'import-module virtualmachinemanager;Get-SCVirtualMachine | ForEach-Object {"`"$($_.Name)`",`"$($_.Tag)`",`"$($_.Hostname)`",`"$($_.VMId)`""}'
    $scvmmVms = $scvmmVms | ConvertFrom-String -PropertyNames Name, Tag, HostName, VMId -Delimiter ","
    return $scvmmVMs
}

function Get-HostName-And-IP() {
    # Get hostname of the host using IP address
    $hosts = powershell.exe -command 'import-module virtualmachinemanager;Get-SCVMHostNetworkAdapter | ForEach-Object {"`"$($_.VMHost)`",`"$($_.IPAddresses[0])`""}'
    $hosts = $hosts | ConvertFrom-String -PropertyNames Hostname, IpAddress -Delimiter ","
    return $hosts
}

function Get-Rubrik-Vms() {
    Param($dry_run)
    #Get lists of VMs from Rubrik
    $retries = 0
    while ($retries -lt $max_retries) {  
        try {
            $rubrikVMs = Get-RubrikHypervVM -DetailedObject
            if ($rubrikVMs.Status -ne $success_string) {
                break
            }
        }
        catch {
            $retries = $retries + 1
            Write-Output "`nERROR:::Could not get list of Hyper-V VMs from Rubrik.ERROR: $_"
            if ($retries -lt $max_retries) {
                Write-Output "Retrying the operation"
            }
            if ($retries -eq $max_retries) {
                Write-Output "`nERROR:::Skipping the cluster after max retries."
                if (!$dry_run) {
                    Write-EventLog -LogName "Application" -Source $source -EventID 3001 -EntryType Error -Message "Could not get list of Hyper-V VMs from Rubrik.ERROR: $_" -Category 1
                }
                return $null
            }
        }
    } 
    return $rubrikVMs
}

function Get-SLA-Mapping() {
    Param($file_location, $dry_run)
    #Get the sla mapping from the file
    if (!(Test-Path -Path $file_location -PathType Leaf)) {
        Write-Output "`nERROR:::Failed to read from file at path: $file_location"
        if (!$dry_run) {
            Write-EventLog -LogName "Application" -Source $source -EventID 3001 -EntryType Error -Message "Failed to read from file at path: $file_location.ERROR: $_" -Category 1
        }
        exit
    }
    $sla_mapping = Get-Content -Raw -Path $file_location | ConvertFrom-Json
    return $sla_mapping
}

function Get-Matching-Host() {
    Param($hosts, $vm)
    $infraPath = $($vm.infraPath)
    $i = 0
    while ($i -lt $($infraPath.Length)) {
        if ($($infraPath[$i].id).indexOf("HypervServer") -ge 0) {
            $ip = $($infraPath[$i].name)
            break;
        }
        $i = $i + 1
    }
    # The infra path sometimes contains IP address while it contains
    # hostname other times depending on how the RBS was installed. Get
    # hostname in case ip is present else use it directly
    try {
        [ipaddress]$ip
        $ip = "`"$ip`""
        $filteredHost = $hosts | Where-Object { $ip -eq $_.IpAddress }
        $final_result = $($filteredHost.Hostname)
    }
    catch {
        $final_result = "`"$ip`""
    }
    return $final_result
}

function Set-SLA-To-VMs() {
    Param($rubrikVMs, $scvmmVMs, $sla_mapping, $hosts, $verbose, $dry_run)
    #iterate through VMs and assign SLA
    $iteration = 0
    while ($iteration -lt $rubrikVMs.Length) {
        $vm = $rubrikVMs[$iteration]
        
        $hostname = Get-Matching-Host $hosts $vm
        $name = "`"$($vm.Name)`""
        $natural_id = "`"$($vm.naturalId)`""
        Write-Output "`n*********************************************************************************** `n"
        Write-Output "Processing virtual machine with name: $name and id: $($vm.id)"
        
        # prefer natural_id, use name+hostname if it does not exist
        if (($null -ne $natural_id) -and ($natural_id -ne "`"`"")) {
            $filteredVm = $scvmmVMs | where-object { ($natural_id -eq $_.VMId) }
        }
        else {
            if ($verbose) {
                Write-Output "`nINFO:::Did not find natural id in Rubrik response. Will use VM name and host name/ip for mapping"
            }
            $filteredVm = $scvmmVMs | where-object { ($name -eq $_.Name) -and ($hostname -eq $_.HostName) }
        }
        
        # check if the VM is present in list of VMs fetched from SCVMM
        if ($filteredVm.Length -eq 0) {
            Write-Output "`nERROR:::For virtual machine $name in Rubrik, did not find a corresponding virtual machine in SCVMM"
            $iteration = $iteration + 1
            continue
        }
        if ($filteredVm.Length -gt 1) {
            Write-Output "`nERROR:::For virtual machine $name, found 2 or more VMs with the same name in the same host. Cannot tie-break, please assign SLA manually."
            $iteration = $iteration + 1
            if (!$dry_run) {
                Write-EventLog -LogName "Application" -Source $source -EventID 3001 -EntryType Error -Message "For virtual machine $name, found 2 or more VMs with the same name in the same host. Cannot tie-break, please assign SLA manually." -Category 2
            }
            continue
        }
        Write-Output "Corresponding virtual machine from SCVMM:"
        Write-Output $filteredVm
        
        # Get the SLA using the tag and assign it to the VM
        $tag = $filteredVm.Tag -replace '"', ""
        if (($tag.Length -eq 0) -or ($tag -eq "(none)")) {
            Write-Output "`nWARN:::No tag assigned to the virtual machine with name: $name and id: $($vm.id)"
        }
        else {
            if ([bool]($sla_mapping.PSobject.Properties.name -match $tag)) {
                $final_sla = $sla_mapping.$($tag)
                Write-Output "`nINFO:::SLA to be assigned to the VM as per the mapping: $final_sla"
                
                # skip if VM already has the SLA
                if ($vm.configuredSlaDomainName -eq $final_sla) {
                    Write-Output "`nINFO::::Virtual machine with name $name and id $($vm.id) is already protected with SLA $final_sla"
                }
                else {
                    if (!$dry_run) {
                        $retries = 0
                        while ($retries -lt $max_retries) {
                            try {
                                $result = Protect-RubrikHypervVM -id $($vm.id) -sla $final_sla -confirm:$false
                                Write-Output $result
                                Write-Output "`nINFO:::Assigned SLA $final_sla to virtual machine with name $name and id $($vm.id)"
                                break
                            }
                            catch {
                                $retries = $retries + 1
                                Write-Output "`nERROR:::Could not assign SLA to the virtual machine with name $name and id $($vm.id).ERROR: $_"
                                if ($retries -lt $max_retries) {
                                    Write-Output "Retrying the operation"
                                }
                                else {
                                    Write-Output "`nERROR:::Failed to assign SLA after $max_retries attempts"
                                    Write-EventLog -LogName "Application" -Source $source -EventID 3001 -EntryType Error -Message "Could not assign SLA to the virtual machine with name $name and id $($vm.id).ERROR: $_" -Category 2
                                }
                            }
                        } 
                    }
                }
            }
            else {
                Write-Output "`nWARN:::Tag ($tag) assigned to $name not found in mapping"
            }
        }
        
        $iteration = $iteration + 1
    } 
}

function Check-Params() {
    Param($name, $parameter, $dry_run)
    if ($null -eq $parameter) {
        Write-Output "`nERROR:::The parameter $name needs to be passed"
        if (!$dry_run) {
            Write-EventLog -LogName "Application" -Source $source -EventID 3001 -EntryType Error -Message "The parameter $name needs to be passed" -Category 1
        }
        exit
    }
}
Set-SLA-Using-VMTag $path $password_file_path $mapping_file_path $verbose $dry_run

$end_timestamp = (New-TimeSpan -Start (Get-Date "01/01/1970") -End (Get-Date)).TotalSeconds
$diff = ($end_timestamp - $start_timestamp) / 1000
Write-Output "`nINFO:::Finished running script in $diff seconds"

#Stop logging
Stop-Transcript
