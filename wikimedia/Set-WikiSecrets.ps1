#Requires -Version 5.1
<#
.SYNOPSIS
    Encrypt and store MediaWiki stack secrets using the personal encryption key.
.DESCRIPTION
    Prompts for each sensitive credential, encrypts it with Protect-CmsMessage
    using the personal encryption certificate created by New-WikiKey.ps1, and
    writes the resulting CMS-armoured ciphertext to the wikimedia/secrets/
    directory.

    The secrets/ directory is listed in wikimedia/.gitignore — the files stay
    on disk but are never committed.  Each file is unreadable without the
    matching private key in the Windows certificate store.

    The public certificate (trust/wiki-*-encrypt.cer) determines which private
    key is authorised to decrypt; commit that file to the repository.

.PARAMETER WikiName
    Logical identifier for this wiki instance.  Default: "mywiki"
.PARAMETER Force
    Overwrite existing .cms files.
.EXAMPLE
    .\Set-WikiSecrets.ps1
    .\Set-WikiSecrets.ps1 -WikiName companywiki
    .\Set-WikiSecrets.ps1 -Force          # update all secrets
#>
[CmdletBinding()]
param(
    [string]$WikiName = 'mywiki',
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Locate the encryption certificate
# ---------------------------------------------------------------------------
$subject = "CN=wiki-$WikiName,O=Docker-Wikimedia"
$cert    = Get-ChildItem Cert:\CurrentUser\My |
    Where-Object { $_.Subject -eq $subject -and $_.NotAfter -gt (Get-Date) } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1

if (-not $cert) {
    Write-Error (
        "No active encryption certificate found for '$WikiName'.`n" +
        "Run .\New-WikiKey.ps1 -WikiName $WikiName first."
    )
}

Write-Host ''
Write-Host "Using certificate $($cert.Thumbprint)  (expires $($cert.NotAfter.ToString('yyyy-MM-dd')))"

# ---------------------------------------------------------------------------
# Ensure the secrets directory exists (gitignored)
# ---------------------------------------------------------------------------
$secretsDir = Join-Path $PSScriptRoot 'secrets'
if (-not (Test-Path $secretsDir)) {
    New-Item -ItemType Directory -Path $secretsDir | Out-Null
}

function Set-EncryptedSecret {
    param(
        [string]$Key,
        [string]$Prompt
    )

    $outPath = Join-Path $secretsDir "$Key.cms"

    if ((Test-Path $outPath) -and -not $Force) {
        Write-Host "  $Key : already encrypted  (use -Force to replace)" -ForegroundColor DarkGray
        return
    }

    $secure = Read-Host -Prompt "  $Prompt" -AsSecureString
    $plain  = [System.Net.NetworkCredential]::new('', $secure).Password

    if ([string]::IsNullOrEmpty($plain)) {
        Write-Warning "  Skipping $Key — no value entered."
        $plain = $null
        return
    }

    Protect-CmsMessage -Content $plain -To $cert -OutFile $outPath
    $plain = $null   # clear plaintext from memory as soon as possible

    Write-Host "  $Key → $(Split-Path $outPath -Leaf)  [encrypted]" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Encrypt the three sensitive secrets
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host "Encrypting secrets for wiki '$WikiName'" -ForegroundColor Cyan
Write-Host "Tip: generate values with:"
Write-Host "     openssl rand -base64 24   # DB_PASSWORD"
Write-Host "     openssl rand -hex 32      # MW_SECRET_KEY"
Write-Host "     openssl rand -hex 8       # MW_UPGRADE_KEY"
Write-Host ''

Set-EncryptedSecret 'DB_PASSWORD'    'Database password (strong random string)'
Set-EncryptedSecret 'MW_SECRET_KEY'  'MediaWiki secret key   (64-char hex)'
Set-EncryptedSecret 'MW_UPGRADE_KEY' 'MediaWiki upgrade key  (16-char hex)'

Write-Host ''
Write-Host 'Secrets encrypted.  Run .\Start-Wiki.ps1 to start the stack.' -ForegroundColor Cyan
