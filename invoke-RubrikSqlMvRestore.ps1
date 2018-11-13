param([String]$MVName
      ,[String]$ServerInstance
      ,[String]$Database
      ,[switch]$Replace
      ,[switch]$script
      ,[datetime]$SnapshotDate
      ,[int]$MaxTransferSize
      ,[int]$BufferCount
      ,[int]$BufferSize)

if($SnapshotDate -eq $null){$SnapshotDate = (Get-Date)}
Get-RubrikManagedVolume -Name $MVName | 
    Get-RubrikSnapshot -Date $SnapshotDate.ToUniversalTime() | 
    Sort-Object data -Descending | 
    Select-Object -First 1 | 
    New-RubrikManagedVolumeExport -Confirm:$false |Out-Null

#pause for live mount
Start-Sleep -Seconds 60
$mv = Get-RubrikManagedVolumeExport -SourceManagedVolumeName $mvname
$files = $mv.channels |
    ForEach-Object {$f = get-childitem "\\$($_.ipaddress)\$($_.mountpoint)\*.bak" | Sort-Object lastwritetime -Descending | Select-Object -First 1;Write-Output "DISK='$($f.FullName)'"}

$sql = "RESTORE DATABASE [$Database] FROM " + ($files -join ',') + " WITH STATS=10"
if($Replace){$sql += ",REPLACE"}
if($MaxTransferSize){$sql+=",MAXTRANSFERSIZE=$MaxTransferSize"}
if($BufferCount){$sql+=",BUFFERCOUNT=$BufferCount"}
if($BufferSize){$sql+=",BUFFERCOUNT=$BufferSize"}
if($script){
    Write-Output $sql
} else {
    sqlcmd -S $ServerInstance -Q $sql
}
