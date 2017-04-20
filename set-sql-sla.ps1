# This will set unprotected databases to the defined SLA

Get-RubrikDatabase | Where {$_.effectiveSlaDomainId -eq 'UNPROTECTED'} | Protect-RubrikDatabase -SLA Bronze -WhatIf

Get-RubrikDatabase | Where {$_.effectiveSlaDomainId -eq 'UNPROTECTED'} | Protect-RubrikDatabase -SLA Bronze -confirm:$false

Get-RubrikDatabase | Where {$_.effectiveSlaDomainId -eq 'UNPROTECTED'} | Protect-RubrikDatabase -SLA Bronze -confirm:$false
