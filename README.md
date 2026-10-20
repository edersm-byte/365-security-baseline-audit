# Microsoft 365 Security Baseline Audit on macOS

Scripts for running [CISA ScubaGear](https://github.com/cisagov/ScubaGear) from a Mac to check a Microsoft 365 tenant against the CISA Secure Cloud Business Applications (SCuBA) baselines.

ScubaGear is built and tested on Windows. On macOS, ScubaGear 1.8.0 with a current Open Policy Agent (OPA) runs into these problems:

| Problem | What you see | What these scripts do |
|---|---|---|
| The module manifest runs a Windows-only check at import | `Windows Principal functionality is not supported on this platform` | Import ScubaGear's `.psm1` files directly, skipping that check |
| ScubaGear looks for a file named `opa` on macOS, not `opa_darwin_amd64` | `Open Policy Agent executable was not found` | Link Homebrew's `opa` to `~/.scubagear/Tools/opa` |
| OPA 1.x rejects `Fail(msg) := [][0]` in `Utils/TestAssertions.rego` | `rego_type_error: undefined ref: [][0]`, then `No test results found` for every product | Patch the rule so it compiles under Rego v1 |
| OPA 1.x rejects `RootDomainFor()` in `AADConfig.rego` returning more than one value | `eval_conflict_error: functions must not produce multiple outputs`, and the Entra ID (AAD) report is empty | Inline the lookup into `IsValid()` |
| Dependency versions newer than ScubaGear supports | `Microsoft.Graph.Authentication: Version 2.39.0 is installed but exceeds maximum` | Offer to uninstall the too-new versions |

The Rego patches keep what each check tests. Originals are saved as `*.orig` and can be restored.

> This project is not affiliated with or endorsed by CISA. ScubaGear is CISA's software, used under its own license.

## Requirements

- macOS on Apple silicon or Intel
- [Homebrew](https://brew.sh)
- PowerShell 7.2 or later
- A Microsoft 365 account that can read tenant configuration. Global Reader covers most products. Some products, and the first-time consent for the Microsoft Graph PowerShell app, may need Global Administrator or a product admin role. See ScubaGear's [permissions documentation](https://github.com/cisagov/ScubaGear/tree/main/docs).
- Tested with ScubaGear 1.8.0, OPA 1.21.3, PowerShell 7.6 on macOS

## Quick start

1. Install PowerShell, if you don't have it:

   ```bash
   brew install --cask powershell
   ```

2. Clone this repository:

   ```bash
   git clone https://github.com/edersm-byte/365-security-baseline-audit.git
   cd 365-security-baseline-audit
   ```

3. Run the setup script. It installs OPA, ScubaGear and its dependencies, then applies the patches. It is safe to run again.

   ```bash
   pwsh ./scripts/Install-ScubaGearMac.ps1
   ```

4. Run the assessment. A browser window opens for Microsoft 365 sign-in, and the report opens when the run finishes.

   ```bash
   pwsh ./scripts/Invoke-ScubaGearMac.ps1
   ```

Results are saved to `~/ScubaGearOutput/M365BaselineConformance_<timestamp>/`.

## What the setup script does

`Install-ScubaGearMac.ps1`:

1. Checks for macOS and PowerShell 7.2+.
2. Installs OPA with Homebrew if `opa` is not on your PATH, then checks that it runs.
3. Creates the link `~/.scubagear/Tools/opa` pointing to that binary. An existing file at that path is renamed, not deleted.
4. Installs ScubaGear 1.8.0 from the PowerShell Gallery for the current user.
5. Runs ScubaGear's `Initialize-SCuBA -NoOPA -SkipUpdate`, which installs its PowerShell dependencies. This step marks the PowerShell Gallery as a trusted repository.
6. Lists any dependency installed at a version above ScubaGear's maximum and asks before uninstalling it. Use `-RemoveIncompatibleModules` to skip the question.
7. Runs `Repair-ScubaGearOpaCompat.ps1`, then `opa check` on ScubaGear's Rego folder.

Options:

```bash
pwsh ./scripts/Install-ScubaGearMac.ps1 -RemoveIncompatibleModules
pwsh ./scripts/Install-ScubaGearMac.ps1 -ScubaGearVersion 1.8.0
```

## Running assessments

```bash
# All default products (aad, defender, exo, sharepoint, teams)
pwsh ./scripts/Invoke-ScubaGearMac.ps1

# Selected products
pwsh ./scripts/Invoke-ScubaGearMac.ps1 -ProductNames aad,exo

# Government clouds
pwsh ./scripts/Invoke-ScubaGearMac.ps1 -M365Environment gcc

# Custom output folder, don't open the report
pwsh ./scripts/Invoke-ScubaGearMac.ps1 -OutPath ~/Audits/m365 -NoOpen

# Use a ScubaGear config file
pwsh ./scripts/Invoke-ScubaGearMac.ps1 -ConfigFilePath ./my-config.yaml
```

Before it starts, the run script checks that OPA is linked and the patches are applied. Without the patches, the run would finish but the reports would be empty.

### Config files

A ScubaGear config file records your organization name, documents approved exceptions, and annotates policies you accept as risks. One common use is listing the break-glass accounts excluded from Conditional Access, because ScubaGear counts any undocumented exclusion as a failure.

ScubaGear ships sample files in its module folder:

```bash
ls ~/.local/share/powershell/Modules/ScubaGear/1.8.0/Sample-Config-Files/
```

Copy one outside this repository, edit it, and pass it with `-ConfigFilePath`. See ScubaGear's [configuration documentation](https://github.com/cisagov/ScubaGear/blob/main/docs/configuration/configuration.md) for the format.

### Calling ScubaGear directly

To use other `Invoke-SCuBA` parameters, load ScubaGear the same way the scripts do:

```powershell
. ./scripts/ScubaGearMac.Common.ps1
Import-ScubaGearMac
Invoke-SCuBA -ProductNames teams -OPAPath ~/.scubagear/Tools -OutPath ~/ScubaGearOutput -DarkMode
```

## Output

See [`sample-report/`](sample-report/) for CISA's example output from a fictional tenant. Each run folder contains:

| File | Contents |
|---|---|
| `BaselineReports.html` | Summary report with links to each product report |
| `IndividualReports/` | One HTML report per product |
| `ScubaResults_<id>.json` | Full results and the raw configuration that was collected |
| `ScubaResults.csv`, `ActionPlan.csv` | Results as spreadsheets, and failed controls with blank columns for planning |
| `DebugLogs/` | Run log and a debug summary |

These files describe your tenant's security configuration, including admin account names and domain details. Store them like any other sensitive security document. The `.gitignore` in this repository excludes them, so keep them out of version control.

## Troubleshooting

| Message | Cause and fix |
|---|---|
| `opa` exits with code 137, or OPA is killed as soon as it starts | Endpoint security or application allowlisting software stopped an unsigned binary. Ask your security team to allow `opa` (Homebrew installs it under `$(brew --prefix)/Cellar/opa/`), then rerun setup. |
| `Windows Principal functionality is not supported on this platform` | ScubaGear was imported with `Import-Module ScubaGear`. Use the scripts here, or `Import-ScubaGearMac`. |
| `Open Policy Agent executable was not found` | `~/.scubagear/Tools/opa` is missing. Rerun the setup script. |
| `rego_type_error: undefined ref: [][0]`, or `No test results found` for every control | The patches are missing, often after reinstalling or updating ScubaGear. Run `pwsh ./scripts/Repair-ScubaGearOpaCompat.ps1`. |
| `eval_conflict_error ... RootDomainFor` | Same as above. |
| `Could not apply ... does not contain the expected code` | Your ScubaGear version differs from 1.8.0. The upstream code may already be fixed; run an assessment and check for empty reports before changing anything. |
| `Version ... exceeds maximum` | Rerun setup with `-RemoveIncompatibleModules`. |
| `The term 'Get-CimInstance' is not recognized` | Windows-only diagnostics in the debug log. Harmless. |
| `Failed to retrieve OPA information`, or `Loaded version 0.0` in the debug report | Side effects of importing the `.psm1` files directly. Harmless. |
| `Resulting JSON is truncated as serialization has exceeded the set depth` | Warnings from ScubaGear's data collection. In testing they did not affect results. |
| `OrgName not provided. This option is required for BOD submissions` | Applies to U.S. federal agencies. Set `OrgName` in a config file, or add `-SilenceBODWarnings` when calling `Invoke-SCuBA` directly. |

## Updating or removing

- **Updating ScubaGear:** after installing a new version, run `pwsh ./scripts/Repair-ScubaGearOpaCompat.ps1`. If it reports that the expected code is missing, the new version may not need the patches.
- **Undoing the patches:** run `pwsh ./scripts/Repair-ScubaGearOpaCompat.ps1 -Revert`.
- **Removing everything:** run `Uninstall-Module ScubaGear -AllVersions` in PowerShell, `brew uninstall opa`, and `rm -rf ~/.scubagear`.

## Repository layout

```
scripts/
  Install-ScubaGearMac.ps1       One-time setup, safe to rerun
  Invoke-ScubaGearMac.ps1        Runs an assessment and opens the report
  Repair-ScubaGearOpaCompat.ps1  Applies or reverts the OPA 1.x Rego patches
  ScubaGearMac.Common.ps1        Shared helpers used by the scripts above
sample-report/                   CISA's sample output from a fictional tenant
```

## License

MIT. See [LICENSE](LICENSE). ScubaGear itself is licensed separately by CISA.
