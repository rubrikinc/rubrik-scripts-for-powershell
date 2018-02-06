$Credential = Get-Credential

$Credential.Password | ConvertFrom-SecureString | Out-File "$($Credential.UserName).txt" -Force