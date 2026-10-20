Set-StrictMode -Version Latest

$script:TestedScubaGearVersion = [version]'1.8.0'
$script:OpaToolsPath = Join-Path $HOME '.scubagear/Tools'

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-ScubaGearModule {
    param([version]$RequiredVersion)
    $modules = @(Get-Module -ListAvailable -Name ScubaGear | Sort-Object Version -Descending)
    if ($RequiredVersion) {
        $modules = @($modules | Where-Object Version -eq $RequiredVersion)
    }
    if ($modules.Count -eq 0) {
        $wanted = if ($RequiredVersion) { " $RequiredVersion" } else { "" }
        throw "ScubaGear$wanted is not installed. Run ./scripts/Install-ScubaGearMac.ps1 first."
    }
    $modules[0]
}

function Import-ScubaGearMac {
    # ScubaGear.psd1 runs Dependencies.ps1 at import time, which calls the Windows-only
    # WindowsPrincipal API and aborts on macOS. Importing the .psm1 files directly skips it.
    param([version]$RequiredVersion)
    $module = Get-ScubaGearModule -RequiredVersion $RequiredVersion
    Import-Module (Join-Path $module.ModuleBase 'Modules/Support/Support.psm1') -Force -WarningAction SilentlyContinue
    Import-Module (Join-Path $module.ModuleBase 'ScubaGear.psm1') -Force -WarningAction SilentlyContinue
    if ($module.Version -ne $script:TestedScubaGearVersion) {
        Write-Warning "ScubaGear $($module.Version) is installed; these scripts were tested with $script:TestedScubaGearVersion."
    }
    $module
}

function Get-OpaCompatPatches {
    # Rego in ScubaGear 1.8.0 that OPA 1.x (Rego v1 semantics) rejects. Patterns tolerate CRLF and LF.
    @(
        [pscustomobject]@{
            Name      = 'TestAssertions.rego: Fail() no longer indexes an empty array'
            File      = 'Rego/Utils/TestAssertions.rego'
            IsApplied = { param($text) $text -match 'Fail\(msg\) if \{' -and $text -notmatch 'Fail\(msg\) := \[\]\[0\]' }
            Steps     = @(
                @{
                    Pattern     = 'Fail\(msg\) := \[\]\[0\] if \{(?<body>[\s\S]*?print\(msg\))(?<nl>\r?\n)\}'
                    Replacement = 'Fail(msg) if {${body}${nl}    false${nl}}'
                }
            )
        },
        [pscustomobject]@{
            Name      = 'AADConfig.rego: RootDomainFor() inlined so it cannot return multiple values'
            File      = 'Rego/AADConfig.rego'
            IsApplied = { param($text) $text -notmatch 'RootDomainFor\(' }
            Steps     = @(
                @{
                    Pattern     = 'RootDomainFor\(Domain\) := Root\.Id if \{\r?\n[ \t]*some Root in RootDomains\r?\n[ \t]*endswith\(Domain\.Id, Root\.Id\)\r?\n\}\r?\n\r?\n'
                    Replacement = ''
                },
                @{
                    Pattern     = '(?<i>[ \t]*)RootDomainFor\(Domain\) != null(?<nl>\r?\n)[ \t]*some Root in RootDomains\r?\n[ \t]*Root\.Id == RootDomainFor\(Domain\)'
                    Replacement = '${i}some Root in RootDomains${nl}${i}endswith(Domain.Id, Root.Id)'
                }
            )
        }
    )
}

function Test-OpaCompatPatched {
    param([Parameter(Mandatory)][string]$ModuleBase)
    foreach ($patch in Get-OpaCompatPatches) {
        $path = Join-Path $ModuleBase $patch.File
        if (-not (& $patch.IsApplied ([IO.File]::ReadAllText($path)))) { return $false }
    }
    $true
}

function Get-OpaLinkPath {
    Join-Path $script:OpaToolsPath 'opa'
}
