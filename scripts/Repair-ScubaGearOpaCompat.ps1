<#
.SYNOPSIS
    Patches ScubaGear's Rego policies so they evaluate under OPA 1.x.

.DESCRIPTION
    ScubaGear 1.8.0 ships two Rego constructs that current OPA releases reject:
      - Utils/TestAssertions.rego: `Fail(msg) := [][0]` is a compile-time type error,
        which stops every product's evaluation.
      - AADConfig.rego: `RootDomainFor()` can return more than one value for a domain,
        an eval_conflict_error that leaves the Entra ID (AAD) report empty.
    The patches keep each check's logic. Originals are saved next to each file as *.orig.

.PARAMETER ModuleBase
    ScubaGear module folder. Defaults to the newest installed ScubaGear.

.PARAMETER Revert
    Restores the *.orig backups.

.EXAMPLE
    pwsh ./scripts/Repair-ScubaGearOpaCompat.ps1

.EXAMPLE
    pwsh ./scripts/Repair-ScubaGearOpaCompat.ps1 -Revert
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ModuleBase,
    [switch]$Revert
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ScubaGearMac.Common.ps1')

if (-not $ModuleBase) { $ModuleBase = (Get-ScubaGearModule).ModuleBase }
Write-Host "ScubaGear module: $ModuleBase"

foreach ($patch in Get-OpaCompatPatches) {
    $path = Join-Path $ModuleBase $patch.File
    $backup = "$path.orig"

    if ($Revert) {
        if (Test-Path $backup) {
            if ($PSCmdlet.ShouldProcess($path, 'Restore original')) {
                Copy-Item $backup $path -Force
                Write-Host "  restored  $($patch.File)"
            }
        } else {
            Write-Host "  no backup $($patch.File)"
        }
        continue
    }

    $text = [IO.File]::ReadAllText($path)
    if (& $patch.IsApplied $text) {
        Write-Host "  ok        $($patch.Name) (already applied)"
        continue
    }

    foreach ($step in $patch.Steps) {
        if (-not [regex]::IsMatch($text, $step.Pattern)) {
            throw "Could not apply '$($patch.Name)': $($patch.File) does not contain the expected code. This ScubaGear version may already be fixed upstream or differ from 1.8.0; no files were changed for this patch."
        }
        $text = [regex]::Replace($text, $step.Pattern, $step.Replacement)
    }
    if (-not (& $patch.IsApplied $text)) {
        throw "Patch '$($patch.Name)' did not produce the expected result; $($patch.File) was not changed."
    }

    if ($PSCmdlet.ShouldProcess($path, $patch.Name)) {
        if (-not (Test-Path $backup)) { Copy-Item $path $backup }
        [IO.File]::WriteAllText($path, $text)
        Write-Host "  patched   $($patch.Name)"
    }
}

if (-not $Revert) {
    $opa = Get-OpaLinkPath
    if (-not (Test-Path $opa)) { $opa = (Get-Command opa -ErrorAction SilentlyContinue)?.Source }
    if ($opa) {
        $regoDir = Join-Path $ModuleBase 'Rego'
        $output = & $opa check $regoDir 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "OPA still reports errors in $regoDir`n$output"
        }
        Write-Host "  verified  opa check passed on $regoDir"
    }
}
