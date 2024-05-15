<#
.SYNOPSIS
    Run iperf tests from a Windows Host to nodes in a Rubrik Cluster
.DESCRIPTION
    Run iperf tests from a Windows Host to nodes in a Rubrik Cluster
.EXAMPLE
    PS C:\> .\Run-iPerfTest.ps1 -RubrikServer 10.8.49.101 `
        -iperfVersion 2 `
        -iperfPath c:\iperf-2.0.9-win64
    The above command will run an iperf test from the windows host to a rubrik cluster using iperf v2
    
.EXAMPLE
    PS C:\> .\Run-iPerfTest.ps1 -RubrikServer 10.8.49.101 `
        -iperfVersion 2 
    The above command will run an iperf test from the windows host to a rubrik cluster using iperf v3

.INPUTS
    None except for parameters
.OUTPUTS
    None
.NOTES
    Name:               Iperf Baseline Script
    Created:            2/10/2021
    Author:             Chris Lumnah
            
    This script will run 3 iperf tests from the windows host to each node in the Rubrik Cluster. Each test will be for 1 minute. An 8 node brik, will require 25 minutes to complete the test. You do need to download iperf for this script to work. 
    This script is just a wrapper around the iperf.exe program to do the tests. Each test will be written to a text file into the location you are in at runtime. This script should be placed into the same folder as where you have iperf installed for ease of use. 
   
#>
#Requires -Module Rubrik
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$RubrikServer,

    [Parameter(Mandatory)]
    [ValidateSet(2,3)]
    [string]$iperfVersion,
    
    [Parameter()]
    [string]$iperfPath = ".\"

)
#region Make sure iperf is installed
switch ($iperfVersion){
    2 {$iperfExists = (Test-Path -Path '.\iperf.exe')}
    3 {$iperfExists = (Test-Path -Path '.\iperf3.exe')}
}
if ($iperfExists -eq $false){
    Write-Error -Message "iperf.exe was not found. Before you can run this script, download iperf from https://iperf.fr/ and then place this script into the same folder you placed the iperf program."
    exit
}
#endregion

#region Get the list of nodes from the Rubrik Cluster
Connect-Rubrik -Server $RubrikServer -id "client|de50a555-a272-4725-a861-aab52bfdfd41" -Secret "3-j3NjAkCRok5PF5Q_K9U9-kGb3VZpWiEN-aEBMjcnXEfnGvou9atgpM-vsvtK0k"
$RubrikNodes = (Invoke-RubrikRESTCall -Endpoint 'cluster/me/node' -Method GET -api 'internal').data
#endregion

#region Run iperf tests against each node in the Rubrik Cluster
$HostName = $env:COMPUTERNAME
foreach($RubrikNode in $RubrikNodes){
    switch ($iperfVersion){
        2 {
            Write-Host "Running .\iperf.exe -c $($RubrikNode.ipAddress) -i 5 -t 60"
            .\iperf.exe -c $($RubrikNode.ipAddress) -i 5 -t 60 > "iperf_$($HostName)_to_$($RubrikNode.ipAddress)_64K_1_Thread.txt"

            Write-Host "Running .\iperf.exe -c $($RubrikNode.ipAddress) -i 5 -t 60 -w 1M"
            .\iperf.exe -c $RubrikNode.ipAddress -i 5 -t 60 -w 1M > "iperf_$($HostName)_to_$($RubrikNode.ipAddress)_1MB_1_Thread.txt"

            Write-Host "Running .\iperf.exe -c $($RubrikNode.ipAddress) -i 5 -t 60 -w 1M -P 8"
            .\iperf.exe -c $RubrikNode.ipAddress -i 5 -t 60 -w 1M -P 8 > "iperf_$($HostName)_to_$($RubrikNode.ipAddress)_1MB_8_Threads.txt"
        }
        3 {
            Write-Host "Running .\iperf3.exe -c $($RubrikNode.ipAddress) -i 5 -t 60"
            .\iperf3.exe -c $($RubrikNode.ipAddress) -i 5 -t 60 --json > "iperf_$($HostName)_to_$($RubrikNode.ipAddress)_64K_1_Thread.json"

            Write-Host "Running .\iperf3.exe -c $($RubrikNode.ipAddress) -i 5 -t 60 -w 1M"
            .\iperf3.exe -c $RubrikNode.ipAddress -i 5 -t 60 -w 1M --json > "iperf_$($HostName)_to_$($RubrikNode.ipAddress)_1MB_1_Thread.json"

            Write-Host "Running .\iperf3.exe -c $($RubrikNode.ipAddress) -i 5 -t 60 -w 1M -P 8 "
            .\iperf3.exe -c $RubrikNode.ipAddress -i 5 -t 60 -w 1M -P 8 --json > "iperf_$($HostName)_to_$($RubrikNode.ipAddress)_1MB_8_Threads.json"
        }
    }
}
#endregion