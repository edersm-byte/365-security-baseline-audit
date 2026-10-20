# Sample report

This is an example of the output folder that one ScubaGear run creates. It comes from CISA and ships inside ScubaGear 1.8.0 (`Sample-Reports/` in the module folder). It was generated against CISA's fictional test tenant `tqhjy.onmicrosoft.com` and contains no real organization's data.

Open `BaselineReports.html` in a browser to start. GitHub shows HTML files as source code, so download or clone the repository to view the pages.

| File | Contents |
|---|---|
| `BaselineReports.html` | Summary page with pass, warning, failure and manual-check counts per product |
| `IndividualReports/*.html` | One detailed report per product: Entra ID (AAD), Defender, Exchange Online, Power Platform, SharePoint, Teams |
| `IndividualReports/*.json` | The same per-product results as JSON |
| `ScubaResults_<id>.json` | Combined results, metadata and the raw configuration that was collected |
| `ScubaResults.csv` | Every control and its result, for spreadsheets |
| `ActionPlan.csv` | Failed controls with blank columns for planning remediation |
| `TestResults.json` | OPA's raw policy evaluation output |
| `ProviderSettingsExport.json` | The tenant configuration that was collected and fed to OPA |

A real run also creates a `DebugLogs/` folder. Real output describes a tenant's security configuration, so this repository's `.gitignore` keeps it out of version control. Only this sample folder is allowed.
