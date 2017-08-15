# On Demand Backup of Databases from within -file [FILE.CSV]
# .csv format
# hostname, instance, dbname
# db1, MSSQLServer, mydatabase

# Usage - ./snap-db-csv.ps1 -file [csvname]

param (
  [string]$file= "input.csv"
)

Import-Csv $file | foreach-object {Get-RubrikDatabase -Hostname $_.hostname -Instance $_.instance -Name $_.dbname | New-RubrikSnapshot -Inherit -confirm:$false}
