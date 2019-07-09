<#
.SYNOPSIS
    Get a list of all SQL Server database backups
.DESCRIPTION
    Get a list of all SQL Server database backups. You can either get the last full backup of each database or the latest recovery point in Rubrik. 
.EXAMPLE
    Get last full backup data
    .\DatabaseBackupReport.ps1 -RubrikServer 256.256.256.256 -RestoreTime "last full" -ComplianceHours 24
.EXAMPLE
    Get latest backup data
    .\DatabaseBackupReport.ps1 -RubrikServer 256.256.256.256 -RestoreTime "latest" -ComplianceHours 24
.PARAMETER RubrikServer
    Will be the IP address or the name of the Rubrik Server
.PARAMETER RestoreTime
    Either of the following two values are accepted.
        last full:  Will retrieve the last full backup of each database in Rubrik
        latest:     Will retrieve the latest recovery point Rubik has. This will include any full backups and transaction log backups that are applicable to the database
.PARAMETER ComplianceHours
    Just comparest the backup time retrieved against NOW() and will state if the time difference is greater than the compliance hours value. 
.PARAMETER OutFile
    File name to write output too. Will defualt to the current directory and a file name of DatabaseBackupReport.csv
.NOTES
    General notes
#>
param(
    # Will be the IP address or the name of the Rubrik Server
    [Parameter(Position=0)]
    [string]$RubrikServer = $RubrikCluster.DEVOPS1,
    # Will either be last full or latest
    [Parameter(Position=1)]
    [ValidateSet("last full","latest")]
    [string]$RestoreTime,
    # Just comparest the backup time retrieved against NOW() and will state if the time difference is greater than the compliance hours value. 
    [Parameter(Position=2)]
    [string]$ComplianceHours = 24,
    # File name to write output too. Will defualt to the current directory and a file name of DatabaseBackupReport.csv
    [Parameter(Position=3)]
    [string]$OutFile = ".\DatabaseBackupReport.csv"
)

Import-Module Rubrik -Force
Connect-Rubrik -Server $RubrikServer -Credential $Credentials.RangerLab
#region FUNCTIONS
$Path = ".\Functions"
Get-ChildItem -Path $Path -Filter *.ps1 |Where-Object { $_.FullName -ne $PSCommandPath } |ForEach-Object {
    . $_.FullName
}
#endregion

$RubrikDatabases = Get-RubrikDatabase -PrimaryClusterID local
$db = @()
$Now = Get-Date
foreach ($RubrikDatabase in $RubrikDatabases){
    $LastFullBackup = Get-DatabaseRecoveryPoint -RubrikDatabase $RubrikDatabase -RestoreTime $RestoreTime
    $OutOfCompliance = $false
    if([string]::IsNullOrEmpty($LastFullBackup)){
        $OutOfCompliance = $true
    }else{
        if ((New-TimeSpan -Start $LastFullBackup -End $Now).TotalHours -gt $ComplianceHours ){$OutOfCompliance = $true}   
    }
    
    
    $db += [pscustomobject]@{
        DatabaseName = $RubrikDatabase.Name
        RootType = $RubrikDatabase.rootProperties.rootType
        Location = $RubrikDatabase.rootProperties.rootName
        LiveMount = $RubrikDatabase.isLiveMount
        Relic = $RubrikDatabase.isRelic
        LastBackup = $LastFullBackup
        OutOfCompliance = $OutOfCompliance
        slaAssignment = $RubrikDatabase.slaAssignment
        configuredSlaDomainName = $RubrikDatabase.configuredSlaDomainName
        copyOnly = $RubrikDatabase.copyOnly
        recoveryModel = $RubrikDatabase.recoveryModel
        effectiveSlaDomainName = $RubrikDatabase.effectiveSlaDomainName
        isLogShippingSecondary = $RubrikDatabase.isLogShippingSecondary
    }
}

$db | Export-csv -path $OutFile -NoTypeInformation -Force
#| where {$_.Relic -eq $false -and $_.LiveMount -eq $false -and $_.OutOfCompliance -eq $True} 