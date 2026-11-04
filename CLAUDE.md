# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Intune Win32 app **requirement scripts**. Each one is a standalone Windows PowerShell 5.1 script that a user uploads as a requirement rule. The Intune Management Extension runs it on every targeted device, as SYSTEM in a 64-bit process, with no arguments. Intune reads STDOUT only when the script exits 0, and then parses it as the rule's output data type (Boolean, String, Integer, Version, ...). README.md covers the Intune side in depth: data types and operators, rule recipes, WOW64 paths, testing on a device, and sources.

Development happens on macOS with PowerShell 7.6. The scripts target Windows PowerShell 5.1, and they haven't run on Windows or under Intune yet.

## Output contract (every script)

- **Exit 0:** exactly one line on STDOUT, written with `Write-Output`.
- **Exit 1:** nothing to report (the app is missing, or its version can't be read). Intune ignores output on any non-zero exit, so a missing app never meets an Integer or Version rule under any operator. Rules that target devices without the app use Boolean Equals False. Don't replace exit 1 with a sentinel value such as `0`.
- **Exit 2:** script error. A top-level `trap` produces it; the trap is hoisted, so with `$ErrorActionPreference = 'Stop'` it catches every error in the script.
- **Diagnostics:** write them with `[Console]::Error.WriteLine(...)`. Never use `Write-Host`, `Write-Warning`, `Write-Verbose` or `Write-Information`: when Windows PowerShell runs non-interactively they can reach STDOUT and corrupt the value Intune parses.

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
- **`Select-ReportedProgram`** in the WMI script is a deliberate `TODO` that the user is implementing themselves: it picks which entry's version is reported when several match. Don't implement it unless asked. Until it exists:
  - Integer and Version output exit 2, including the shipped default `$OutputType = 'Version'`.
  - PSScriptAnalyzer reports `PSReviewUnusedParameter` for it.
- **`Get-AdobeAcrobatRequirement.ps1`** is app-specific and always outputs an Integer: the highest installed Acrobat or Reader version, packed as `year*10000000 + release*100000 + build` (26.002.22031 → 260222031).
  - Not removing the dots: that would exceed Int32, and Intune doesn't document the width of its Integer type.
  - Only builds matching `[23]\d{4}` count (2 = Continuous track, 3 = Classic).
  - A release of 100 or more throws (exit 2) rather than emit a value that sorts wrongly.

For version comparisons, use the Version data type. Integer fits only the major version, or a packed encoding like Acrobat's.

## Verifying changes

There's no test suite in the repo. These are the checks used so far.

**Lint.** This runs the default rules plus the Windows PowerShell 5.1 compatibility rules in one pass; a `-Settings` hashtable with only `Rules` keeps the default rule set. The only expected finding is the `Select-ReportedProgram` one above.

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

- **README.md:** the Scripts table, the rule recipes, the script's own section, the Verification case counts, Repository layout, and the version badge.
- **CHANGELOG.md:** use Keep a Changelog with SemVer (currently 0.2.0).
- **Categories:** `Applications/` is the only category folder so far. The README lists operating-system requirement scripts (OS version, multi-session) as planned.
