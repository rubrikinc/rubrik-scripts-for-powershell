$csv = Import-Csv $args[0] -Header @("VM","SLA")

foreach ($l in $csv) {
   Get-RubrikVM -Name $l.VM | Protect-RubrikVM -SLA $l.SLA
}
