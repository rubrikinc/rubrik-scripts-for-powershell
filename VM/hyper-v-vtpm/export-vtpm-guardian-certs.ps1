$GuardianName = 'UntrustedGuardian'
$CertificatePassword = Read-Host -Prompt 'Please enter a password to secure the certificate files' -AsSecureString

$guardian = Get-HgsGuardian -Name $GuardianName

if (-not $guardian)
{
    throw "Guardian '$GuardianName' could not be found on the local system."
}

$encryptionCertificate = Get-Item -Path "Cert:\LocalMachine\Shielded VM Local Certificates\$($guardian.EncryptionCertificate.Thumbprint)"
$signingCertificate = Get-Item -Path "Cert:\LocalMachine\Shielded VM Local Certificates\$($guardian.SigningCertificate.Thumbprint)"

if (-not ($encryptionCertificate.HasPrivateKey -and $signingCertificate.HasPrivateKey))
{
    throw 'One or both of the certificates in the guardian do not have private keys. ' + `
          'Please ensure the private keys are available on the local system for this guardian.'
}

Export-PfxCertificate -Cert $encryptionCertificate -FilePath ".\$GuardianName-encryption.pfx" -Password $CertificatePassword
Export-PfxCertificate -Cert $signingCertificate -FilePath ".\$GuardianName-signing.pfx" -Password $CertificatePassword