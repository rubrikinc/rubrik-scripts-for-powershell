<#
.SYNOPSIS
Format the result of an iPerf JSON results file.

.DESCRIPTION
The Parse-iPerfResults.ps1 script formats the results of an iPerf results file.
With iPerf you can output the results to JSON using the "-J" flag.
Output all results with "-J" to a concatenated file.

This script will pull each of the discrete results into a JSON array,
and then output relevant fields to a CSV file.

.NOTES
Written by Steven Tong for community usage
GitHub: stevenctong
Date: 10/15/21

.EXAMPLE
./Parse-iPerfResults.ps1 -file <input_filename.json>
Takes <filename> as the input and outputs it to a file with the same name but as .csv.

.EXAMPLE
./Parse-iPerfResults.ps1 -file <input_filename.json> -output <CSV_output_filename.csv>
Takes <filename> as the input and outputs it to <output> filename.
#>

param (
  [CmdletBinding()]

  # Input filename of iPerf results in a JSON array
  [Parameter(Mandatory=$true)]
  [string]$file = '',

  # Output filename of the formatted iPerf results as a CSV file
  [Parameter(Mandatory=$false)]
  [string]$output = ''
)

# CreateJSONArray - Takes in JSON file with a bunch of separate JSON objects
# Combines the separate objects and returns and array of JSON objects
Function CreateJSONArray($jsonFile) {
  $jsonCount = 0
  $textObject = ""
  $jsonArray = @()

  [System.IO.File]::ReadLines($jsonFile) | ForEach-Object {
    if ($_ -match '{') {
      $jsonCount += 1
    }

    if ($_ -match '}') {
      $jsonCount -= 1
    }

    if ($jsonCount -gt 0)
    {
      $textObject += $_
    } else {
      $textObject += $_
      $jsonArray += $textObject | ConvertFrom-Json
      $textObject = ""
    }
  }
  return $jsonArray
} # FUNCTION - CreateJSONArray($jsonFile)


# Pass in the iPerf results file and put each JSON object into an array for processing
$jsonArray = CreateJSONArray $file

# If the file is already an array of JSON objects you can use the following
# $jsonArray = Get-Content -Path $file | ConvertFrom-Json

$resultList = @()

foreach ($test in $jsonArray)
{
  # If iPerf was run with the -r (reverse) flag, swap source & target
  if ($test.start.test_start.reverse -eq 1) {
    $source = $test.start.connected[0].remote_host
    $target = $test.start.connected[0].local_host
    $note = "Source/Target swapped"
  } else {
    $source = $test.start.connected[0].local_host
    $target = $test.start.connected[0].remote_host
    $note = ""
  }

  $gbps = [math]::round($test.end.sum_sent.bits_per_second / 1000/1000/1000, 2)

  $timesecs = $test.start.timestamp.timesecs
  $localTime = [DateTime]$test.start.timestamp.time
  $localTZ = Get-TimeZone | Select -ExpandProperty DisplayName

  $result = [PSCustomObject] @{
    "Source" = $source
    "Target" = $target
    "Gbps" = $gbps
    "num_streams" = $test.start.test_start.num_streams
    "blksize" = $test.start.test_start.blksize
    "duration_secs" = $test.start.test_start.duration
    "reverse" = $test.start.test_start.reverse
    "tcp_mss_default" = $test.start.tcp_mss_default
    "sum_sent_bytes" = $test.end.sum_sent.bytes
    "sum_sent_bps" = $test.end.sum_sent.bits_per_second
    "sum_sent_retransmits" = $test.end.sum_sent.retransmits
    "host_cpu_total" = $test.end.cpu_utilization_percent.host_total
    "remote_cpu_total" = $test.end.cpu_utilization_percent.remote_total
    "note" = $note
    "time_local" = $localTime
    "time_local_zone" = $localTZ
    "time_utc" = $test.start.timestamp.time
  }

  $resultList += $result
}

# If no output filename is given, use the input filename as the base output filename
if ($output -eq '')
{
  $resultList | Export-CSV -Path "$(Split-Path $file -Leafbase).csv"
} else {
  $resultList | Export-CSV -Path $output
}
