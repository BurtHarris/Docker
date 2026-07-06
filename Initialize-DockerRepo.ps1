#Requires -Version 5.1
<#
.SYNOPSIS
    Initialize repository-level developer defaults for this repository.
.DESCRIPTION
    Interviews the developer for local defaults and stores them in the Windows
    registry under HKCU\Software\BurtHarris\Docker. Policy values in
    HKLM\SOFTWARE\Policies\BurtHarris\Docker are enforced transparently and
    always take precedence over user values.

    Current settings:
      - TestContainerContext: Docker context to use for test containers
      - TestContainerHost: Optional Docker host endpoint for remote contexts

    Use Get-DockerRepoConfig.ps1 to read effective values from scripts.
.PARAMETER TestContainerContext
    Optional explicit context value. If omitted, prompts interactively.
    Supported values: default, desktop-linux, desktop-windows, remote.
.PARAMETER TestContainerHost
    Optional explicit remote Docker host (for example tcp://host:2376).
.PARAMETER NonInteractive
    Skip prompts. Requires values to be provided through parameters.
#>
[CmdletBinding()]
param(
    [ValidateSet('default', 'desktop-linux', 'desktop-windows', 'remote')]
    [string]$TestContainerContext,
    [string]$TestContainerHost,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'Initialize-DockerRepo.ps1 currently supports Windows only.'
}

$configScript = Join-Path $PSScriptRoot 'Get-DockerRepoConfig.ps1'
if (-not (Test-Path -Path $configScript)) {
    throw "Missing required script: $configScript"
}

. $configScript
$effective = & $configScript -IncludeMetadata

$userPath = 'Registry::HKEY_CURRENT_USER\Software\BurtHarris\Docker'

function Prompt-ForContext {
    param([string]$Current)

    Write-Host ''
    Write-Host 'Select default test-container deployment context:' -ForegroundColor Cyan
    Write-Host '  [1] default'
    Write-Host '  [2] desktop-linux'
    Write-Host '  [3] desktop-windows'
    Write-Host '  [4] remote'
    Write-Host ''

    $defaultChoice = switch ($Current) {
        'desktop-linux'   { '2' }
        'desktop-windows' { '3' }
        'remote'          { '4' }
        default           { '1' }
    }

    $choice = Read-Host "Choose 1-4 (default: $defaultChoice)"
    if ([string]::IsNullOrWhiteSpace($choice)) {
        $choice = $defaultChoice
    }

    switch ($choice) {
        '1' { return 'default' }
        '2' { return 'desktop-linux' }
        '3' { return 'desktop-windows' }
        '4' { return 'remote' }
        default { throw "Invalid choice '$choice'. Expected 1, 2, 3, or 4." }
    }
}

if (-not $PSBoundParameters.ContainsKey('TestContainerContext')) {
    if ($NonInteractive) {
        throw 'TestContainerContext is required when -NonInteractive is used.'
    }

    $TestContainerContext = Prompt-ForContext -Current $effective.TestContainerContext
}

if ($TestContainerContext -eq 'remote' -and -not $PSBoundParameters.ContainsKey('TestContainerHost')) {
    if ($NonInteractive) {
        throw 'TestContainerHost is required when TestContainerContext is remote and -NonInteractive is used.'
    }

    $defaultHost = $effective.TestContainerHost
    $prompt      = 'Enter remote Docker host (for example tcp://host:2376)'

    if (-not [string]::IsNullOrWhiteSpace($defaultHost)) {
        $prompt = "$prompt (current: $defaultHost)"
    }

    $TestContainerHost = Read-Host $prompt
}

if ($TestContainerContext -ne 'remote') {
    $TestContainerHost = ''
}

if ($null -eq (Get-Item -Path $userPath -ErrorAction SilentlyContinue)) {
    New-Item -Path $userPath -Force | Out-Null
}

New-ItemProperty -Path $userPath -Name 'TestContainerContext' -PropertyType String -Value $TestContainerContext -Force | Out-Null
New-ItemProperty -Path $userPath -Name 'TestContainerHost' -PropertyType String -Value $TestContainerHost -Force | Out-Null

$updated = & $configScript -IncludeMetadata

Write-Host ''
Write-Host 'Repository defaults updated.' -ForegroundColor Green
Write-Host "  TestContainerContext : $($updated.TestContainerContext) [$($updated.Source.TestContainerContext)]"
Write-Host "  TestContainerHost    : $($updated.TestContainerHost) [$($updated.Source.TestContainerHost)]"

if ($updated.Source.TestContainerContext -eq 'Policy' -or $updated.Source.TestContainerHost -eq 'Policy') {
    Write-Host ''
    Write-Host 'One or more values are policy-enforced and may differ from user-entered values.' -ForegroundColor Yellow
}
