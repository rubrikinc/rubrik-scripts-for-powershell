<#
.SYNOPSIS
    Get a list of all SQL Server database backups
    WORK IN PROGRESS
    
.DESCRIPTION
    Get a list of all SQL Server database backups. You can either get the last full backup of each database or the latest recovery point in Rubrik.

#>
param(
    [string]$Server,
    [pscredential]$Credential,
    [int]$SLAComplianceMin=60,
    [Int]$SLAWariningMin=180,
    [string]$SLAConfig,
    [string]$SLA,
    [string]$OutPath = ".\",
    [int]$threads=20
)

# Force TLS1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Bypass SSL Cert Check
if (-not("dummy" -as [type])) {
    add-type -TypeDefinition @"
using System;
using System.Net;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

public static class Dummy {
    public static bool ReturnTrue(object sender,
        X509Certificate certificate,
        X509Chain chain,
        SslPolicyErrors sslPolicyErrors) { return true; }
    public static RemoteCertificateValidationCallback GetDelegate() {
        return new RemoteCertificateValidationCallback(Dummy.ReturnTrue);
    }
}
"@
}

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = [dummy]::GetDelegate()

#Internal function to log to host
function Write-Log($msg,[datetime]$startdate)
{   
    $logdate = Get-Date
    $timespan = New-TimeSpan -Start $startdate -End $logdate
    $runtime = "$($timespan.Hours):$($timespan.Minutes):$($timespan.Seconds)"
    Write-Host "[$($logdate.ToSTring('yyyyMMdd HH:mm:ss'))] $msg - Runtime $runtime"
}

#internal function to get nodes in Rubrik cluster, used for parallelization
function getNodes($server, $headers){
    $Servers = @();
    #$uri = [uri]::EscapeUriString("https://$($server)/api/internal/node")
    #$r = Invoke-RestMethod -Headers $headers -Method GET -Uri $uri 
    $r=Invoke-RubrikRESTCall -Endpoint node -Method GET -api internal
    foreach ($node in $r.data){
        if ($node.status -eq "OK"){
            $Servers += $node.ipAddress
            }
        }
        return $Servers
    }

#scriptblock for parallelization
$cmd = {
    param($db, $Servers, $headers, $comp, $warn)
    # Force TLS1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    # Bypass SSL Cert Check
    if (-not("dummy" -as [type])) {
        add-type -TypeDefinition @"
using System;
using System.Net;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

public static class Dummy {
    public static bool ReturnTrue(object sender,
        X509Certificate certificate,
        X509Chain chain,
        SslPolicyErrors sslPolicyErrors) { return true; }
    public static RemoteCertificateValidationCallback GetDelegate() {
        return new RemoteCertificateValidationCallback(Dummy.ReturnTrue);
    }
}
"@
    }

    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = [dummy]::GetDelegate()

    #Get random node and build REST call endpoint
    $server = , $Servers[(Get-Random -Maximum $Servers.count)]
    $uri = [uri]::EscapeUriString("https://$($server)/api/v1/mssql/db/$($db.id)")
    $LastFullBackup = Invoke-RestMethod -Headers $headers -Method GET -Uri $uri 
    
    #Collect data
    $return = [pscustomobject]@{
        DatabaseName            = $db.Name
        RootType                = $db.rootProperties.rootType
        Location                = $db.rootProperties.rootName
        InstanceName            = $db.instanceName
        LiveMount               = $db.isLiveMount
        Relic                   = $db.isRelic
        LastBackup              = if ($LastFullBackup.latestRecoveryPoint -eq $null) { '1/1/1900 00:00:00' }else { (Get-date $LastFullBackup.latestRecoveryPoint -Format 'yyyy-MM-dd HH:mm:ss') }
        ComplianceCheck         = 'FAILURE'
        slaAssignment           = $db.slaAssignment
        configuredSlaDomainName = $db.configuredSlaDomainName
        copyOnly                = $db.copyOnly
        recoveryModel           = $db.recoveryModel
        effectiveSlaDomainName  = $db.effectiveSlaDomainName
        isLogShippingSecondary  = $db.isLogShippingSecondary
        CheckDate               = $(Get-Date)
        ComplianceMinutes       = $comp
        WarningMinutes          = $warn
    }

    #Flag FAILURE/WARNING/TRUE for SLA compliance
    $check = (New-TimeSpan -Start $return.LastBackup -End $return.CheckDate).TotalMinutes
    if($check -lt $comp){
        $return.ComplianceCheck = 'TRUE'
    }elseif ($check -gt $comp -and $check -lt $warn) {
        $return.ComplianceCheck = 'WARNING'
    }
    $return
} #End Process-Thread
#endregion
$start = Get-Date

