#Requires -Version 5.1
<#
.SYNOPSIS
    Decrypt MediaWiki secrets and start the Docker stack.
.DESCRIPTION
    Reads each CMS-encrypted secret file from wikimedia/secrets/, decrypts it
    with Unprotect-CmsMessage (which automatically uses the matching private key
    from the Windows certificate store), injects the plaintext as a process-
    scoped environment variable, then calls docker compose.

    Plaintext values exist only in the running process — they are never written
    to disk and are cleared from PowerShell variables immediately after the env
    var is set.

    Non-sensitive configuration (WIKI_NAME, DB_NAME, DB_USER, MW_SITE_SERVER,
    DEV_PORT) is still read from .env as usual.

.PARAMETER WikiName
    Logical identifier for this wiki instance.  Default: "mywiki"
.PARAMETER ComposeArgs
    Arguments forwarded to docker compose as an array.  Default: @('up','-d')
.PARAMETER Down
    Convenience flag — equivalent to -ComposeArgs @('down')
.EXAMPLE
    .\Start-Wiki.ps1
    .\Start-Wiki.ps1 -ComposeArgs up, -d, --build
    .\Start-Wiki.ps1 -Down
    .\Start-Wiki.ps1 -WikiName companywiki
#>
[CmdletBinding()]
param(
    [string]  $WikiName    = 'mywiki',
    [string[]]$ComposeArgs = @('up', '-d'),
    [switch]  $Down
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$secretsDir = Join-Path $PSScriptRoot 'secrets'

if (-not (Test-Path $secretsDir)) {
    Write-Error (
        "Secrets directory not found: $secretsDir`n" +
        "Run .\New-WikiKey.ps1 then .\Set-WikiSecrets.ps1 first."
    )
}

# ---------------------------------------------------------------------------
# Decrypt each secret and inject as a process-scoped environment variable
# ---------------------------------------------------------------------------
$secretKeys = @('DB_PASSWORD', 'MW_SECRET_KEY', 'MW_UPGRADE_KEY')
$missing    = @()

foreach ($key in $secretKeys) {
    $cmsPath = Join-Path $secretsDir "$key.cms"
    if (-not (Test-Path $cmsPath)) {
        $missing += $key
        continue
    }
    try {
        $plain = Unprotect-CmsMessage -Path $cmsPath
        [System.Environment]::SetEnvironmentVariable($key, $plain, 'Process')
        $plain = $null   # clear plaintext from memory as soon as possible
    } catch {
        Write-Error "Failed to decrypt $key from '$cmsPath': $_"
    }
}

if ($missing.Count -gt 0) {
    Write-Error (
        "Missing encrypted secret files: $($missing -join ', ')`n" +
        "Run .\Set-WikiSecrets.ps1 -WikiName $WikiName to create them."
    )
}

Write-Host 'Secrets decrypted and loaded.' -ForegroundColor Green

# ---------------------------------------------------------------------------
# Apply repo-level Docker defaults (Windows registry user/policy)
# ---------------------------------------------------------------------------
$repoConfigScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'Get-DockerRepoConfig.ps1'
if (Test-Path -Path $repoConfigScript) {
    $repoConfig = & $repoConfigScript
    $dockerContext = $repoConfig.TestContainerContext

    if (-not [string]::IsNullOrWhiteSpace($dockerContext)) {
        [System.Environment]::SetEnvironmentVariable('DOCKER_CONTEXT', $dockerContext, 'Process')
        Write-Host "Using DOCKER_CONTEXT from repo config: $dockerContext" -ForegroundColor DarkGray
    }

    if ($dockerContext -eq 'remote' -and -not [string]::IsNullOrWhiteSpace($repoConfig.TestContainerHost)) {
        [System.Environment]::SetEnvironmentVariable('DOCKER_HOST', $repoConfig.TestContainerHost, 'Process')
        Write-Host "Using DOCKER_HOST from repo config: $($repoConfig.TestContainerHost)" -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
# Invoke docker compose
# ---------------------------------------------------------------------------
$cmdArgs = if ($Down) { @('down') } else { $ComposeArgs }

Write-Host "Running: docker compose $($cmdArgs -join ' ')" -ForegroundColor Cyan
& docker compose @cmdArgs
exit $LASTEXITCODE
