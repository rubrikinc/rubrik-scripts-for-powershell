# This will create on-demand backups for all databases on the host/instance defined

Get-RubrikDatabase -Host 'devops-sql-2k12' -Instance 'MSSQLSERVER' | New-RubrikSnapshot
