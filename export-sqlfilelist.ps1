#Requires -Modules Rubrik
#Parameterized Script Values 
param([string]$SQLHost
      ,[string]$SQLInstance
      ,[string]$DBName
      ,[string]$OutPath = 'C:\temp')

$OutFile = Join-Path -Path $OutPath -ChildPath "$DBName-files.csv"
#create a .csv listing all db logical files

$db = Get-RubrikDatabase -Hostname $SQLHost -Instance $SQLInstance -Database $DBName | Get-RubrikDatabase
Get-RubrikDatabaseFiles -id $db.id -time $db.latestRecoveryPoint |
    Sort-Object fileid |
    Select-Object LogicalName,@{n='exportPath';e={$_.OriginalPath}},@{n='newFileName';e={$_.OriginalName}} | 
    ConvertTo-Csv -NoTypeInformation | 
    Out-File $OutFile

"Files written to $OutFile" | Out-Host