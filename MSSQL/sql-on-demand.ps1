# This will create on-demand backups for all databases on the host/instance defined

Get-RubrikDatabase -Host 'hostname in rubrik' -Instance 'MSSQLSERVER' | New-RubrikSnapshot
