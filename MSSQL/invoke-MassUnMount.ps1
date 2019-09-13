<#
.SYNOPSIS
mass-unMount is used to unMount multiple databases.

.DESCRIPTION
Based on parameters supplied, mass-unMount will start unmounting LM databases for supplied databases or whole instance.

.PARAMETER databases
It is an optional parameter, if is supplied, the script will start unMount LM DBs only for supplied DBs on this parameter. 
If this parameter was not supplied, the script will consider all LM databases supplied on ServerInstance parameter

.PARAMETER ServerInstance
SQL Server Instance name that has the LM DBs, e.g. SQLserv01\Prod

.EXAMPLE
Start unMount LM DBs for supplied databases.
    $RubrikServer = "172.21.8.51"
    $RubrikCredential = (Get-Credential -Message 'Please enter your Rubrik credentials')
    Connect-Rubrik -Server $RubrikServer -Credential $RubrikCredential
    .\mass-unMount.ps1 -databases "AdventureWorks2014","DBTest01","DBTest02" -ServerInstance "sql1.domain.com"
        
.EXAMPLE
Start unMount all LM DBs on the instance.
    $RubrikServer = "172.21.8.51"
    $RubrikCredential = (Get-Credential -Message 'Please enter your Rubrik credentials')
    Connect-Rubrik -Server $RubrikServer -Credential $RubrikCredential
    .\mass-unMount.ps1 -ServerInstance "sql1.domain.com"

.NOTES
Name:               Mass unMount Live Mounted databases
Created:            09/13/2018
Author:             Marcelo Fernandes
Execution Process:
    Before running this script, you need to connect to the Rubrik cluster, and also ensure SQL Permission for account that will run this script.
        Ex.
        $RubrikServer = "172.21.8.51"
        #$RubrikCredential = (Get-Credential -Message 'Please enter your Rubrik credentials')
        Connect-Rubrik -Server $RubrikServer -Credential $RubrikCredential
#>

param( [String[]] $databases
        ,[Parameter(Mandatory=$true)]
        [String] $ServerInstance              
        )


function ConvertFrom-ServerInstance($ServerInstance) {
    if($ServerInstance.Contains('\')){
        $si = $ServerInstance.Split('\')
        $return = New-Object psobject -Property @{'hostname'= $si[0];'instancename'=$si[1]}
    } else {
        $return = New-Object psobject -Property @{'hostname'= $ServerInstance;'instancename'='MSSQLSERVER'}
    }
    return $return
}

function Wait-RubrikRequests($reqs) {
    do{
        Start-Sleep -Seconds 15
        $reqs = $reqs | Get-RubrikRequest -Type mssql -ErrorAction SilentlyContinue
    }until(($reqs | Where-Object {@('QUEUED','RUNNING','FINISHING') -contains $_.status} | Measure-Object).Count -eq 0)
}

$source = ConvertFrom-ServerInstance $ServerInstance
$TargetInstance = (Get-RubrikSQLInstance -ServerInstance $source)
#Getting user databases by instance if the $databases parameter was not informed
if(!$databases){
    $databases=@{}
    $dbExclusion ="master","Tempdb","model","msdb","distribution"
    $databases = $(Get-RubrikDatabase -Hostname $source.hostname -Instance $source.instance | Where-Object {$_.isrelic -ne 'TRUE' -and $_.isLiveMount -ne 'TRUE' -and $_.name  -notmatch [String]::Join('|', $dbExclusion)}| Select-Object name).name
}

"Begining unmount/cleanup process for: $($databases -join ",")" | Out-Host
$unmount_reqs = Get-RubrikDatabaseMount -TargetInstanceId $TargetInstance.id |
    Where-Object {$databases -contains $_.sourceDatabaseName} |
    Remove-RubrikDatabaseMount -Confirm:$false

if($unmount_reqs) {Wait-RubrikRequests $unmount_reqs}