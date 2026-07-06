#Requires -Version 5.1
<#
.SYNOPSIS
    Store MediaWiki stack secrets in Windows Credential Manager.
.DESCRIPTION
    Prompts for each sensitive credential (database password, MediaWiki secret
    key and upgrade key) and saves them to the Windows Credential Manager
    PasswordVault using the WinRT API.  Secrets are DPAPI-encrypted and are
    only accessible to the current Windows user on this machine — they are
    never written to disk as plaintext.

    Run once to initialise, or again (with -Force) to update values.

    Non-sensitive configuration (WIKI_NAME, DB_NAME, DB_USER, MW_SITE_SERVER,
    DEV_PORT) is stored in the normal .env file; see .env.example.

.PARAMETER WikiName
    Logical name for the wiki instance.  Must match the WIKI_NAME you use in
    .env and when calling start.ps1.  Default: "mywiki"
.PARAMETER Force
    Overwrite credentials that already exist in the vault.
.EXAMPLE
    .\setup-secrets.ps1
    .\setup-secrets.ps1 -WikiName companywiki
    .\setup-secrets.ps1 -Force          # update all secrets
#>
[CmdletBinding()]
param(
    [string]$WikiName = 'mywiki',
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Load the PasswordVault WinRT type (available in PowerShell 5.1+ on Windows)
# ---------------------------------------------------------------------------
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.Security.Credentials.PasswordVault,
             Windows.Security.Credentials,
             ContentType=WindowsRuntime]
} catch {
    Write-Error 'Windows Credential Manager (PasswordVault) is not available on this system.'
}

$vault    = [Windows.Security.Credentials.PasswordVault]::new()
$resource = "docker-wikimedia-$WikiName"

function Set-VaultSecret {
    param(
        [string]$Key,
        [string]$Prompt
    )

    # Check whether the credential already exists
    $existing = $null
    try { $existing = $vault.Retrieve($resource, $Key) } catch {}

    if ($existing -and -not $Force) {
        Write-Host "  $Key : already stored  (use -Force to overwrite)" -ForegroundColor DarkGray
        return
    }

    $secure = Read-Host -Prompt "  $Prompt" -AsSecureString
    $plain  = [System.Net.NetworkCredential]::new('', $secure).Password

    if ([string]::IsNullOrEmpty($plain)) {
        Write-Warning "  Skipping $Key — no value entered."
        return
    }

    $cred = [Windows.Security.Credentials.PasswordCredential]::new(
        $resource, $Key, $plain)
    if ($existing) { $vault.Remove($existing) }
    $vault.Add($cred)
    Write-Host "  $Key stored." -ForegroundColor Green
}

Write-Host ""
Write-Host "Storing MediaWiki secrets for wiki '$WikiName'" -ForegroundColor Cyan
Write-Host "Vault resource : $resource"                    -ForegroundColor DarkGray
Write-Host "Tip: generate passwords with  openssl rand -base64 24"
Write-Host "     generate hex keys with   openssl rand -hex 32"
Write-Host ""

Set-VaultSecret -Key 'DB_PASSWORD'    `
    -Prompt 'Database password (strong random string)'

Set-VaultSecret -Key 'MW_SECRET_KEY'  `
    -Prompt 'MediaWiki secret key   (64-char hex; openssl rand -hex 32)'

Set-VaultSecret -Key 'MW_UPGRADE_KEY' `
    -Prompt 'MediaWiki upgrade key  (16-char hex; openssl rand -hex 8)'

Write-Host ""
Write-Host "Done.  Run .\start.ps1 to start the stack." -ForegroundColor Cyan
