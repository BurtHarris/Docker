#Requires -Version 5.1
<#
.SYNOPSIS
    Get effective repository-level developer defaults from the Windows registry.
.DESCRIPTION
    Reads per-user settings from HKCU and transparently applies policy overrides
    from HKLM when present.

    User settings path:
      HKCU\Software\BurtHarris\Docker

    Policy settings path:
      HKLM\SOFTWARE\Policies\BurtHarris\Docker

    Current settings:
      - TestContainerContext
      - TestContainerHost
.PARAMETER IncludeMetadata
    Include value-source metadata for each setting (Default/User/Policy).
#>
[CmdletBinding()]
param(
    [switch]$IncludeMetadata
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'Get-DockerRepoConfig.ps1 currently supports Windows only.'
}

$userPath   = 'Registry::HKEY_CURRENT_USER\Software\BurtHarris\Docker'
$policyPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\BurtHarris\Docker'

$defaults = @{
    TestContainerContext = 'default'
    TestContainerHost    = ''
}

function Get-RegistryValue {
    param(
        [string]$Path,
        [string]$Name
    )

    if (-not (Test-Path -Path $Path)) {
        return $null
    }

    $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return $null
    }

    return $item.$Name
}

$result         = [ordered]@{}
$sourceMetadata = [ordered]@{}

function Resolve-Value {
    param(
        [string]$PolicyValue,
        [string]$UserValue,
        [string]$DefaultValue
    )

    if (-not [string]::IsNullOrWhiteSpace($PolicyValue)) {
        return [pscustomobject]@{
            Value  = [string]$PolicyValue
            Source = 'Policy'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($UserValue)) {
        return [pscustomobject]@{
            Value  = [string]$UserValue
            Source = 'User'
        }
    }

    return [pscustomobject]@{
        Value  = [string]$DefaultValue
        Source = 'Default'
    }
}

foreach ($name in $defaults.Keys) {
    $policyValue = Get-RegistryValue -Path $policyPath -Name $name
    $userValue   = Get-RegistryValue -Path $userPath -Name $name

    $resolved = Resolve-Value -PolicyValue $policyValue -UserValue $userValue -DefaultValue $defaults[$name]
    $result[$name] = $resolved.Value
    $sourceMetadata[$name] = $resolved.Source
}

if ($IncludeMetadata) {
    $result['Source'] = [pscustomobject]$sourceMetadata
}

[pscustomobject]$result
