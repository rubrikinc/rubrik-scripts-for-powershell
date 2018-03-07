<#
    .SYNOPSIS
        Script to parse the SQL Errorlog for VDI backup operations

    .DESCRIPTION
        Script to parse the SQL Errorlog for VDI backup operations. It will scan all of the errorlogs for instances of 
        'I/O is frozen' - Means the start of the VDI backup
        'I/O was resumed' - Means the end of the VDI backup


    .PARAMETER ServerInstance
        SQL Server Instance name. If default instance, then just use the server name, if a named instance, use either 
        Server\Instance or Server, port    

    .PARAMETER OutputFile
        Path and file name to CSV that will contain the data collected from the Errorlog

    .INPUTS
        None

    .OUTPUTS
        CSV file 

    .EXAMPLE
        Example of how to run the script

    .LINK
        None

    .NOTES
        Name:       Parse SQL Errorlog for VSS Backups   
        Created:    1/22/2018
        Author:     Chris Lumnah
#>
param (
        [Parameter(Mandatory=$true,Position=0)]
        #SQL Server Instance name. If default instance, then just use the server name, if a named instance, use either 
        #Server\Instance or Server, port                    
        [string]
        $ServerInstance,
        [Parameter(Mandatory=$true,Position=1)]
        [AllowEmptyString()]
        [string]
        $OutputFile
    )

#Requires -Version 4.0
#Requires -Modules SQLServer

Import-Module SQLServer


if (!$OutputFile){$OutputFile = [environment]::getfolderpath("mydocuments") + "\" + $ServerInstance + "_BackupTimings.csv"}
$OutputFile

#Use the first line for testing to limit the amount of data back. Use the second line to gather all of the data from the Errorlog
#$SQLErrorLog = Get-SqlErrorLog -ServerInstance $ServerInstance  -Since Yesterday -Ascending  | Where-Object { $_.Text -match 'I/O is frozen' -or $_.Text -match 'I/O was resumed' } 
$SQLErrorLog = Get-SqlErrorLog -ServerInstance $ServerInstance -Since LastWeek -Ascending  | Where-Object { $_.Text -match 'I/O is frozen' -or $_.Text -match 'I/O was resumed' }  

$Output = @()

foreach ($Entry in $SQLErrorLog)
{
    $DatabaseName = ($Entry.Text.split(" "))[5]
    $DatabaseName = $DatabaseName.replace('.','')

    #Need dates to include milliseconds
    If ( $Entry.Text -match 'I/O is frozen' ) 
    {
        $BackupStartDate = $Entry.Date.ToString("MM/dd/yyyy hh:mm:ss.fff") 
        $OutputRecord = New-Object PSObject
        $OutputRecord | Add-Member -type NoteProperty -Name "Database" -Value $DatabaseName
        $OutputRecord | Add-Member -type NoteProperty -Name "Time" -Value $BackupStartDate
        $OutputRecord | Add-Member -type NoteProperty -Name "Start-End" -Value "Start"
    }
    
    If ( $Entry.Text -match 'I/O was resumed' ) 
    {
        $BackupEndDate = $Entry.Date.ToString("MM/dd/yyyy hh:mm:ss.fff")
        $OutputRecord = New-Object PSObject
        $OutputRecord | Add-Member -type NoteProperty -Name "Database" -Value $DatabaseName
        $OutputRecord | Add-Member -type NoteProperty -Name "Time" -Value $BackupEndDate
        $OutputRecord | Add-Member -type NoteProperty -Name "Start-End" -Value "End"
    }

   $Output += $OutputRecord
}

Write-Host "Data written to $OutputFile"

$Output | Export-csv -Path $OutputFile
