<#
.SYNOPSIS
    Script to enable or disable protection for a SQL Server Availability Group.
.DESCRIPTION
    This script is designed to enable or disable protection across an availability group
    to support cross data center failover. This script assumes that all the databases in the AG
    are inheriting from the AG and no databases are directly assigned. It also assumes that the
    SLA domain name is the same for both sides of the AG.

    The script assumes that the SQL portion of the failover will be executed outside of the
    script. To use the script, you will declare:
        -The name of the Availability Group that is failing over.
        -A Primary Rubrik cluster where protection will be enabled.
        -A Secondary Rubrik cluster where protection will be disabled.
        -Log backup frequency and retention for the Availability Group.
        -Whether or not a new snapshot should be taken once the failover is complete.
        -A credential or a token for each Rubrik cluster to authenticate the access.


.EXAMPLE
    .\multi-dc-ag-failover.ps1 -agname YourAGName -PrimaryRubrikCluster RubrikCluster1 -PrimaryRubriCredential $cred -SecondaryRubrikCluster RubrikCluster1 
        -SecondaryRubriCredential $cred -SLAName 'YourSLADomain' -LogBackupFrequencyMin 60 -LogBackupRetentionDays 3 -NewSnapshot  


#>

param(#Availability Group Name
      [string]$agname,

      #Primary Rubrik connection info (cluster, user, password/token)
      [string]$PrimaryRubrikCluster,
      [pscredential]$PrimaryRubriCredential,
      [string]$PrimaryRubrikToken,

      #Secondary Rubrik connection info (cluster, user, password/token)
      [string]$SecondaryRubrikCluster,
      [pscredential]$SecondaryRubriCredential,
      [string]$SecondaryRubrikToken,

      #SLA Domain to be assigned
      [Alias("SLA")]
      [String]$SLAName,

      #Log backup frequecny in minutes
      [Alias("LogBackupFrequency")]
      [int]$LogBackupFrequencyMin,

      #Log backup retention in days
      [Alias("LogBackupRetention")]
      [int]$LogBackupRetentionDays,

      #Trigger new snapshot when enabling protection
      [Switch]$NewSnapshot
      )

function New-RubrikConnection{
    param($server,[pscredential]$cred,$token)
    switch($true){
        {$cred} {
            $return = @{
                Server = $server
                Credential = $cred
            }
        }
        {$token} {
            $return = @{
                Server = $server
                Token = $token
            }
        }
        default {
            $return = @{
                Server = $server
            }
        }
    }
    return $return
}
#connect to the cluster that will be the secondary
$connection = New-RubrikConnection -server $SecondaryRubrikCluster -cred $SecondaryRubriCredential -token $SecondaryRubrikToken
Connect-Rubrik @connection | Out-Null
$secondarycluster = Get-RubrikClusterInfo
#gather AG
$secondaryag = Get-RubrikAvailabilityGroup -GroupName $agname | Where-Object primaryClusterId -eq  $secondarycluster.id
$secondaryconfig = [PSCustomObject]@{'logBackupFrequencyInSeconds'=0;'logRetentionHours'=0;'configuredSlaDomainId'='UNPROTECTED'}
Invoke-RubrikRESTCall -Endpoint "mssql/availability_group/$($secondaryag.id)" -Method PATCH -api 'internal' -Body $secondaryconfig

#connect to the cluster that will be the primary
$connection = New-RubrikConnection -server $PrimaryRubrikCluster -cred $PrimaryRubriCredential -token $PrimaryRubrikToken
Connect-Rubrik @connection | Out-Null
$primarycluster = Get-RubrikClusterInfo 

#Enable protection on primary Rubrik cluster
$primaryag = Get-RubrikAvailabilityGroup -GroupName $agname | Where-Object primaryClusterId -eq $primarycluster.id
$slaid = (Get-RubrikSLA -Name $SLAName -PrimaryClusterID local).id
$primaryconfig = [PSCustomObject]@{'logBackupFrequencyInSeconds'=($LogBackupFrequencyMin * 60);'logRetentionHours'=($LogBackupRetentionDays * 24) ;'configuredSlaDomainId'=$slaid}
Invoke-RubrikRESTCall -Endpoint "mssql/availability_group/$($primaryag.id)" -Method PATCH -api 'internal' -Body $primaryconfig 
#if NewSnapshot is flagged, execute a new on-demand snapshot once protection is re-enabled
if($NewSnapshot){
    Get-RubrikDatabase -AvailabilityGroupName $agname | Where-Object isRelic -ne 'TRUE' | New-RubrikSnapshot -SLA $SLAName -Confirm:$false
}

