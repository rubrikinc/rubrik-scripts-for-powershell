[CmdletBinding()]
param (
    [Parameter()]
    [string]$RubrikCluster
)
Connect-Rubrik -Server $Rubrikcluster

$RubrikUsers = @()
$principal_search_payload = New-Object -typename psobject -Property @{
    "queries"= @(new-object -TypeName psobject -Property @{
        "hasAuthorizations"= $true
        "isDeleted"= $false
        }
    )
}



$LDAPServices = (Invoke-RubrikRESTCall -Endpoint 'ldap_service' -api 1 -Method GET).data

$principals = (Invoke-RubrikRESTCall -Endpoint 'principal_search' -Method POST -api internal -Body $principal_search_payload -Verbose).data 

foreach ($principal in $principals){
    $permissions = (Invoke-RubrikRESTCall -Endpoint 'authorization' -Method GET -api internal -Query @{'principals'=$principal.id} -verbose ).data
    
    
    $user = New-Object PSObject
    # $user | Add-Member -type NoteProperty -name id -Value $principal.id
    $user | Add-Member -type NoteProperty -name userName -Value $principal.name
    $Directory = $LDAPServices | Where-Object {$_.id -eq $principal.authDomainId} 
    $user | Add-Member -type NoteProperty -name Directory -Value $Directory.name
    $user | Add-Member -type NoteProperty -name Type -Value $principal.principalType
    $user | Add-Member -type NoteProperty -name Description -Value $principal.Description

    if($Permissions.readOnlyAdmin.basic -ne $null){ $readOnly = $true} else { $readOnly = $false }
    if($Permissions.admin.fullAdmin -ne $null){ $fullAdmin = $true } else { $fullAdmin = $false }
    if($Permissions.organization.viewLocalLdapSerice -ne $null){ $viewLocalLdapSerice = $true } else { $viewLocalLdapSerice = $false }
    if($Permissions.organization.manageSla -ne $null){ $manageSla = $true } else { $manageSla = $false }
    if($Permissions.organization.viewPrecannedReport -ne $null){ $viewPrecannedReport = $true } else { $viewPrecannedReport = $false }
    if($Permissions.organization.manageSelf -ne $null){ $manageSelf = $true } else { $manageSelf = $false }
    if($Permissions.organization.useSla -ne $null){ $useSla = $true } else { $useSla = $false }
    if($Permissions.organization.manageResource -ne $null){ $manageResource = $true } else { $manageResource = $false }
    if($Permissions.organization.viewOrg -ne $null){ $viewOrg = $true } else { $viewOrg = $false }
    if($Permissions.organization.manageCluster -ne $null){ $manageCluster = $true } else { $manageCluster = $false }
    if($Permissions.organization.createGlobal -ne $null){ $createGlobal = $true } else { $createGlobal = $false }
    if($Permissions.managedVolumeAdmin.basic -ne $null){ $managedVolumeAdmin = $true } else { $managedVolumeAdmin = $false }
    if($Permissions.managedVolumeUser.basic -ne $null){ $managedVolumeUser = $true } else { $managedVolumeUser = $false }
    if($Permissions.endUser.viewEvent -ne $null){ $viewEvent = $true } else { $viewEvent = $false }
    if($Permissions.endUser.restoreWithoutDownload -ne $null){ $restoreWithoutDownload = $true } else { $restoreWithoutDownload = $false }
    if($Permissions.endUser.destructiveRestore -ne $null){ $destructiveRestore = $true } else { $destructiveRestore = $false }
    if($Permissions.endUser.onDemandSnapshot -ne $null){ $onDemandSnapshot = $true } else { $onDemandSnapshot = $false }
    if($Permissions.endUser.viewReport -ne $null){ $viewReport = $true } else { $viewReport = $false }
    if($Permissions.endUser.restore -ne $null){ $restore = $true } else { $restore = $false }
    if($Permissions.endUser.provisionOnInfra -ne $null){ $provisionOnInfra = $true } else { $provisionOnInfra = $false }

    if($Permissions.admin.fullAdmin -ne $null) {
        $readOnly = $true
        $fullAdmin = $true
        $viewLocalLdapSerice = $true
        $manageSla = $true
        $viewPrecannedReport = $true
        $manageSelf = $true
        $useSla = $true
        $manageResource = $true
        $viewOrg = $true
        $manageCluster = $true
        $createGlobal = $true
        $managedVolumeAdmin = $true
        $managedVolumeUser = $true
        $viewEvent = $true
        $restoreWithoutDownload = $true
        $destructiveRestore = $true
        $onDemandSnapshot = $true
        $viewReport = $true
        $restore = $true
        $provisionOnInfra = $true
    }

    $user | Add-Member -type NoteProperty -name "Full Administrator" -Value $fullAdmin
    $user | Add-Member -type NoteProperty -name "Managed Volume Admin" -Value $managedVolumeAdmin
    $user | Add-Member -type NoteProperty -name "Managed Volume User" -Value $managedVolumeUser
    $user | Add-Member -type NoteProperty -name "Read Only" -Value $readOnly
    $user | Add-Member -type NoteProperty -name "viewLocalLdapSerice" -Value $viewLocalLdapSerice
    $user | Add-Member -type NoteProperty -name "Manage Sla" -Value $manageSla
    $user | Add-Member -type NoteProperty -name "Use SLA" -Value $useSla
    $user | Add-Member -type NoteProperty -name "viewPrecannedReport" -Value $viewPrecannedReport
    $user | Add-Member -type NoteProperty -name "manageSelf" -Value $manageSelf
    $user | Add-Member -type NoteProperty -name "Managed Resource" -Value $manageResource
    $user | Add-Member -type NoteProperty -name "View Org" -Value $manageCluster
    $user | Add-Member -type NoteProperty -name "Create Global" -Value $createGlobal
    $user | Add-Member -type NoteProperty -name "View Event" -Value $viewEvent
    $user | Add-Member -type NoteProperty -name "Restore Without Download" -Value $restoreWithoutDownload
    $user | Add-Member -type NoteProperty -name "Destructive Restore" -Value $destructiveRestore
    $user | Add-Member -type NoteProperty -name "On Demand Snapshot" -Value $onDemandSnapshot
    $user | Add-Member -type NoteProperty -name "View Report" -Value $viewReport
    $user | Add-Member -type NoteProperty -name "Restore" -Value $restore
    $user | Add-Member -type NoteProperty -name "Provision On Infrastructure" -Value $provisionOnInfra

    
    $RubrikUsers += $user
}


$RubrikUsers |  Export-Csv -Path .\RubrikEffectivePermissions.csv
