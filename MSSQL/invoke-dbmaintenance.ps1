#requires -modules Rubrik

param([parameter(Mandatory=$true)]
      [string]$ServerInstance
      ,[int]$CheckWindow=12
      ,[int]$TimeOutHours=12
      ,[parameter(Mandatory=$true)]
      [string]$RubrikServer
      ,[parameter(Mandatory=$true)]
      [pscredential]$RubrikCred
      ,[parameter(Mandatory=$true)]
      [string]$SystemJobName
      ,[parameter(Mandatory=$true)]
      [string]$UserJobName)

#Set Hostname and Instance name for Rubrik call
if($ServerInstance -contains '\'){
    $HostName = $ServerInstance.Split('\')[0]
    $InstanceName = $ServerInstance.Split('\')[1]
} else {
    $HostName = $ServerInstance
    $InstanceName = 'MSSQLSERVER'
}
#Set initial variables
$CheckTime = (Get-Date).AddHours(-$CheckWindow)
$EndTime = (Get-Date).AddHours($TimeOutHours)
$SystemMaintenace = $false
$UserMaintenance = $false

#Connect to Rubrik and get data to check
Connect-Rubrik -Server $RubrikServer -Credential $RubrikCred | Out-Null
$SystemDatabases = @(Get-RubrikDatabase -Hostname $HostName -Instance $InstanceName | Where-Object {@('master','model','msdb') -contains $_.name -and $_.isRelic -ne 'True'})
$UserDatabases = @(Get-RubrikDatabase -Hostname $HostName -Instance $InstanceName | Where-Object {@('master','model','msdb') -notcontains $_.name -and $_.isRelic -ne 'True'})

#Loop and check on completed snapshots every 30 seconds
do{
    Start-Sleep -Seconds 30

    #Get current listing of snapshots that are within the the check window
    $SystemDBCheck = @($SystemDatabases | Get-RubrikSnapshot -Date (Get-Date) | Where-Object {(Get-Date $_.date) -gt $CheckTime})
    $UserDBCheck  = @($UserDatabases | Get-RubrikSnapshot -Date (Get-Date) | Where-Object {(Get-Date $_.date) -gt $CheckTime})

    #If we have enough snapshots for the system databases and the system maintenance hasn't been started, start system maintenance
    if($SystemDatabases.Count -eq $SystemDBCheck.Count -and $SystemMaintenace -eq $false){
        Invoke-Sqlcmd -ServerInstance $ServerInstance -Database msdb -Query "EXEC sp_start_job @job_name='$SystemJobName';"
        $SystemMaintenace = $true
    }

    #If we have enough snapshots for the user databases and the user maintenance hasn't been started, start user maintenance
    if($UserDatabases.Count -eq $UserDBCheck.Count -and $UserMaintenance -eq $false){
        Invoke-Sqlcmd -ServerInstance $ServerInstance -Database msdb -Query "EXEC sp_start_job @job_name='$UserJobName';"
        $UserMaintenance = $true 
    }
  
    #Check to see if timeout has been reached. If so, error out the job
    if((Get-Date) -gt $EndTime){
        Write-Error "Job run timeout of $TimeOutHours hours reached. Job stopping." -ErrorAction Stop
    }
#Loop until both maintenance jobs have been started
}until(($SystemMaintenace -eq $true -and $UserMaintenance -eq $true))



