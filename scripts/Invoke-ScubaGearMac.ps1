<#
.SYNOPSIS
    Runs a CISA ScubaGear assessment of a Microsoft 365 tenant from macOS.

.DESCRIPTION
    Loads ScubaGear without its Windows-only startup check, confirms OPA and the
    compatibility patches are in place, and calls Invoke-SCuBA. A browser window opens
    for Microsoft 365 sign-in. When the run finishes, the HTML report opens.

.PARAMETER ProductNames
    Products to assess: aad, defender, exo, powerplatform, sharepoint, teams, or *.

.PARAMETER M365Environment
    commercial, gcc, gcchigh or dod.

.PARAMETER OutPath
    Folder for results. Each run creates a timestamped subfolder.

.PARAMETER ConfigFilePath
    Optional ScubaGear YAML or JSON config file (exclusions, org name, annotations).
    Samples ship with ScubaGear in its Sample-Config-Files folder.

.PARAMETER NoOpen
    Do not open the HTML report when the run finishes.

.EXAMPLE
    pwsh ./scripts/Invoke-ScubaGearMac.ps1

.EXAMPLE
    pwsh ./scripts/Invoke-ScubaGearMac.ps1 -ProductNames aad,exo -ConfigFilePath ./my-config.yaml
#>
[CmdletBinding()]
param(
    [ValidateSet('aad', 'defender', 'exo', 'powerplatform', 'sharepoint', 'teams', '*')]
    [string[]]$ProductNames = @('aad', 'defender', 'exo', 'sharepoint', 'teams'),

    [ValidateSet('commercial', 'gcc', 'gcchigh', 'dod')]
    [string]$M365Environment = 'commercial',

    [string]$OutPath = (Join-Path $HOME 'ScubaGearOutput'),

    [string]$ConfigFilePath,

    [switch]$NoOpen
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ScubaGearMac.Common.ps1')

$module = Import-ScubaGearMac

if (-not (Test-Path (Get-OpaLinkPath))) {
    throw "OPA was not found at $(Get-OpaLinkPath). Run ./scripts/Install-ScubaGearMac.ps1 first."
}
if (-not (Test-OpaCompatPatched -ModuleBase $module.ModuleBase)) {
    throw 'The OPA compatibility patches are not applied, so results would be empty. Run ./scripts/Repair-ScubaGearOpaCompat.ps1 first.'
}

New-Item -ItemType Directory -Force -Path $OutPath | Out-Null
$started = Get-Date

$scubaArgs = @{
    ProductNames    = $ProductNames
    M365Environment = $M365Environment
    OPAPath         = $script:OpaToolsPath
    OutPath         = $OutPath
}
if ($ConfigFilePath) { $scubaArgs.ConfigFilePath = (Resolve-Path $ConfigFilePath).Path }

Write-Host ''
Write-Host 'ScubaGear assessment' -ForegroundColor Cyan
Write-Host "  Products:    $($ProductNames -join ', ')"
Write-Host "  Environment: $M365Environment"
Write-Host "  Output:      $OutPath"
Write-Host ''
Write-Host 'A browser window will open for Microsoft 365 sign-in. Some products may ask you to sign in again.' -ForegroundColor Yellow

Invoke-SCuBA @scubaArgs

$report = Get-ChildItem -Path $OutPath -Filter 'BaselineReports.html' -Recurse -ErrorAction SilentlyContinue |
    Where-Object LastWriteTime -ge $started |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($report) {
    Write-Host ''
    Write-Host "Report: $($report.FullName)" -ForegroundColor Green
    if (-not $NoOpen) { & open $report.FullName }
} else {
    Write-Warning "No new report was found under $OutPath. Check the DebugLogs folder of the latest run."
}
