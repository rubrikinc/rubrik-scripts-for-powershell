# Restore Latest Snapshot of Databases from within -file [FILE.CSV]
# .csv format
# hostname, instance, dbname
# db1, MSSQLServer, mydatabase

# Usage - ./restore-db-csv.ps1 [-file input.csv]

param (
  [string]$file="input.csv"
)

Import-Csv $file | foreach-object {
  $out = Get-RubrikDatabase -id ((Get-RubrikDatabase -Hostname $_.hostname -Instance $_.instance -Name $_.dbname).id)
  Restore-RubrikDatabase -id $out.id -RecoveryDateTime (Get-Date ($out.latestRecoveryPoint))
}
