<#
.SYNOPSIS
    Script to enable or disable protection for a SQL Server Availability Group.
.DESCRIPTION
    This script is designed to enable or disable protection across an availability group
    to support cross data center failover. This script assumes that all the databases in the AG
    are inheriting from the AG and no databases are directly assigned. It also assumes that the
    SLA domain name is the same for both sides of the AG.
.EXAMPLE
    .\multi-dc-ag-failover -AGname YourAG -PrimaryRubrikCluster cluster1.yourdomain.com -PrimaryRubrikToken '0000-0000-0000-0000-0000' -SecondaryRubrikCluster cluster2.yourdomain.com -SecondaryRubrikToekn '0000-0000-0000-0000-0000'
        -SLAName 'YourSLA' -LogBackupFrequencyMin 15 -LogBackupRetentionDays 14


#>

param(#Availability Group Name
      [Parameter(ParameterSetName='Core')]
      [string]$agname,

      #Primary Rubrik connection info (cluster, user, password/token)
      [Parameter(ParameterSetName='Core')]
      [string]$PrimaryRubrikCluster,
      [Parameter(ParameterSetName='Core')]
      [pscredential]$PrimaryRubriCredential,
      [Parameter(ParameterSetName='Core')]
      [string]$PrimaryRubrikToken,

      #Secondary Rubrik connection info (cluster, user, password/token)
      [Parameter(ParameterSetName='Core')]
      [string]$SecondaryRubrikCluster,
      [Parameter(ParameterSetName='Core')]
      [pscredential]$SecondaryRubriCredential,
      [Parameter(ParameterSetName='Core')]
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
    param($server,[securestring]$cred,$token)
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
Connect-Rubrik @connection
#gather AG
$secondaryag = Get-RubrikAvailabilityGroup -GroupName $agname
Set-RubrikAvailabilityGroup -id $secondaryag.id -SLA UNPROTECTED -LogBackupFrequencyInSeconds 0 -LogRetentionHours 0 -Confirm:$false

#connect to the cluster that will be the primary
$connection = New-RubrikConnection -server $PrimaryRubrikCluster -cred $PrimaryRubriCredential -token $PrimaryRubrikToken
Connect-Rubrik @connection

#Enable protection on primary Rubrik cluster
$primaryag = Get-RubrikAvailabilityGroup -GroupName $agname
Set-RubrikAvailabilityGroup -id $primaryag.id -SLA $SLAName -LogBackupFrequencyInSeconds ($LogBackupFrequencyMin * 60) -LogRetentionHours ($LogBackupRetentionDays * 24) -Confirm:$false

#if NewSnapshot is flagged, execute a new on-demand snapshot once protection is re-enabled
if($snapshot -eq $true){
    Get-RubrikDatabase -AvailabilityGroupName $agname | Where-Object isRelic -ne 'TRUE' | New-RubrikSnapshot -SLA $SLAName -Confirm:$false
}

