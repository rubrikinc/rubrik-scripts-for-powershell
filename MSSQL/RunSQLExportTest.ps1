$TestDBs = @('TPCH_2F100G','TPCH_3F100G','TPCH_4F100G','TPCH_5F100G','TPCH_6F100G')
$cred = Get-Credential
Import-Module Rubrik,SqlServer
'"DBName","StartTime","EndTime"'| Out-File C:\Temp\ExportTestLog.csv

foreach($DBName in $TestDBs){

for($i=1;$i -le 2; $i++){
    $suffix = "TEST$i"
    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starting $DBName-$suffix..."
    $data = Invoke-Sqlcmd -ServerInstance poc-sql01.rangers.lab -Database $DBName 'SELECT name,physical_name FROM sys.database_files' -Username pester -Password 'uni++est'
    Connect-Rubrik -Server 172.21.8.51 -Credential $cred | Out-Null
    $db = Get-RubrikDatabase -Hostname poc-sql01.rangers.lab -Instance mssqlserver -Name $DBName | Where-Object {$_.isRelic -ne 'True'}
    $snap = Get-RubrikSnapshot -id $db.id -Date (Get-Date)
    $files = @()
    $data | ForEach-Object {$files += @{logicalName=$_.name;exportPath=($_.physical_name | Split-Path).Replace($DBName,"$DBName-$suffix")}}
    $target = (Get-RubrikDatabase -Hostname poc-sql02.rangers.lab -Instance MSSQLSERVER).instanceid[0]

    $req = $db | Export-RubrikDatabase -TargetInstanceId $target -TargetDatabaseName "$DBName-$suffix" -TargetFilePaths $files `
                                 -MaxDataStreams 8 -RecoveryDateTime (Get-Date $snap.date) -FinishRecovery -Confirm:$false
    do{
        Start-Sleep -Seconds 60
        $req = $req | Get-RubrikRequest -Type mssql
    }until($req.status -eq 'SUCCEEDED')

    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')]$DBName-$suffix Export Complete."
    $req | Get-RubrikRequest -Type mssql | 
        Select-Object @{n='DBName';e={$DBName}},@{n='Start';e={Get-date $_.startTime -Format 'yyyy-MM-dd HH:mm:ss'}},@{n='End';e={Get-date $_.endTime -Format 'yyyy-MM-dd HH:mm:ss'}} |
        ConvertTo-Csv | Select-Object -Skip 1 | Out-File C:\Temp\ExportTestLog.csv -Append

    Invoke-Sqlcmd -ServerInstance 'poc-sql02.rangers.lab' -Database 'tempdb' -Query "IF DB_ID('$DBName-$suffix') IS NOT NULL DROP DATABASE [$DBName-$suffix];" -Username pester -Password 'uni++est'
    }
}