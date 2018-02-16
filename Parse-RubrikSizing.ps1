param($csvfile
      ,$delimiter = '|'
      ,[int[]]$HistogramBins=@(1000,10000,100000,500000,1000000))

$rawdata = Get-Content $csvfile | ConvertFrom-Csv -Delimiter $delimiter

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
            'Estimated Daily Change Rate (GB)' = ((($rawdata | Measure-Object -Property DBTotalSizeMB -Sum).Sum/1024) * $EstimatedChangePerc).ToString('0.00')
        }

$BinStart = 0
foreach($bin in $HistogramBins){
    $BinCount = ($rawdata | Where-Object {[int]$_.DBTotalSizeMB -gt $BinStart -and [int]$_.DBTotalSizeMB -le $bin} | Measure-Object).Count
    $return.Add("Histogram:$bin",$BinCount)
    $BinStart = $bin
}

$BinCount = ($rawdata | Where-Object {[int]$_.DBTotalSizeMB -gt $BinStart} | Measure-Object).Count
$return.Add("Histogram:More",$BinCount)

return $return