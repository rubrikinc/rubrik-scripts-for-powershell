<#
.SYNOPSIS
    Script to enable or disable protection for a SQL Server Availability Group.
.DESCRIPTION
    This script is designed to enable or disable protection across an availability group
    to support cross data center failover. 
.EXAMPLE
    #Enable Protection
    PS C:\> .\multi-dc-ag-failover.ps1 -agname YourAvailabilityGroup -SLAName "SQL SLA" -LogBackupFrequencyMin 15 -LogBackupRetentionDay 14
.EXAMPLE
    #Disable Protection
    PS C:\> .\multi-dc-ag-failover.ps1 -agname YourAvailabilityGroup -Disable
.EXAMPLE
    #Enable Protection and execute a snapshot
    PS C:\> .\multi-dc-ag-failover.ps1 -agname YourAvailabilityGroup -SLAName "SQL SLA" -LogBackupFrequencyMin 15 -LogBackupRetentionDay 14 -NewSnapshot


#>

param(#Availability Group Name
      [Parameter(ParameterSetName='Core')]
      [string]$agname,
      #SLA Domain to be assigned
      [Parameter(ParameterSetName='Enable')]
      [Alias("Enable","SLA")]
      [String]$SLAName,
      #Log backup frequecny in minutes
      [Parameter(ParameterSetName='Enable')]
      [Alias("LogBackupFrequency")]
      [int]$LogBackupFrequencyMin,
      #Log backup retention in days
      [Parameter(ParameterSetName='Enable')]
      [Alias("LogBackupRetention")]
      [int]$LogBackupRetentionDay,
      #Trigger new snapshot when enabling protection
      [Parameter(ParameterSetName='Enable')]
      [Switch]$NewSnapshot,
      #disable protection
      [Parameter(ParameterSetName='Disable')]
      [Switch]$Disable
      )

#gather databases to be altered based on AG name
$dbs = Get-RubrikDatabase -AvailabilityGroupName $agname

#If an SLA is declared, protection is being enabled. 
if($SLAName.Length -gt 0) {
      $dbs | Set-RubrikDatabase -SLA $SLAName -LogBackupFrequencyInSeconds ($LogBackupFrequencyMin * 60) -LogRetentionHours ($LogBackupRetentionDay * 24) -Confirm:$false

      #if NewSnapshot is flagged, execute a new on-demand snapshot once protection is re-enabled
      if($NewSnapshot){
            $dbs | New-RubrikSnapshot -SLA $SLAName -Confirm:$false
      }
}

#if the Disable switch is flagged, 
if($Disable){
      $dbs | Set-RubrikDatabase -SLA UNPROTECTED -LogBackupFrequencyInSeconds 0 -LogRetentionHours 0 -Confirm:$false
}