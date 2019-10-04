Get-RubrikVM | Where {$_.configuredSlaDomainName -eq 'Gold'} | % {$_ | Get-RubrikSnapshot | Select-Object -first 1 | ForEach-Object {Write-Host $_.vmName  ","  $_.date}}
