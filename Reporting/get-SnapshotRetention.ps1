<#
.SYNOPSIS
Creates a report for Retention Snapshot

.DESCRIPTION
Script will query the Rubrik API and get the recordset from Retention Snapshot GUI 

.PARAMETER OutFile
Lacation to save the CSV file.
ex. -OutFile "c:\temp\SnapshotRetention.csv"

.PARAMETER Filter
Represents the the filter object, you should use one of the above list:
VirtualMachine          -- for vSphere VMs
VcdVapp                 -- for vCD vApps
HypervVirtualMachine    -- for Hyper-V VMs
NutanixVirtualMachine   -- for AHV VMs
LinuxHost               -- for Linux & Unix Hosts
WindowsHost             -- for Windows Hosts
ShareFileset            -- for NAS Shares
MssqlDatabase           -- for SQL Server DBs
ManagedVolume           -- for Managed Volume
Ec2Instance             -- for EC2 Instances
OracleDatabase          -- for Oracle DBs

.PARAMETER first
To limitate the number or records, if you don't at this parameter the script will return information for ALL snapshot and this can take longer to be completed

.EXAMPLE
#connecting to the Rubrik cluster
$Cred = get-credential
Connect-Rubrik '172.xx.xx.xx' -Credential $Cred

.\get-SnapshotRetention.ps1 -OutFile "c:\temp\SnapshotRetention.csv" -first 50 -filter MssqlDatabase

.NOTES
    Name:               Return the information about the Snapshot Retention
    Created:            06/09/2019
    Author:             Marcelo Fernandes
#>

param(
    # Parameter save the CSV file
    [Parameter(Mandatory=$true)]
    [string]$OutFile,

    #Parameter to filter the object type
    [Parameter(Mandatory=$false)]
    [ValidateSet("VirtualMachine","VcdVapp","HypervVirtualMachine","NutanixVirtualMachine","LinuxHost","WindowsHost","ShareFileset","MssqlDatabase","ManagedVolume","Ec2Instance","OracleDatabase")]
    [string]$filter,
    
    #add limit to the number of records
    [Parameter(Mandatory=$false)]
    [int]$first
)

$Header = $global:RubrikConnection.header
$uri = "https://"+$($global:RubrikConnection.server)+"/api/internal/graphql"    

if($filter){
    $Queryfilter='"objectType": "'+$filter+'",'
}else{$Queryfilter=""}

if($first){
    $Queryfirst=', "first": '+$first+''
}else{$Queryfirst=""}

$body = '
{"query":"query UnmanagedObject(\n  $name: String,\n  $unmanagedStatus: String,\n  $objectType: String,\n  $sortBy: String,\n  $sortOrder: String\n  $first: Int,\n  $after: String,\n) {\n  unmanagedObjectConnection(\n    name: $name,\n    unmanagedStatus: $unmanagedStatus,\n    objectType: $objectType,\n    sortBy: $sortBy,\n    sortOrder: $sortOrder,\n    first: $first,\n    after: $after,\n  )\n  {\n    nodes {\n      id,\n      name,\n      objectType,\n      physicalLocation {\n        id,\n        name\n      },\n      unmanagedStatus,\n      autoSnapshotCount,\n      manualSnapshotCount,\n      localStorage,\n      archiveStorage,\n      retentionSlaDomainId,\n      retentionSlaDomainName,\n      retentionSlaDomainPolarisManagedId\n    },\n    pageInfo {\n      endCursor,\n      hasNextPage\n    }\n  },\n}\n","variables":{'+$Queryfilter+'"sortBy":"Name","sortOrder":"asc"'+$Queryfirst+'}}
'
Write-Host "Querying API..." -ForegroundColor Yellow

$response =(Invoke-RestMethod -Uri $uri -Headers $Header -Method POST -Body $body).data

$output_array = @()
foreach($recordM in $response.unmanagedObjectConnection.nodes){
    $row = '' | select id,name,objectType,Location,ObjectAvailability,PolicyBasedRetentionSla,autoSnapshotCount,manualSnapshotCount,localStorage_MB,archiveStorage_MB,SnapshotType,date,SnapshotRetentionSla
    $row.Id= $recordM.id;
    $row.Name= $recordM.name;
    $row.objectType= $recordM.objectType;
    $row.Location= $recordM.physicalLocation.name -join "/";
    $row.ObjectAvailability = $recordM.unmanagedStatus;
    $row.PolicyBasedRetentionSla= if($recordM.autoSnapshotCount -gt 0){$recordM.retentionSlaDomainName}else{"None"};
    $row.autoSnapshotCount= $recordM.autoSnapshotCount;
    $row.manualSnapshotCount= $recordM.manualSnapshotCount;
    $row.localStorage_MB= [math]::round($recordM.localStorage/1MB,2);
    $row.archiveStorage_MB= [math]::round($recordM.archiveStorage/1MB,2);

    $row.SnapshotType= "";
    $row.date = "";
    $row.SnapshotRetentionSla= "";
    $output_array += $row

    #detailed report
    $responseD =(Invoke-RubrikRESTCall -Endpoint "unmanaged_object/$($recordM.id)/snapshot" -api internal -Method GET).data | Sort-Object date
    foreach($recordD in $responseD){
        $row = '' | select id,name,objectType,Location,ObjectAvailability,RetentionSla,autoSnapshotCount,manualSnapshotCount,localStorage_MB,archiveStorage_MB,SnapshotType,date,SnapshotRetentionSla
        $row.Id= $recordM.id;
        $row.Name= "";
        $row.objectType= "";
        $row.Location= "";
        $row.ObjectAvailability = "";
        $row.RetentionSla= "";
        $row.autoSnapshotCount= "";
        $row.manualSnapshotCount= "";
        $row.localStorage_MB= "";
        $row.archiveStorage_MB= "";

        $row.SnapshotType= $recordD.unmanagedSnapshotType;
        $row.date = (get-date($recordD.date)).ToString('yyyy/MM/dd HH:mm:ss');
        $row.SnapshotRetentionSla= $recordD.retentionSlaDomainName;
        $output_array += $row
    }
}
$output_array | Export-Csv -Path $OutFile -NoTypeInformation
Write-Host "File Exported to [$OutFile]" -ForegroundColor Green