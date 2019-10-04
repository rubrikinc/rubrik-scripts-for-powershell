param([String]$MVName
      ,[String]$ServerInstance
      ,[String]$Database
      ,[switch]$DeleteOld
      ,[switch]$script
      ,[int]$MaxTransferSize
      ,[int]$BufferCount)

$i=0
$mv = Get-RubrikManagedVolume -Name $MVName
$files = $mv.mainExport.channels | 
    ForEach-Object {$i++;"DISK='\\$($_.ipaddress)\$($_.mountpoint)\$Database`_$i`_$(Get-Date -Format 'yyyyMMddHHmmss').bak'"}

$sql = "BACKUP DATABASE [$Database] TO " + ($files -join ',') + " WITH INIT,COMPRESSION,STATS=10"
if($MaxTransferSize){$sql+=",MAXTRANSFERSIZE=$MaxTransferSize"}
if($BufferCount){$sql+=",BUFFERCOUNT=$BufferCount"}
if($script){
    Write-Output $sql
} else {
$mv | Start-RubrikManagedVolumeSnapshot
if($DeleteOld){
    foreach($channel in $mv.mainExport.channels){
        Get-ChildItem -Path "\\$($channel.ipaddress)\$($channel.mountpoint)\$Database_*.bak" | Remove-Item -Force
    }
}
    sqlcmd -S $ServerInstance -Q $sql
    $mv | Stop-RubrikManagedVolumeSnapshot
}