#Get SLACompliance config
if($SLAConfig){
    #Validate config file path. If not valid, stop
    Test-Path $SLAConfig -ErrorAction Stop
    $ComplianceConfigs = Import-Csv $SLAConfig
}

#Connect to Rubrik
if($Credential){
    Write-Log -msg "Connecting to Rubrik" -startdate $start
    Connect-Rubrik -Server $Server -Credential $Credential | out-null
}else{
    $user = Read-Host "User Name"
    $password = Read-Host -AsSecureString "Password"
    $Credential = New-Object pscredential ($user,$password)
    Write-Log -msg "Connecting to Rubrik" -startdate $start
    Connect-Rubrik -Server $Server -Credential $Credential | out-null
}
Write-Log -msg "Connected to $server" -startdate $start

# Setup Auth Header
$auth = [System.Text.Encoding]::UTF8.GetBytes(("{0}:{1}" -f $Credential.UserName.ToString(),([Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)))))
$auth = [System.Convert]::ToBase64String($auth)
$headers = @{  Authorization = "Basic {0}" -f $auth}
$RubrikDatabases = @()
$Servers = getNodes $Server $headers

if($SLA){
    Write-Log -msg "Collecting databases for $SLA" -startdate $start
    $RubrikDatabases += Get-RubrikDatabase -PrimaryClusterID local -SLA $SLA
    $allpath = Join-Path $OutPath -ChildPath $($SLA + '_' + (Get-Date).ToString('yyyyMMddHHmm')+'_all.csv')
    Write-Log -msg "$SLA collected($($RubrikDatabases.Count) databases)" -startdate $start
} else {
    Write-Log -msg "Collecting all databases" -startdate $start
    $RubrikDatabases = (Invoke-RubrikRESTCall -Method GET -Endpoint mssql/db -Query @{'limit'=999999;'is_live_mount'='false';'is_relic'='false';'primary_cluster_id'='local'}).data 
    $allpath = Join-Path $OutPath -ChildPath $('RubrikDatabases_' + (Get-Date).ToString('yyyyMMddHHmm')+'_all.csv')
    Write-Log -msg "Databases collected($($RubrikDatabases.Count) databases)" -startdate $start
}

#$dbFail = @()
$dbAll = @()
$jobs = @()
#Parse the database arrays
Write-Log -msg "Starting $threads threads for data collection." -startdate $start
foreach ($DB in $RubrikDatabases){
    $count = $(Get-Job -state running).count
    While ($count -ge $threads){
        Start-Sleep -Milliseconds 3
        $count = $(Get-Job -state running).count
    }
    #Check for SLA complinace config. If exists, use those values. Otherwise, use passed values
    $SLACheck = $ComplianceConfigs | Where-Object SLA -eq $db.effectiveSlaDomainName
    if($SLACheck){
        $comp = $SLACheck.ComplianceMin
        $warn = $SLACheck.WarningMin
    }else{
        $comp = $SLAComplianceMin
        $warn = $SLAWariningMin
    }

    $jobs += Start-Job -ScriptBlock $cmd -ArgumentList $DB, $Servers, $headers, $comp, $warn
}
$jobs | Wait-Job | Out-Null
$jobs | ForEach-Object { $dbAll += Receive-Job $_ }
Write-Log -msg "Data collection complete($($dbAll.Length) databases), creating final reports" -startdate $start
$dbAll | Export-csv -path $allpath -NoTypeInformation -Force

$jobs | Remove-Job
Write-Log -msg "Script complete." -startdate $start
