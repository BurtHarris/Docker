#Requires -Version 5.1
<#
.SYNOPSIS
    Generate a personal encryption key for the MediaWiki Docker stack.
.DESCRIPTION
    Creates a self-signed RSA certificate in the current user's personal
    certificate store (Cert:\CurrentUser\My) and exports the PUBLIC half
    to the wikimedia/trust/ directory as a .cer file.

    The private key is protected by Windows DPAPI / TPM and never leaves
    the machine.  The .cer trust marker is safe to commit to the repository:
    it lets anyone ENCRYPT new secrets for this wiki, but only the private-
    key holder can DECRYPT them.

    To encrypt and store secrets after this step run Set-WikiSecrets.ps1.
    To migrate to a new machine run this script there, then re-run
    Set-WikiSecrets.ps1 (old .cms files will be unreadable on the new key).

.PARAMETER WikiName
    Logical identifier for this wiki instance.  Used as the certificate
    subject and as a file-name component.  Default: "mywiki"
.PARAMETER KeyBits
    RSA key size in bits.  3072 provides ~128-bit security headroom.
    Default: 3072
.PARAMETER ValidYears
    Certificate validity in years.  Default: 10
.PARAMETER Force
    Replace an existing certificate.  Old .cms secret files become
    unreadable; re-run Set-WikiSecrets.ps1 afterwards.
.EXAMPLE
    .\New-WikiKey.ps1
    .\New-WikiKey.ps1 -WikiName companywiki -KeyBits 4096
    .\New-WikiKey.ps1 -Force
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$WikiName   = 'mywiki',
    [int]   $KeyBits    = 3072,
    [int]   $ValidYears = 10,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$subject = "CN=wiki-$WikiName,O=Docker-Wikimedia"

# ---------------------------------------------------------------------------
# Guard against accidental replacement
# ---------------------------------------------------------------------------
$existing = Get-ChildItem Cert:\CurrentUser\My |
    Where-Object { $_.Subject -eq $subject -and $_.NotAfter -gt (Get-Date) } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1

if ($existing -and -not $Force) {
    Write-Host ''
    Write-Host "An active encryption certificate already exists for '$WikiName':" -ForegroundColor Yellow
    Write-Host "  Thumbprint : $($existing.Thumbprint)"
    Write-Host "  Expires    : $($existing.NotAfter.ToString('yyyy-MM-dd'))"
    Write-Host ''
    Write-Host 'Use -Force to replace it.  Existing .cms secret files will' -ForegroundColor Yellow
    Write-Host 'become unreadable — re-run Set-WikiSecrets.ps1 afterwards.' -ForegroundColor Yellow
    return
}

# ---------------------------------------------------------------------------
# Create the Document Encryption certificate
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host "Generating RSA-$KeyBits Document Encryption certificate ..." -ForegroundColor Cyan
Write-Host "  Subject : $subject"

if (-not $PSCmdlet.ShouldProcess($subject, 'New-SelfSignedCertificate')) { return }

$cert = New-SelfSignedCertificate `
    -Subject             $subject `
    -Type                DocumentEncryptionCert `
    -KeyAlgorithm        RSA `
    -KeyLength           $KeyBits `
    -KeyExportPolicy     NonExportable `
    -CertStoreLocation   'Cert:\CurrentUser\My' `
    -NotAfter            (Get-Date).AddYears($ValidYears) `
    -FriendlyName        "MediaWiki Docker encryption key — $WikiName"

Write-Host ''
Write-Host "Certificate created:" -ForegroundColor Green
Write-Host "  Thumbprint : $($cert.Thumbprint)"
Write-Host "  Expires    : $($cert.NotAfter.ToString('yyyy-MM-dd'))"

# ---------------------------------------------------------------------------
# Export the PUBLIC certificate (trust marker) — safe to commit
# ---------------------------------------------------------------------------
$trustDir = Join-Path $PSScriptRoot 'trust'
if (-not (Test-Path $trustDir)) {
    New-Item -ItemType Directory -Path $trustDir | Out-Null
}

$cerPath = Join-Path $trustDir "wiki-$WikiName-encrypt.cer"
Export-Certificate -Cert $cert -FilePath $cerPath -Type CERT | Out-Null

Write-Host ''
Write-Host "Trust marker exported (safe to commit to the repository):" -ForegroundColor Green
Write-Host "  $cerPath"
Write-Host ''
Write-Host 'Next step: run .\Set-WikiSecrets.ps1 to encrypt and store secrets.' -ForegroundColor Cyan
