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

param([Parameter(ParameterSetName='Core')]
      [string]$agname,
      [Parameter(ParameterSetName='Enable')]
      [Alias("Enable","SLA")]
      [String]$SLAName,
      [Parameter(ParameterSetName='Enable')]
      [Alias("LogBackupFrequency")]
      [int]$LogBackupFrequencyMin,
      [Parameter(ParameterSetName='Enable')]
      [Alias("LogBackupRetention")]
      [int]$LogBackupRetentionDay,
      [Parameter(ParameterSetName='Enable')]
      [Switch]$NewSnapshot,
      [Parameter(ParameterSetName='Disable')]
      [Switch]$Disable
      )

$dbs = Get-RubrikDatabase -AvailabilityGroupName $agname

if($SLAName.Length -gt 0) {
      $dbs | Set-RubrikDatabase -SLA $SLAName -LogBackupFrequencyInSeconds ($LogBackupFrequencyMin * 60) -LogRetentionHours ($LogBackupRetentionDay * 24) -Confirm:$false

      if($NewSnapshot){
            $dbs | New-RubrikSnapshot -SLA $SLAName -Confirm:$false
      }
}
if($Disable){
      $dbs | Set-RubrikDatabase -SLA UNPROTECTED -LogBackupFrequencyInSeconds 0 -LogRetentionHours 0 -Confirm:$false
}