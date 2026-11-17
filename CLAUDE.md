# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Intune Win32 app **requirement scripts**. Each one is a standalone Windows PowerShell 5.1 script that a user uploads as a requirement rule. The Intune Management Extension runs it on every targeted device, as SYSTEM in a 64-bit process, with no arguments. Intune reads STDOUT only when the script exits 0, and then parses it as the rule's output data type (Boolean, String, Integer, Version, ...). README.md covers the Intune side in depth: data types and operators, rule recipes, WOW64 paths, testing on a device, and sources.

Development happens on macOS with PowerShell 7.6. The scripts target Windows PowerShell 5.1, and they haven't run on Windows or under Intune yet.

## Output contract (every script)

- **Exit 0:** exactly one line on STDOUT, written with `Write-Output`.
- **Exit 1:** nothing to report (the app is missing, or its version can't be read). Microsoft documents only that Intune reads STDOUT on exit 0. It doesn't document what a non-zero exit means for a requirement rule; the scripts assume the rule isn't met, as Microsoft documents for detection scripts. So a missing app is expected never to meet an Integer or Version rule. Keep the docs and `.OUTPUTS` wording clear about which parts are documented and which are assumed. Rules that target devices without the app use Boolean Equals False. Don't replace exit 1 with a sentinel value such as `0`.
- **Exit 2:** script error. A top-level `trap` produces it; the trap is hoisted, so with `$ErrorActionPreference = 'Stop'` it catches every error in the script.
- **Diagnostics:** write them with `[Console]::Error.WriteLine(...)`. Never use `Write-Host`, `Write-Warning`, `Write-Verbose` or `Write-Information`: when Windows PowerShell runs non-interactively they can reach STDOUT and corrupt the value Intune parses. Write diagnostics only on a non-zero exit: Microsoft documents that any STDERR output makes a *detection* script count as not installed even with exit 0, and doesn't say whether that applies to requirement scripts.

## Script anatomy

All scripts share one layout; copy an existing script to start a new one.

1. `#Requires -Version 5.1`, then a **blank line**, then the comment-based help. Without the blank line, `Get-Help` silently ignores the whole help block.
2. Help sections:
   - `.SYNOPSIS` and `.DESCRIPTION`.
   - `.OUTPUTS`: the user-facing spec of what Intune should expect. It gives the exact STDOUT for each case, the exit codes, and example rules (data type, operator, value). When behavior changes, keep it in sync with the code and with the README tables.
   - `.NOTES`: the Intune rule settings.
3. `$ErrorActionPreference = 'Stop'`, followed by the `trap` that exits 2.
4. A `# --- Configuration ---` block of typed variables, used instead of a `param()` block because Intune passes no parameters. Validation attributes (`[ValidateNotNullOrEmpty()]`, `[ValidateSet(...)]`) make an invalid value fail at assignment, so the script exits 2. Keep `ValidateNotNullOrEmpty` on paths: `Test-Path -LiteralPath ''` throws in 5.1 but returns `$false` in PowerShell 7, so tests on macOS can't catch an empty path.
5. The body. Above the final `Write-Output`, a one-line comment shows the value written; `exit 0` follows.

Scripts must be **ASCII-only**, because Windows PowerShell 5.1 reads UTF-8 without a BOM as ANSI. ~/Projects/MECM-Scripts is otherwise the style reference (README badges, CHANGELOG format); its box-drawing dividers are deliberately not copied.

## No Windows Installer provider classes

Never query `Win32_Product`, or any other class served by the MSI WMI provider (`Msi.mof`/`Msiprov.dll`), such as `Win32_SoftwareFeature`, `Win32_SoftwareElement`, `Win32_Property` or `Win32_Patch`. Enumerating them starts a Windows Installer consistency check that reconfigures every MSI product (Event ID 1035, KB 974524), and requirement scripts run on every targeted device each time the rule is evaluated. Use file versions, or `Get-CimInstance -ClassName Win32_InstalledWin32Program` (defined in `Aeinv.mof`). That class is documented for Windows clients only, so on Windows Server the scripts exit 2 by design.

## The scripts

- **`Get-AppRequirementByFile.ps1` and `Get-AppRequirementByWmi.ps1`** are generic templates. Users copy one, edit its Configuration block, and set `$OutputType` (Boolean, String, Integer for the major version, or Version) to match the rule's data type.
  - File versions always have four parts (`24.8.0.0`).
  - WMI `Version` is free text, normalized by `ConvertTo-ComparableVersion`.
- **`Select-ReportedProgram`** in the WMI script picks whose version is reported when several entries match. It reports the highest readable version, the same rule the Acrobat script uses, so *Greater than or equal to* means at least one install meets the bar. If this rule changes, change it in both scripts.
- **`Get-AdobeAcrobatRequirement.ps1`** is app-specific and always outputs an Integer: the highest installed Acrobat or Reader version, packed as `year*10000000 + release*100000 + build` (26.002.22031 → 260222031).
  - Not removing the dots: that would exceed Int32, and Intune doesn't document the width of its Integer type.
  - Only builds matching `[23]\d{4}` count (2 = Continuous track, 3 = Classic).
  - A release of 100 or more throws (exit 2) rather than emit a value that sorts wrongly.
- **`OperatingSystem/Get-OperatingSystemRequirement.ps1`** mirrors a Configuration Manager *Device › Operating system › One of* rule. `$AllowedOperatingSystems` takes the console's entry names, and the output is always Boolean.
  - Each entry matches exactly one Windows version, architecture and edition, as in Configuration Manager: Windows 10 entries don't match Windows 11, and 64-bit, ARM64 and multi-session are separate entries. Keep it exact.
  - Multi-session is `OperatingSystemSKU` 175. It reports `ProductType` 3 like Windows Server, so check the SKU before the product type.
  - Architecture comes from `Win32_Processor.Architecture` (5 or 12 means Arm) plus `[Environment]::Is64BitOperatingSystem`. Never use `Win32_OperatingSystem.OSArchitecture`, which Microsoft documents as localizable.
  - The OS test harness replaces the exact line `$is64BitOperatingSystem = [Environment]::Is64BitOperatingSystem` to simulate 32-bit Windows, and injects list overrides before the closing `# ----` divider of the configuration block. Keep both intact.
- **`Hardware/Get-ComputerModelRequirement.ps1`** works like a Configuration Manager collection query on `SMS_G_System_COMPUTER_SYSTEM.Model`, and the output is always Boolean.
  - The model is `Win32_ComputerSystem.Model`, trimmed. An empty model throws (exit 2), so neither Equals True nor Equals False matches. Don't write `False` for it: a *None of* rule would then match hardware the script couldn't identify.
  - Matching is exact and case-insensitive: `$AllowedModels -contains $computerModel`, like WQL `Model = '...'`. Wildcards were rejected as too unpredictable, so don't switch to `-like`, `-match` or substring matching; `*` and `?` in an entry stay literal.
  - `$AllowedModels` has one quoted entry per line, with no commas, so any line can be commented out. The model test harness comments out the shipped entries by their exact lines and injects list overrides before the closing `# ----` divider; keep both intact.
- **`Hardware/Get-ComputerManufacturerRequirement.ps1`** is the model script for `Win32_ComputerSystem.Manufacturer`. Keep the two in step: the same exact matching, and the same exit 2 for an empty value.
- **`Hardware/Get-ChassisTypeRequirement.ps1`** works like a collection query on `SMS_G_System_SYSTEM_ENCLOSURE.ChassisTypes`, and the output is always Boolean.
  - `$AllowedChassisTypes` lists all 36 numbers, one per line with its name as a trailing comment; commented-out lines are unselected. Selected lines are `    9       # Laptop` and unselected ones `    # 9     # Laptop`, padded so the names line up. The chassis test harness swaps these exact lines; keep the format.
  - Any reported number that is selected is a match, across the `ChassisTypes` array and across enclosures. No chassis type at all throws (exit 2).
  - The shipped selection (8, 9, 10, 14, 31, 32) is an example for laptops, including 2-in-1s; the user chose to include Convertible and Detachable. Hand Held (11), Docking Station (12) and Tablet (30) are deliberately left out.
- **`OperatingSystem/Get-OperatingSystemLanguageRequirement.ps1`** mirrors a Configuration Manager *Device › Operating system language › One of* rule, and the output is always Boolean.
  - It compares `Win32_OperatingSystem.OSLanguage` (an LCID) with the LCIDs of the culture names in `$AllowedLanguages`. Microsoft documents `OSLanguage` for the task sequence language condition only; for the application requirement this is an assumption, and the docs say so.
  - A neutral culture (`en`) or LCID 4096 throws. Windows 10 and later give any well-formed but unknown culture name LCID 4096 instead of an error, so without that check a typo would never match and never fail.
- **`ActiveDirectory/Get-ActiveDirectorySiteRequirement.ps1` and `Get-OrganizationalUnitRequirement.ps1`** mirror the *Active Directory site* and *Organizational unit (OU)* conditions, and the output is always Boolean.
  - Not domain-joined (`Win32_ComputerSystem.PartOfDomain` false) writes `False` without reading the registry: the device is known to be in no site or OU. Domain-joined with no recorded value throws (exit 2): the device couldn't be identified.
  - Both read the registry on purpose, not a domain controller (`ADSystemInfo`, `ActiveDirectorySite::GetComputerSite()`), so they work off the corporate network. Don't switch to a live lookup.
  - Read the registry with `Get-ItemProperty -LiteralPath`, which the harnesses shadow with a script-scope function. .NET registry calls can't be stubbed on macOS.
  - Site: `SiteName` wins over `DynamicSiteName` under `HKLM\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters`.
  - OU: `Distinguished-Name` under `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine`, which Microsoft doesn't document. Entries are hashtables with `OU` and `IsIncludeSubOU`, the form `New-CMRequirementRuleOUValue` takes; a missing or non-Boolean `IsIncludeSubOU` throws rather than default to `$false`. Split distinguished names only on commas not preceded by a backslash.

For version comparisons, use the Version data type. Integer fits only the major version, or a packed encoding like Acrobat's.

## Verifying changes

The test harnesses live in `Tests/`, which is gitignored: it exists only on the machine where it was created, never in a clone. Run them from the repo root:

```bash
pwsh -NoProfile -File Tests/Invoke-RequirementTests.ps1   # file and WMI scripts
pwsh -NoProfile -File Tests/Invoke-AcrobatTests.ps1       # Acrobat script, plus a check that the encoding keeps real versions in order
pwsh -NoProfile -File Tests/Invoke-OperatingSystemTests.ps1   # operating system script
pwsh -NoProfile -File Tests/Invoke-ComputerModelTests.ps1     # computer model script
pwsh -NoProfile -File Tests/Invoke-ComputerManufacturerTests.ps1      # computer manufacturer script
pwsh -NoProfile -File Tests/Invoke-ChassisTypeTests.ps1               # chassis type script
pwsh -NoProfile -File Tests/Invoke-OperatingSystemLanguageTests.ps1   # operating system language script
pwsh -NoProfile -File Tests/Invoke-ActiveDirectorySiteTests.ps1       # Active Directory site script
pwsh -NoProfile -File Tests/Invoke-OrganizationalUnitTests.ps1        # organizational unit script
pwsh -NoProfile -File Tests/Test-ScriptQuality.ps1        # lint, ASCII-only, help parses, #Requires 5.1, for every script
```

Each one prints a PASS/FAIL table and a pass count. The per-case script copies they run are written inside `Tests/`, so they're ignored too. When you add a script or change behavior, extend the harnesses. Without `Tests/`, run the same checks by hand:

**Lint.** This runs the default rules plus the Windows PowerShell 5.1 compatibility rules in one pass; a `-Settings` hashtable with only `Rules` keeps the default rule set. Expect no findings.

```bash
pwsh -NoProfile -Command '
$pssa = Get-Module -ListAvailable PSScriptAnalyzer | Sort-Object Version -Descending | Select-Object -First 1
$profiles = Get-ChildItem (Join-Path $pssa.ModuleBase "compatibility_profiles") -Filter "win-*_5.1.*framework.json" | ForEach-Object BaseName
$settings = @{ Rules = @{
    PSUseCompatibleSyntax   = @{ Enable = $true; TargetVersions = @("5.1") }
    PSUseCompatibleCommands = @{ Enable = $true; TargetProfiles = $profiles }
    PSUseCompatibleTypes    = @{ Enable = $true; TargetProfiles = $profiles } } }
Invoke-ScriptAnalyzer -Path . -Recurse -Settings $settings'
```

**ASCII check.** It prints `file:line` for each offending line, and nothing when the scripts are clean. macOS grep doesn't detect these bytes, so use perl:

```bash
find . -name '*.ps1' -exec perl -ne 'print "$ARGV:$.\n" if /[^\x00-\x7F]/; close ARGV if eof' {} +
```

**Help parses.** `pwsh -NoProfile -Command 'Get-Help ./Applications/<script>.ps1 -Full'`. If the synopsis shows only the file name, the help block wasn't recognized.

**Behavior.** Running a script directly on macOS checks little:
- `pwsh -NoProfile -File ./Applications/<script>.ps1`, then `echo $?`.
- The WMI-based scripts exit 2, because `Get-CimInstance` doesn't exist on macOS.
- The file script exits 1, because `%ProgramW6432%` isn't expanded.

To test behavior:
1. Copy the script.
2. Insert a stub `function Get-CimInstance { param($ClassName, $Property) [pscustomobject]@{ Name = '...'; Vendor = '...'; Version = '...' } }` just before the `# --- Configuration` line; a script-scope function shadows the cmdlet.
3. Replace configuration lines by their exact text, e.g. `[string]$OutputType = 'Version'`.
4. Run the copy with `pwsh -NoProfile -File` and check the exit code, that STDOUT has at most one line, and STDERR.

These tests run in PowerShell 7, so they can't catch behavior that differs only in 5.1.

## When adding or changing a script

- **README.md:** the Scripts table, the Configuration Manager global conditions table, the rule recipes, the script's own section, the Verification case counts, Repository layout, and the version badge.
- **CHANGELOG.md:** use Keep a Changelog with SemVer, and bump the README version badge to match.
- **Categories:** scripts are grouped in top-level folders, currently `ActiveDirectory/`, `Applications/`, `Hardware/` and `OperatingSystem/`. `Tests/Test-ScriptQuality.ps1` checks every `.ps1` outside `Tests/`, so a new folder is covered automatically.
