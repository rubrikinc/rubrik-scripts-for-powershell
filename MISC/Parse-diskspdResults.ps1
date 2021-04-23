[CmdletBinding()]
param (
    [Parameter()]
    [String]$Path = ".\"
)


$ResultFiles = Get-ChildItem -Path $Path -Filter *.rbk

foreach ($ResultFile in $ResultFiles){
    #Export test results as .csv
    [xml]$xDoc = Get-Content $ResultFile
    #$CSVFile = $OutFile -replace ".rbk", ".csv"
    $csvfile = ".\Diskspd_Results.csv"
    $timespans = $xDoc.Results.timespan
    
    $n = 0
    $resultobj = @()
    $cols_sum = @('BytesCount','IOCount','ReadBytes','ReadCount','WriteBytes','WriteCount')
    $cols_avg = @('AverageReadLatencyMilliseconds','ReadLatencyStdev','AverageWriteLatencyMilliseconds','WriteLatencyStdev','AverageLatencyMilliseconds','LatencyStdev')
    $cols_ntile = @('0','25','50','75','90','95','99','99.9','99.99'.'99.999','99.9999','99.99999'.'99.999999','100')
    
    foreach($Timespan in $Timespans){
        $threads = $Timespan.Thread.Target
        $buckets = $ts.Latency.Bucket

        #create custom PSObject for output
        $outset = New-Object -TypeName PSObject
        
        $outset | Add-Member -MemberType NoteProperty -Name 'ComputerName' -Value $xDoc.Results.System.ComputerName
        $outset | Add-Member -MemberType NoteProperty -Name 'Test Run Time' -Value $xDoc.Results.System.RunTime
        $outset | Add-Member -MemberType NoteProperty -Name 'TestPath' -Value $xDoc.Results.Profile.TimeSpans.TimeSpan.Targets.Target.Path
        $outset | Add-Member -MemberType NoteProperty -Name 'Blocksize' -Value $xDoc.Results.Profile.TimeSpans.TimeSpan.Targets.Target.BlockSize
        $outset | Add-Member -MemberType NoteProperty -Name 'IO Depth' -Value $xDoc.Results.Profile.TimeSpans.TimeSpan.Targets.Target.RequestCount
        $outset | Add-Member -MemberType NoteProperty -Name 'Write Ratio' -Value $xDoc.Results.Profile.TimeSpans.TimeSpan.Targets.Target.WriteRatio
        
        $outset | Add-Member -MemberType NoteProperty -Name 'File Size' -Value $xDoc.Results.Profile.TimeSpans.TimeSpan.Targets.Target.FileSize
        $outset | Add-Member -MemberType NoteProperty -Name 'Duration [s]' -Value $xDoc.Results.Profile.TimeSpans.TimeSpan.Duration


        $outset | Add-Member -MemberType NoteProperty -Name 'Error' -Value $xDoc.Results.TimeSpan.Error

        #loop through nodes that will be summed across threads
        foreach($col in $cols_sum){
            $outset | Add-Member -MemberType NoteProperty -Name $col -Value ($threads | Measure-Object $col -Sum).Sum
        }

        #generate MB/s and IOP values
        $outset | Add-Member -MemberType NoteProperty -Name MBps -Value (($outset.BytesCount / 1048576) / $outset.'Duration [s]' )
        $outset | Add-Member -MemberType NoteProperty -Name IOps -Value ($outset.IOCount / $outset.'Duration [s]')
        $outset | Add-Member -MemberType NoteProperty -Name ReadMBps -Value (($outset.ReadBytes / 1048576) / $outset.'Duration [s]')
        $outset | Add-Member -MemberType NoteProperty -Name ReadIOps -Value ($outset.ReadCount / $outset.'Duration [s]')
        $outset | Add-Member -MemberType NoteProperty -Name WriteMBps -Value (($outset.WriteBytes / 1048576) / $outset.'Duration [s]')
        $outset | Add-Member -MemberType NoteProperty -Name WriteIOps -Value ($outset.WriteCount / $outset.'Duration [s]')

        #loop through nodes that will be averaged across threads
        foreach($col in $cols_avg){
            if([bool]($threads.PSobject.Properties.name -match "SelectNodes")){
                if($threads.SelectNodes($col)){
                    $outset | Add-Member -MemberType NoteProperty -Name $col -Value ($threads |Measure-Object $col -Average).Average
                } else {
                    $outset | Add-Member -MemberType NoteProperty -Name $col -Value ""
                }
            }
        }
        
        #loop through ntile buckets and extract values for the declared ntiles
        foreach($bucket in $buckets){
            if($cols_ntile -contains $bucket.Percentile){
                if($bucket.SelectNodes('ReadMilliseconds')){
                    $outset | Add-Member -MemberType NoteProperty -Name ("ReadMS_"+$bucket.Percentile) -Value $bucket.ReadMilliseconds
                }
                else{
                    $outset | Add-Member -MemberType NoteProperty -Name ("ReadMS_"+$bucket.Percentile) -Value ""
                }

                if($bucket.SelectNodes('WriteMilliseconds')){
                    $outset | Add-Member -MemberType NoteProperty -Name ("WriteMS_"+$bucket.Percentile) -Value $bucket.WriteMilliseconds
                }
                else{
                    $outset | Add-Member -MemberType NoteProperty -Name ("WriteMS_"+$bucket.Percentile) -Value ""
                }

                $outset | Add-Member -MemberType NoteProperty -Name ("TotalMS_"+$bucket.Percentile) -Value $bucket.TotalMilliseconds
            }
        }

        #Add some CPU Avg's to CSV file for analysis
        $outset | Add-Member -MemberType NoteProperty -Name AvgUsagePercent -Value $xDoc.Results.TimeSpan.CpuUtilization.Average.UsagePercent
        $outset | Add-Member -MemberType NoteProperty -Name AvgUserPercent -Value $xDoc.Results.TimeSpan.CpuUtilization.Average.UserPercent
        $outset | Add-Member -MemberType NoteProperty -Name AvgKernelPercent -Value $xDoc.Results.TimeSpan.CpuUtilization.Average.KernelPercent
        $outset | Add-Member -MemberType NoteProperty -Name AvgIdlePercent -Value $xDoc.Results.TimeSpan.CpuUtilization.Average.IdlePercent

        $resultobj += $outset
        $n++
    }
    $resultobj | Select-Object -Property ComputerName, 'Test Run Time', TestPath, BlockSize, 'IO Depth', 'Write Ratio', ReadMBps, WriteMBps, `
        ReadIOps, WriteIOps, AvgUsagePercent, AvgUserPercent, AvgKernelPercent, AvgIdlePercent, 'Duration [s]',	'File Size', 'Error', `
        BytesCount, IOCount, ReadBytes, ReadCount, WriteBytes, WriteCount, MBps, IOps `
        | Export-Csv -Path $csvfile -NoTypeInformation -Append
}
