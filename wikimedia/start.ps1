#Requires -Version 5.1
<#
.SYNOPSIS
    Load MediaWiki secrets from Windows Credential Manager and start the stack.
.DESCRIPTION
    Retrieves the three sensitive credentials (DB_PASSWORD, MW_SECRET_KEY,
    MW_UPGRADE_KEY) that were stored by setup-secrets.ps1, injects them as
    process-scoped environment variables, then calls docker compose.

    Secrets exist only in the current process — they are never written to disk.
    Non-sensitive configuration (WIKI_NAME, DB_NAME, etc.) is read from .env
    as usual; see .env.example.

.PARAMETER WikiName
    Logical name of the wiki instance.  Must match the name used with
    setup-secrets.ps1.  Default: "mywiki"
.PARAMETER ComposeArgs
    Arguments forwarded to docker compose.  Default: "up -d"
.PARAMETER Down
    Convenience flag — equivalent to -ComposeArgs "down"
.EXAMPLE
    .\start.ps1
    .\start.ps1 -ComposeArgs "up -d --build"
    .\start.ps1 -Down
    .\start.ps1 -WikiName companywiki
#>
[CmdletBinding()]
param(
    [string]$WikiName    = 'mywiki',
    [string]$ComposeArgs = 'up -d',
    [switch]$Down
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Load the PasswordVault WinRT type
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

function Get-VaultSecret {
    param([string]$Key)
    $cred = $vault.Retrieve($resource, $Key)   # throws if not found
    $cred.RetrievePassword()
    return $cred.Password
}

# ---------------------------------------------------------------------------
# Retrieve the three sensitive secrets and inject them into the process env
# ---------------------------------------------------------------------------
$secretKeys = @('DB_PASSWORD', 'MW_SECRET_KEY', 'MW_UPGRADE_KEY')
$missing    = @()

foreach ($key in $secretKeys) {
    try {
        $value = Get-VaultSecret $key
        [System.Environment]::SetEnvironmentVariable($key, $value, 'Process')
    } catch {
        $missing += $key
    }
}

if ($missing.Count -gt 0) {
    Write-Error (
        "The following secrets were not found in Credential Manager: $($missing -join ', ')`n" +
        "Run .\setup-secrets.ps1 -WikiName $WikiName to store them."
    )
}

Write-Host "Secrets loaded from Windows Credential Manager." -ForegroundColor Green

# ---------------------------------------------------------------------------
# Build the docker compose argument list and invoke
# ---------------------------------------------------------------------------
$rawArgs = if ($Down) { 'down' } else { $ComposeArgs }
$argList = $rawArgs.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)

Write-Host "Running: docker compose $rawArgs" -ForegroundColor Cyan
& docker compose @argList
