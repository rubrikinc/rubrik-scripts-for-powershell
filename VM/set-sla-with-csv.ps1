$csv = Import-Csv $args[0] -Header @("VM","SLA")

foreach ($l in $csv) {
   $out = Get-RubrikVM -Name $l.VM -verbose:$false | Protect-RubrikVM -SLA $l.SLA  -verbose:$false -confirm:$false  # Optionally add -WhatIf for dry-run, or -confirm:$false to bypass confirmation questions
}
