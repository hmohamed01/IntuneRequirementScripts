# IntuneRequirementScripts

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.2.0-informational.svg)](CHANGELOG.md)
[![Build](https://img.shields.io/badge/PSScriptAnalyzer-5.1%20compatible-success.svg)](#verification)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/en-us/powershell/)
[![Platform](https://img.shields.io/badge/platform-Windows-0078D6?logo=windows&logoColor=white)](https://www.microsoft.com/en-us/windows)
[![Intune](https://img.shields.io/badge/Intune-Win32%20app%20requirements-0078D4)](https://learn.microsoft.com/en-us/intune/intune-service/apps/apps-win32-add)

PowerShell requirement scripts for Intune Win32 apps. Each script writes exactly one value to STDOUT, in a form an Intune requirement rule can parse as **Boolean**, **String**, **Integer** or **Version**, so a rule can check whether an app is installed and which version it is.

## How Intune evaluates a requirement script

The Intune Management Extension runs the script on the device: as SYSTEM, in a 64-bit Windows PowerShell 5.1 process, unless the rule says otherwise. If the script **exits with code 0**, Intune reads STDOUT, parses it as the rule's **output data type**, and compares it with the rule's operator and value. With any other exit code, Intune never reads the output, so the rule isn't met.

| Output data type | Operators | Used here for |
|---|---|---|
| String | Equals, Not equal to | `Installed` / `NotInstalled` |
| Boolean | Equals, Not equal to | `True` / `False` |
| Integer | Equals, Not equal to, Greater than, Greater than or equal to, Less than, Less than or equal to | major version, e.g. `24` |
| Version | the same six | full version, e.g. `24.8` |
| Floating Point, Date and Time | the same six | not used yet |

Graph stores the value you compare against as a string, and a Boolean as `true` or `false`.

> **Use Version, not Integer, for version checks.** An Integer holds one whole number, so it can't represent `24.08` or `124.0.6367.91`. Integer is useful when only the major version matters.

## Scripts

| Script | Detects the app by | Version comes from |
|---|---|---|
| [`Applications/Get-AppRequirementByFile.ps1`](Applications/Get-AppRequirementByFile.ps1) | A file path | The file's version resource |
| [`Applications/Get-AppRequirementByWmi.ps1`](Applications/Get-AppRequirementByWmi.ps1) | Display name and publisher in `Win32_InstalledWin32Program` | The version text listed in Installed apps |
| [`Applications/Get-AdobeAcrobatRequirement.ps1`](Applications/Get-AdobeAcrobatRequirement.ps1) | Any Adobe Acrobat product in `Win32_InstalledWin32Program` | Adobe's version, packed into one integer: see [Adobe Acrobat script](#adobe-acrobat-script) |

The two general scripts follow the same output contract, set by `$OutputType` in the configuration block:

| `$OutputType` | Installed | Not installed |
|---|---|---|
| `Boolean` | `True` | `False` |
| `String` | `Installed` | `NotInstalled` |
| `Integer` | Major version, e.g. `24` | No output, exit 1 |
| `Version` | Version, e.g. `24.8.0.0` | No output, exit 1 |

| Exit code | Meaning |
|---|---|
| 0 | A value was written to STDOUT |
| 1 | Nothing to report: the app isn't installed, or (WMI script) its version text has no number in it |
| 2 | Script error: invalid configuration, or the WMI class isn't available |

Diagnostics go to STDERR, never STDOUT, so they can't corrupt the value Intune parses.

**A missing app never meets an Integer or Version rule, whatever the operator.** The script exits 1, so Intune reads no output. That keeps *Less than 24.8* aimed at devices with an old install, not at devices without the app. To target devices without the app, use Boolean *Equals False*.

## Adding a rule in Intune

1. Copy the script and give the copy a name that identifies the app and check, e.g. `Req-7Zip-Version.ps1`.
2. Edit its configuration block: the file path or name pattern, and `$OutputType`.
3. In the app's **Requirements** page, under **Configure additional requirement rules**, select **Add**, set **Requirement type** to **Script**, and upload the copy.
4. Set the rule:
   - **Run script as 32-bit process on 64-bit clients**: No
   - **Run this script using the logged on credentials**: No
   - **Enforce script signature check**: No, unless you sign the script
   - **Select output data type**: the type that matches `$OutputType`, then the operator and value from the table below

| Requirement | `$OutputType` | Output data type | Operator | Value |
|---|---|---|---|---|
| App is installed | `Boolean` | Boolean | Equals | True |
| App isn't installed | `Boolean` | Boolean | Equals | False |
| App is installed | `String` | String | Equals | `Installed` |
| Version 24.8 or later | `Version` | Version | Greater than or equal to | `24.8` |
| Older than 24.8, e.g. to target an upgrade | `Version` | Version | Less than | `24.8` |
| Major version 24 or later | `Integer` | Integer | Greater than or equal to | `24` |

Enter a Version value with as many parts as the script writes. The file script always writes four (`24.8.0.0`). The WMI script writes the version as Installed apps shows it (`24.8`), so run it once on a device to see the exact form. Each script's `.OUTPUTS` help section repeats these tables, so the guidance travels with the script.

## File script: paths and 32-bit processes

`$FilePath` expands environment variables, and a 32-bit process on 64-bit Windows sees different values for some of them:

| Variable | 64-bit process | 32-bit process |
|---|---|---|
| `%ProgramFiles%` | `C:\Program Files` | `C:\Program Files (x86)` |
| `%ProgramW6432%` | `C:\Program Files` | `C:\Program Files` |
| `%ProgramFiles(x86)%` | `C:\Program Files (x86)` | `C:\Program Files (x86)` |

Use `%ProgramW6432%` for a 64-bit app and `%ProgramFiles(x86)%` for a 32-bit app, and the path stays correct however the rule runs. `%ProgramW6432%` doesn't exist on 32-bit Windows.

The version is the four-part numeric file version, so `Version` output always has four parts, e.g. `24.8.0.0`. A file without a version resource reports `0.0.0.0`.

## WMI script: why `Win32_InstalledWin32Program`

**No Windows Installer provider classes.** A `Win32_Product` query makes WMI use the Windows Installer (MSI) provider to enumerate every installed product, and that starts a consistency check: Windows Installer reconfigures each product and logs Event ID 1035 for each one (KB 974524). A requirement rule runs on every device the app targets, every time it's evaluated. The same provider (`Msi.mof`, `Msiprov.dll`) also serves `Win32_SoftwareFeature`, `Win32_SoftwareElement`, `Win32_InstalledSoftwareElement`, `Win32_ProductSoftwareFeatures`, `Win32_Property`, `Win32_Patch`, `Win32_PatchPackage` and dozens more. Keep every class from that provider out of these scripts.

`Win32_InstalledWin32Program` (`root\cimv2`) is defined in `Aeinv.mof`, not the MSI provider, and it isn't in that provider's class list. It lists installed Win32 apps with `Name`, `Vendor`, `Version` and `MsiProductCode`. Microsoft doesn't state outright that it never triggers a check, so confirm it on a device with the Event ID 1035 check under [Testing on a device](#testing-on-a-device). Microsoft documents the class for **Windows clients only**, so on Windows Server the query fails and the script exits 2.

- `$NamePattern` matches the display name shown in **Settings › Apps › Installed apps**, using `-like` wildcards. Make it specific, e.g. `Java 8 Update*` rather than `Java*`, so companion entries such as updaters don't match.
- `Version` is free text. The script keeps the leading number (`24.08` → `24.8`, `1.2.3 build 7` → `1.2.3`), pads a one-part version (`5` → `5.0`), and exits 1 if there's no number at all. Enter the Intune value in the same form, e.g. `24.8`.
- Several entries can match one pattern, such as x86 and x64 builds side by side. `Select-ReportedProgram` decides whose version is reported.
- The script runs as SYSTEM. If an app installs per user, test whether the class lists it before relying on the rule.

## Adobe Acrobat script

`Get-AdobeAcrobatRequirement.ps1` reports the installed Acrobat version as one **Integer**, for a rule such as *Integer, Greater than or equal to, 260222031*. It considers every product whose name starts with *Adobe Acrobat* from a publisher starting with *Adobe*: Acrobat and Acrobat Reader, Continuous and Classic tracks, 32-bit and 64-bit. When several are installed, it reports the highest version. It uses `Win32_InstalledWin32Program` like the general WMI script, so the same Windows Installer and Windows Server notes apply.

Adobe versions are *year.release.build*, and the five-digit build starts with the track: 2 for Continuous, 3 for Classic. The script packs the three parts into one integer:

`year × 10,000,000 + release × 100,000 + build`

| Adobe version | Track | Integer |
|---|---|---|
| `26.002.22031` | Continuous | `260222031` |
| `25.001.20756` | Continuous | `250120756` |
| `24.001.30429` | Classic (Acrobat 2024) | `240130429` |
| `20.005.30838` | Classic (Acrobat 2020) | `200530838` |

Read `260222031` as *26 02 22031*: the year, the release without its leading zero, and the build exactly as Adobe writes it. To convert the version you want the rule to compare against:

```powershell
$v = [version]'26.002.22031'; $v.Major * 10000000 + $v.Minor * 100000 + $v.Build
```

| Requirement | Output data type | Operator | Value |
|---|---|---|---|
| Acrobat 26.002.22031 or later | Integer | Greater than or equal to | `260222031` |
| Acrobat older than 26.002.22031, e.g. to target an update | Integer | Less than | `260222031` |

With no Acrobat product installed, the script exits 1, so neither rule matches.

**Why not just remove the dots?** `2600222031` is larger than 2,147,483,647, the largest 32-bit integer, and Intune doesn't document whether Integer output is 32-bit. If it is, that number would fail to parse on every device and the rule would never match. The packed form stays below 1,000,000,000. It relies on the release being below 100, which Adobe's releases always have been; a release of 100 or more makes the script exit 2 rather than report a number that sorts wrongly.

- Entries whose version isn't in Adobe's format are ignored, so an add-in listed under an Acrobat name doesn't count. If only such entries match, the script exits 1 and STDERR lists what it found.
- Compare within one track. Inside a track, the integers sort exactly as the versions do. Across tracks they sort by year and release first.
- To limit the rule to fewer products, narrow `$NamePattern`, e.g. `Adobe Acrobat Reader*`.

## Testing on a device

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Req-7Zip-Version.ps1
$LASTEXITCODE
```

To test as SYSTEM, the context Intune uses, run the same command through Sysinternals `psexec.exe -s -i`. To test as a 32-bit process, use `%SystemRoot%\SysWOW64\WindowsPowerShell\v1.0\powershell.exe`.

To confirm a script doesn't trigger a Windows Installer consistency check, run it, then look for Event ID 1035 from `MsiInstaller` logged since it started. No output means no product was reconfigured:

```powershell
$startTime = Get-Date
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Req-7Zip-Version.ps1
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'; ProviderName = 'MsiInstaller'; Id = 1035; StartTime = $startTime
} -ErrorAction SilentlyContinue
```

On a managed device, the Intune Management Extension logs are in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs`. `AgentExecutor.log` tracks PowerShell script execution, and `IntuneManagementExtension.log` shows the requirement check.

## Verification

- **PSScriptAnalyzer 1.25**: default rules, plus the compatibility rules for Windows PowerShell 5.1 (Windows 10 1607 and 1809, Windows Server 2019 profiles). No findings, apart from `Select-ReportedProgram`'s unused parameter until it's implemented.
- **WMI class audit**: every WMI call in the repository is `Get-CimInstance` on `Win32_InstalledWin32Program`. No script uses a Windows Installer provider class.
- **13 Acrobat cases**, covering both tracks, unpadded and four-part versions, several products installed together, add-ins, a wrong publisher, a release of 100, and a missing WMI class. Plus a check that the integer keeps eight real versions from Adobe's release notes in order.
- **22 behavior cases** run in PowerShell 7.6, covering every `$OutputType`, missing and present apps, configuration errors and a missing WMI class. `Get-CimInstance` was stubbed, because the test machine has no WMI. Not yet run on a Windows device.

## Repository layout

```
IntuneRequirementScripts/
└── Applications/
    ├── Get-AdobeAcrobatRequirement.ps1   Adobe Acrobat version as one integer
    ├── Get-AppRequirementByFile.ps1      App present / version, by file
    └── Get-AppRequirementByWmi.ps1       App present / version, by Win32_InstalledWin32Program
```

Planned: requirement scripts for the operating system, such as OS version and multi-session.

## Sources

Checked on November 3, 2026:

- [Add, assign, and monitor a Win32 app in Microsoft Intune](https://learn.microsoft.com/en-us/intune/intune-service/apps/apps-win32-add) — requirement rule settings; STDOUT is evaluated when the exit code is 0
- [win32LobAppPowerShellScriptRequirement](https://learn.microsoft.com/en-us/graph/api/resources/intune-apps-win32lobapppowershellscriptrequirement?view=graph-rest-1.0), [detection type](https://learn.microsoft.com/en-us/graph/api/resources/intune-apps-win32lobapppowershellscriptdetectiontype?view=graph-rest-1.0) and [operator](https://learn.microsoft.com/en-us/graph/api/resources/intune-apps-win32lobappdetectionoperator?view=graph-rest-1.0) — output data types and operators
- [IntuneWin32App `New-IntuneWin32AppRequirementRuleScript`](https://www.powershellgallery.com/packages/IntuneWin32App/1.5.0/Content/Public%5CNew-IntuneWin32AppRequirementRuleScript.ps1) — operators allowed per type; Boolean stored as `true`/`false`
- [Troubleshoot Win32 app issues](https://learn.microsoft.com/en-us/intune/intune-service/apps/apps-win32-troubleshoot) — log locations
- [Win32_InstalledWin32Program class](https://learn.microsoft.com/en-us/windows/win32/wmisdk/win32-installedwin32program)
- [Windows Installer reconfigured all installed applications (KB 974524)](https://learn.microsoft.com/en-us/troubleshoot/windows-server/admin-development/windows-installer-reconfigured-all-applications)
- [WOW64 implementation details](https://learn.microsoft.com/en-us/windows/win32/winprog64/wow64-implementation-details) — environment variables in 32-bit and 64-bit processes
- [Adobe Acrobat release notes](https://www.adobe.com/devnet-docs/acrobatetk/tools/ReleaseNotesDC/index.html) — current version numbers for each track
- [Document Cloud tracks explained: Continuous vs Classic](https://community.adobe.com/t5/acrobat-reader-discussions/document-cloud-tracks-explained-quot-continuous-quot-vs-quot-classic-quot/td-p/7226460) — the track digit in the build number

## License

[MIT](LICENSE)
