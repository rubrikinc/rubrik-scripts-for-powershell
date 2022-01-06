param($csvfile
      ,$delimiter = '|'
      ,[int[]]$HistogramBins=@(1,10,100,500,1000))

$data = Get-Content $csvfile 

if ($data[0].Substring(1,10) -ne "ServerName")
{
    $Header ="ServerName","SQLVersion","name","recovery_model_desc","SevenDayLogBackupMB","AverageFullMB","AverageFullTimeSec","AverageLogTimeSec","DBTotalSizeMB","AverageLogBackupInterval","ChangeCapture","ColumnStoreIndex","Compression","FILESTREAM","InMemoryOLTP","Partitioning","TransparentDatabaseEncryption", "NumberOfFiles"
    $rawdata = Get-Content $csvfile | ConvertFrom-Csv -Delimiter $delimiter -Header $Header
}
else 
{
    $rawdata = Get-Content $csvfile | ConvertFrom-Csv -Delimiter $delimiter 
}

$DailyLogChurn = ($rawdata | Measure-Object -Property SevenDayLogBackupMB -Sum).Sum/7
$EstimatedChangePerc = $DailyLogChurn/($rawdata | Where-Object {$_.recovery_model_desc -ne 'SIMPLE'} | Measure-Object -Property DBTotalSizeMB -Sum).Sum

$return = [ordered]@{
            'DB Count' = ($rawdata | Measure-Object).Count
            'DBs in Full' = ($rawdata | Where-Object {$_.recovery_model_desc -ne 'SIMPLE'} | Measure-Object).Count
            'Server Count' =  ($rawdata | Group-Object -Property ServerName | Measure-Object).Count
            'Total DB Size (GB)' = (($rawdata | Measure-Object -Property DBTotalSizeMB -Sum).Sum/1024).ToString('0.00')
            'Avg Full Backup Time(Sec)' = ($rawdata | Measure-Object -Property 'AverageFullTimeSec' -Average).Average.ToString('0.00')
            'Avg Log Backup Time(Sec)' = ($rawdata | Where-Object {$_.recovery_model_desc -ne 'SIMPLE'} | Measure-Object -Property 'AverageLogTimeSec' -Average).Average.ToString('0.00')
            'Estimated Daily Change Rate (Perc)' = ($EstimatedChangePerc * 100).ToString('0.00')
            'Estimated Daily Change Rate (GB)' = ((($rawdata | Measure-Object -Property DBTotalSizeMB -Sum).Sum)/1024 * $EstimatedChangePerc).ToString('0.00')
            'Avg Log Backup Interval (min)' = ($rawdata | Where-Object {$_.recovery_model_desc -ne "SIMPLE"} | Measure-Object -Property 'AverageLogBackupInterval' -Average).Average.ToString('0.00')
            'DBs with ChangeCapture' = ($rawdata | Measure-Object -Property 'ChangeCapture' -Sum).Sum
            'DBs with ColumnStoreIndex' = ($rawdata | Measure-Object -Property 'ColumnStoreIndex' -Sum).Sum
            'DBs with Compression' = ($rawdata | Measure-Object -Property 'Compression' -Sum).Sum
            'DBs with FILESTREAM' = ($rawdata | Measure-Object -Property 'FILESTREAM' -Sum).Sum
            'DBs with InMemoryOLTP' = ($rawdata | Measure-Object -Property 'InMemoryOLTP' -Sum).Sum
            'DBs with Partitioning' = ($rawdata | Measure-Object -Property 'Partitioning' -Sum).Sum
            'DBs with TransparentDatabaseEncryption' = ($rawdata | Measure-Object -Property 'TransparentDatabaseEncryption' -Sum).Sum
            'DBs with Greater than 300 Files' = ($rawdata | Where-Object {[int]$_.NumberOfFiles -ge 300} | Measure-Object).Count
        }

$MaxDbCountSingleHost = ($rawdata | Group-Object ServerName | Sort-Object Count -Descending| Select-Object Name, Count -first 1)
if($MaxDbCountSingleHost.Count -gt 500){
    $return.Add("Max DB count for a single host [$($MaxDbCountSingleHost.Name)]",$($MaxDbCountSingleHost.Count))
}

$BinStart = 0
foreach($bin in $HistogramBins){
    $BinCount = ($rawdata | Where-Object {[int]$_.DBTotalSizeMB/1024 -gt $BinStart -and [int]$_.DBTotalSizeMB/1024 -le $bin} | Measure-Object).Count
    $return.Add("Histogram (GBs) :$bin",$BinCount)
    $BinStart = $bin
}

$BinCount = ($rawdata | Where-Object {[int]$_.DBTotalSizeMB/1024 -gt $BinStart} | Measure-Object).Count
$return.Add("Histogram:More",$BinCount)

return $return | Format-Table -AutoSize