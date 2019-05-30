<#
.SYNOPSIS Prompts for credentials securely and stores the credentials in an encrypted file, Rubrik.cred
#>
$Credential = Get-Credential
$Credential | Export-CliXml -Path .\rubrik.Cred