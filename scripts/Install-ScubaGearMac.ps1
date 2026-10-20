<#
.SYNOPSIS
    Prepares a Mac to run CISA ScubaGear against a Microsoft 365 tenant.

.DESCRIPTION
    1. Checks for macOS and PowerShell 7.
    2. Installs Open Policy Agent with Homebrew if it is not on PATH, and checks that it runs.
    3. Links OPA to ~/.scubagear/Tools/opa, the path ScubaGear uses on macOS and Linux.
    4. Installs ScubaGear from the PowerShell Gallery for the current user.
    5. Runs Initialize-SCuBA to install ScubaGear's PowerShell dependencies.
    6. Offers to remove dependency versions newer than ScubaGear supports.
    7. Applies the OPA compatibility patches (Repair-ScubaGearOpaCompat.ps1).
    Safe to run more than once.

.PARAMETER ScubaGearVersion
    ScubaGear version to install. Defaults to the version these scripts were tested with.

.PARAMETER RemoveIncompatibleModules
    Uninstall dependency versions above ScubaGear's maximum without asking.

.EXAMPLE
    pwsh ./scripts/Install-ScubaGearMac.ps1
#>
[CmdletBinding()]
param(
    [version]$ScubaGearVersion = '1.8.0',
    [switch]$RemoveIncompatibleModules
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ScubaGearMac.Common.ps1')

Write-Step 'Checking platform'
if (-not $IsMacOS) { throw 'This script is for macOS. On Windows, follow the standard ScubaGear instructions.' }
if ($PSVersionTable.PSVersion -lt [version]'7.2') {
    throw "PowerShell 7.2 or later is required; this is $($PSVersionTable.PSVersion). Run: brew install --cask powershell"
}
Write-Host "macOS, PowerShell $($PSVersionTable.PSVersion)"

Write-Step 'Checking Open Policy Agent (OPA)'
$opaCommand = Get-Command opa -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $opaCommand) {
    if (-not (Get-Command brew -ErrorAction SilentlyContinue)) {
        throw 'OPA is not installed and Homebrew was not found. Install Homebrew from https://brew.sh, or install OPA from https://www.openpolicyagent.org/docs/latest/#running-opa and put it on PATH, then rerun.'
    }
    Write-Host 'Installing OPA with Homebrew...'
    & brew install opa
    if ($LASTEXITCODE -ne 0) { throw 'brew install opa failed.' }
    $opaCommand = Get-Command opa -CommandType Application | Select-Object -First 1
}
$opaPath = $opaCommand.Source
$opaVersion = & $opaPath version 2>&1
if ($LASTEXITCODE -ne 0) {
    $hint = if ($LASTEXITCODE -eq 137) {
        ' Exit code 137 means the process was killed, which usually comes from endpoint security or application allowlisting software. Ask your security team to allow this binary, then rerun.'
    } else { '' }
    throw "OPA at $opaPath failed to run (exit code $LASTEXITCODE).$hint"
}
Write-Host "$opaPath ($(@($opaVersion)[0]))"

Write-Step "Linking OPA to $(Get-OpaLinkPath)"
New-Item -ItemType Directory -Force -Path $script:OpaToolsPath | Out-Null
$link = Get-OpaLinkPath
$existing = Get-Item $link -Force -ErrorAction SilentlyContinue
if ($existing -and $existing.LinkType -eq 'SymbolicLink' -and $existing.Target -eq $opaPath) {
    Write-Host 'Link already in place.'
} else {
    if ($existing) {
        $saved = "$link.bak-$(Get-Date -Format yyyyMMddHHmmss)"
        Move-Item $link $saved
        Write-Host "Moved existing $link to $saved"
    }
    New-Item -ItemType SymbolicLink -Path $link -Target $opaPath | Out-Null
    Write-Host "Linked $link -> $opaPath"
}

Write-Step "Installing ScubaGear $ScubaGearVersion"
if (Get-Module -ListAvailable -Name ScubaGear | Where-Object Version -eq $ScubaGearVersion) {
    Write-Host 'Already installed.'
} else {
    Install-Module -Name ScubaGear -RequiredVersion $ScubaGearVersion -Repository PSGallery -Scope CurrentUser -Force
}
$module = Import-ScubaGearMac -RequiredVersion $ScubaGearVersion
Write-Host "Loaded from $($module.ModuleBase)"

Write-Step "Installing ScubaGear's PowerShell dependencies"
Initialize-SCuBA -NoOPA -SkipUpdate

Write-Step 'Checking for dependency versions newer than ScubaGear supports'
. (Join-Path $module.ModuleBase 'RequiredVersions.ps1')
$tooNew = foreach ($dependency in $ModuleList) {
    if (-not $dependency.ContainsKey('MaximumVersion')) { continue }
    Get-Module -ListAvailable -Name $dependency.ModuleName |
        Where-Object Version -gt $dependency.MaximumVersion |
        ForEach-Object { [pscustomobject]@{ Name = $_.Name; Version = $_.Version; Maximum = $dependency.MaximumVersion } }
}
$tooNew = @($tooNew | Sort-Object Name, Version -Unique)
if ($tooNew.Count -eq 0) {
    Write-Host 'None found.'
} else {
    $tooNew | Format-Table Name, Version, Maximum -AutoSize | Out-Host
    Write-Host 'PowerShell loads the newest installed version, which ScubaGear has not been tested with.'
    $remove = $RemoveIncompatibleModules -or ((Read-Host 'Uninstall these versions? [y/N]') -match '^(y|yes)$')
    if ($remove) {
        foreach ($item in $tooNew) {
            try {
                Uninstall-Module -Name $item.Name -RequiredVersion $item.Version -Force -ErrorAction Stop
                Write-Host "Removed $($item.Name) $($item.Version)"
            } catch {
                Write-Warning "Could not remove $($item.Name) $($item.Version): $($_.Exception.Message)"
            }
        }
    } else {
        Write-Warning 'Left in place. If a product fails to collect data, rerun with -RemoveIncompatibleModules.'
    }
}

Write-Step 'Applying OPA compatibility patches'
& (Join-Path $PSScriptRoot 'Repair-ScubaGearOpaCompat.ps1') -ModuleBase $module.ModuleBase

Write-Step 'Setup complete'
Write-Host 'Run the assessment with:  pwsh ./scripts/Invoke-ScubaGearMac.ps1'
