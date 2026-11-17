# IntuneRequirementScripts

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.6.0-informational.svg)](CHANGELOG.md)
[![Build](https://img.shields.io/badge/PSScriptAnalyzer-5.1%20compatible-success.svg)](#verification)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/en-us/powershell/)
[![Platform](https://img.shields.io/badge/platform-Windows-0078D6?logo=windows&logoColor=white)](https://www.microsoft.com/en-us/windows)
[![Intune](https://img.shields.io/badge/Intune-Win32%20app%20requirements-0078D4)](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32)

PowerShell requirement scripts for Intune Win32 apps. Each script writes exactly one value to STDOUT, in a form an Intune requirement rule can parse as **Boolean**, **String**, **Integer** or **Version**, so a rule can check whether an app is installed, which version it is, which operating system and language the device runs, what hardware it is, or where it sits in Active Directory.

The device scripts replicate Configuration Manager global conditions and collection queries that Intune has no built-in rule for. They take the same values Configuration Manager does, so a requirement can be carried over as it is: see [Configuration Manager global conditions in Intune](#configuration-manager-global-conditions-in-intune).

| Script | Checks |
|---|---|
| [`Applications/Get-AppRequirementByFile.ps1`](Applications/Get-AppRequirementByFile.ps1) | Whether an app is installed, or its version, by a file path |
| [`Applications/Get-AppRequirementByWmi.ps1`](Applications/Get-AppRequirementByWmi.ps1) | Whether an app is installed, or its version, by its entry in Installed apps |
| [`Applications/Get-AdobeAcrobatRequirement.ps1`](Applications/Get-AdobeAcrobatRequirement.ps1) | The installed Adobe Acrobat version, as one integer |
| [`OperatingSystem/Get-OperatingSystemRequirement.ps1`](OperatingSystem/Get-OperatingSystemRequirement.ps1) | Whether the device runs one of the selected operating systems |
| [`OperatingSystem/Get-OperatingSystemLanguageRequirement.ps1`](OperatingSystem/Get-OperatingSystemLanguageRequirement.ps1) | Whether Windows was installed in one of the selected languages |
| [`Hardware/Get-ComputerModelRequirement.ps1`](Hardware/Get-ComputerModelRequirement.ps1) | Whether the device is one of the listed computer models |
| [`Hardware/Get-ComputerManufacturerRequirement.ps1`](Hardware/Get-ComputerManufacturerRequirement.ps1) | Whether the device is from one of the listed manufacturers |
| [`Hardware/Get-ChassisTypeRequirement.ps1`](Hardware/Get-ChassisTypeRequirement.ps1) | Whether the device has one of the selected chassis types, e.g. is a laptop |
| [`ActiveDirectory/Get-ActiveDirectorySiteRequirement.ps1`](ActiveDirectory/Get-ActiveDirectorySiteRequirement.ps1) | Whether the device is in one of the listed Active Directory sites |
| [`ActiveDirectory/Get-OrganizationalUnitRequirement.ps1`](ActiveDirectory/Get-OrganizationalUnitRequirement.ps1) | Whether the device's computer account is in one of the listed OUs |

## How Intune evaluates a requirement script

The Intune Management Extension runs the script on the device: as SYSTEM, in a 64-bit Windows PowerShell 5.1 process, unless the rule says otherwise. Microsoft documents that when the script **exits with code 0**, Intune reads STDOUT and compares it, as the rule's **output data type**, with the rule's operator and value. Microsoft doesn't document what any other exit code means for a requirement rule. These scripts assume the rule isn't met, which is how Microsoft documents a non-zero exit for *detection* scripts on the same page. That's why Boolean output writes `False` with exit code 0 rather than failing: it's the only way an *Equals False* rule can match.

Every script writes diagnostics to STDERR, never STDOUT, so they can't corrupt the value Intune parses, and only when it exits non-zero. Microsoft documents that any STDERR output makes a *detection* script count as not installed, even with exit code 0. It doesn't say the same for requirement scripts, but staying silent on success avoids the question.

| Output data type | Operators | Used here for |
|---|---|---|
| String | Equals, Not equal to | `Installed` / `NotInstalled` |
| Boolean | Equals, Not equal to | `True` / `False` |
| Integer | Equals, Not equal to, Greater than, Greater than or equal to, Less than, Less than or equal to | major version, e.g. `24` |
| Version | the same six | full version, e.g. `24.8` |
| Floating Point, Date and Time | the same six | not used yet |

Graph stores the value you compare against as a string, and a Boolean as `true` or `false`.

> **Use Version, not Integer, for version checks.** An Integer holds one whole number, so it can't represent `24.08` or `124.0.6367.91`. Integer is useful when only the major version matters.

## Configuration Manager global conditions in Intune

Configuration Manager's built-in device conditions, and what replaces each one on an Intune Win32 app:

| Configuration Manager condition | In Intune |
|---|---|
| Active Directory site | [`Get-ActiveDirectorySiteRequirement.ps1`](#active-directory-site-script) |
| Organizational unit (OU) | [`Get-OrganizationalUnitRequirement.ps1`](#organizational-unit-script) |
| Operating system | [`Get-OperatingSystemRequirement.ps1`](#operating-system-script). Intune's built-in **Operating system architecture** and **Minimum operating system** rules cover simpler cases |
| Operating system language | [`Get-OperatingSystemLanguageRequirement.ps1`](#operating-system-language-script) |
| Disk space | Built-in rule: **Disk space required (MB)** |
| Total physical memory | Built-in rule: **Physical memory required (MB)** |
| Number of processors | Built-in rule: **Minimum number of logical processors required** |
| CPU speed | Built-in rule: **Minimum CPU speed required (MHz)** |
| Configuration Manager site | No script: it applies only to Configuration Manager clients |

The built-in Intune rules are minimums, where Configuration Manager lets you pick an operator; no script here covers the other operators. The computer model, manufacturer and chassis type scripts have no global condition behind them: they replace collection queries on hardware inventory, the usual way to limit a Configuration Manager deployment by hardware.

## Adding a rule in Intune

1. Copy the script and give the copy a name that identifies the app and check, e.g. `Req-7Zip-Version.ps1`.
2. Edit its configuration block: the file path or name pattern and `$OutputType` for an application script, or the one list of allowed values in a device script, such as `$AllowedOperatingSystems` or `$AllowedModels`.
3. In the app's **Requirements** page, under **Configure additional requirement rules**, select **Add**, set **Requirement type** to **Script**, and upload the copy.
4. Set the rule:
   - **Run script as 32-bit process on 64-bit clients**: No
   - **Run this script using the logged on credentials**: No
   - **Enforce script signature check**: No, unless you sign the script
   - **Select output data type**: the type the script writes, then the operator and value. The script's section below gives them for common requirements, and its `.OUTPUTS` help section repeats them, so the guidance travels with the script.

## Application scripts

| Script | Detects the app by | Version comes from |
|---|---|---|
| [`Get-AppRequirementByFile.ps1`](Applications/Get-AppRequirementByFile.ps1) | A file path | The file's version resource |
| [`Get-AppRequirementByWmi.ps1`](Applications/Get-AppRequirementByWmi.ps1) | Display name and publisher in `Win32_InstalledWin32Program` | The version text listed in Installed apps |
| [`Get-AdobeAcrobatRequirement.ps1`](Applications/Get-AdobeAcrobatRequirement.ps1) | Any Adobe Acrobat product in `Win32_InstalledWin32Program` | Adobe's version, packed into one integer: see [Adobe Acrobat script](#adobe-acrobat-script) |

### Output and exit codes

The file and WMI scripts write the type set by `$OutputType` in the configuration block. The Acrobat script always writes an Integer.

| `$OutputType` | Installed | Not installed |
|---|---|---|
| `Boolean` | `True` | `False` |
| `String` | `Installed` | `NotInstalled` |
| `Integer` | Major version, e.g. `24` | No output, exit 1 |
| `Version` | Version, e.g. `24.8.0.0` | No output, exit 1 |

| Exit code | Meaning |
|---|---|
| 0 | A value was written to STDOUT |
| 1 | Nothing to report: the app isn't installed, or (WMI script) no matching entry has a number in its version text |
| 2 | Script error: invalid configuration, or the WMI class isn't available |

**A missing app gives an Integer or Version rule nothing to compare.** The script exits 1 and writes nothing, so, given the assumption under [How Intune evaluates a requirement script](#how-intune-evaluates-a-requirement-script), the rule isn't met whatever the operator. That keeps *Less than 24.8* aimed at devices with an old install, not at devices without the app. To target devices without the app, use Boolean *Equals False*: the script exits 0 with `False`, the case Microsoft documents.

### Example rules

For the file and WMI scripts:

| Requirement | `$OutputType` | Output data type | Operator | Value |
|---|---|---|---|---|
| App is installed | `Boolean` | Boolean | Equals | True |
| App isn't installed | `Boolean` | Boolean | Equals | False |
| App is installed | `String` | String | Equals | `Installed` |
| Version 24.8 or later | `Version` | Version | Greater than or equal to | `24.8` |
| Older than 24.8, e.g. to target an upgrade | `Version` | Version | Less than | `24.8` |
| Major version 24 or later | `Integer` | Integer | Greater than or equal to | `24` |

Enter a Version value with as many parts as the script writes. The file script always writes four (`24.8.0.0`). The WMI script writes the version as Installed apps shows it (`24.8`), so run it once on a device to see the exact form.

### File script: paths and 32-bit processes

`$FilePath` expands environment variables, and a 32-bit process on 64-bit Windows sees different values for some of them:

| Variable | 64-bit process | 32-bit process |
|---|---|---|
| `%ProgramFiles%` | `C:\Program Files` | `C:\Program Files (x86)` |
| `%ProgramW6432%` | `C:\Program Files` | `C:\Program Files` |
| `%ProgramFiles(x86)%` | `C:\Program Files (x86)` | `C:\Program Files (x86)` |

Use `%ProgramW6432%` for a 64-bit app and `%ProgramFiles(x86)%` for a 32-bit app, and the path stays correct however the rule runs. `%ProgramW6432%` doesn't exist on 32-bit Windows.

The version is the four-part numeric file version, so `Version` output always has four parts, e.g. `24.8.0.0`. A file without a version resource reports `0.0.0.0`.

### WMI script: why `Win32_InstalledWin32Program`

**No Windows Installer provider classes.** A `Win32_Product` query makes WMI use the Windows Installer (MSI) provider to enumerate every installed product, and that starts a consistency check: Windows Installer reconfigures each product and logs Event ID 1035 for each one (KB 974524). A requirement rule runs on every device the app targets, every time it's evaluated. The same provider (`Msi.mof`, `Msiprov.dll`) also serves `Win32_SoftwareFeature`, `Win32_SoftwareElement`, `Win32_InstalledSoftwareElement`, `Win32_ProductSoftwareFeatures`, `Win32_Property`, `Win32_Patch`, `Win32_PatchPackage` and dozens more. Keep every class from that provider out of these scripts.

`Win32_InstalledWin32Program` (`root\cimv2`) is defined in `Aeinv.mof`, not the MSI provider, and it isn't in that provider's class list. It lists installed Win32 apps with `Name`, `Vendor`, `Version` and `MsiProductCode`. Microsoft doesn't state outright that it never triggers a check, so confirm it on a device with the Event ID 1035 check under [Testing on a device](#testing-on-a-device). Microsoft documents the class for **Windows clients only**, so on Windows Server the query fails and the script exits 2.

- `$NamePattern` matches the display name shown in **Settings › Apps › Installed apps**, using `-like` wildcards. Make it specific, e.g. `Java 8 Update*` rather than `Java*`, so companion entries such as updaters don't match.
- `Version` is free text. The script keeps the leading number (`24.08` → `24.8`, `1.2.3 build 7` → `1.2.3`), pads a one-part version (`5` → `5.0`), and exits 1 if there's no number at all. Enter the Intune value in the same form, e.g. `24.8`.
- Several entries can match one pattern, such as x86 and x64 builds side by side. The script reports the highest readable version, as the Acrobat script does, so *Greater than or equal to* is met when at least one install meets it, and *Less than* only when every readable install is older. Entries whose version text has no number are skipped.
- The script runs as SYSTEM. If an app installs per user, test whether the class lists it before relying on the rule.

### Adobe Acrobat script

`Get-AdobeAcrobatRequirement.ps1` reports the installed Acrobat version as one **Integer**, for a rule such as *Integer, Greater than or equal to, 260222031*. It considers every product whose name starts with *Adobe Acrobat* from a publisher starting with *Adobe*: Acrobat and Acrobat Reader, Continuous and Classic tracks, 32-bit and 64-bit. When several are installed, it reports the highest version. It uses `Win32_InstalledWin32Program` like the WMI script, so the same Windows Installer and Windows Server notes apply.

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

With no Acrobat product installed, the script exits 1 and writes nothing, so expect neither rule to match. See [How Intune evaluates a requirement script](#how-intune-evaluates-a-requirement-script) for what Microsoft documents about exit codes.

**Why not just remove the dots?** `2600222031` is larger than 2,147,483,647, the largest 32-bit integer, and Intune doesn't document whether Integer output is 32-bit. If it is, that number would fail to parse on every device and the rule would never match. The packed form stays below 1,000,000,000. It relies on the release being below 100, which Adobe's releases always have been; a release of 100 or more makes the script exit 2 rather than report a number that sorts wrongly.

- Entries whose version isn't in Adobe's format are ignored, so an add-in listed under an Acrobat name doesn't count. If only such entries match, the script exits 1 and STDERR lists what it found.
- Compare within one track. Inside a track, the integers sort exactly as the versions do. Across tracks they sort by year and release first.
- To limit the rule to fewer products, narrow `$NamePattern`, e.g. `Adobe Acrobat Reader*`.

## Operating system script

`Get-OperatingSystemRequirement.ps1` works like a Configuration Manager requirement rule with **Device › Operating system › One of**. List the allowed operating systems in `$AllowedOperatingSystems`, using the names Configuration Manager shows under Windows 10 and Windows 11. The script writes `True` when the device runs one of them, and `False` otherwise. Commenting out a line leaves that entry unselected, like clearing its check box:

```powershell
[string[]]$AllowedOperatingSystems = @(
    # 'All Windows 10 (32-bit)'
    'All Windows 10 (64-bit)'
    # 'All Windows 10 (ARM64)'
    # 'Windows 10 Enterprise multi-session'
    'All Windows 11 (64-bit)'
    # 'All Windows 11 (ARM64)'
    # 'Windows 11 Enterprise multi-session'
)
```

| Entry | Matches devices running |
|---|---|
| `All Windows 10 (32-bit)` | Windows 10, 32-bit |
| `All Windows 10 (64-bit)` | Windows 10, 64-bit (x64) |
| `All Windows 10 (ARM64)` | Windows 10 on Arm |
| `Windows 10 Enterprise multi-session` | Windows 10 Enterprise multi-session |
| `All Windows 11 (64-bit)` | Windows 11, 64-bit (x64) |
| `All Windows 11 (ARM64)` | Windows 11 on Arm |
| `Windows 11 Enterprise multi-session` | Windows 11 Enterprise multi-session |

| Requirement | Output data type | Operator | Value |
|---|---|---|---|
| Device runs one of the selected operating systems (Configuration Manager *One of*) | Boolean | Equals | True |
| Device runs none of them (Configuration Manager *None of*) | Boolean | Equals | False |

The script always exits 0 with `True` or `False`, except on a script error (exit 2), such as a misspelled entry or an empty list.

**Each entry covers exactly one Windows version, architecture and edition**, as in Configuration Manager:

- **Multi-session and Arm need their own entries.** Microsoft documents that selecting the Windows 10 platform doesn't add Windows 10 Enterprise multi-session, which you select separately, and that apps limited to the other Windows 10 entries don't reach Windows 10 ARM64 devices until **All Windows 10 (ARM64)** is selected.
- **Windows 10 entries don't match Windows 11.** Microsoft doesn't state this outright, but a published migration report shows apps limited to Windows 10 not deploying to Windows 11 devices. To allow both, select both.
- **Windows Server, and Windows before Windows 10, never match.** There are no entries for them.

How the script identifies the device, with `Get-CimInstance` in `root\cimv2` and no Windows Installer classes:

| Property | Meaning |
|---|---|
| `Win32_OperatingSystem.Version` 10.0 | Windows 10 or 11: build 22000 or later is Windows 11 |
| `Win32_OperatingSystem.OperatingSystemSKU` 175 | Windows Enterprise multi-session (Enterprise for Virtual Desktops) |
| `Win32_OperatingSystem.ProductType` 1 | Any other Windows client. Multi-session reports 3, like Windows Server, so the SKU is checked first |
| `Win32_Processor.Architecture` 12 (ARM64) or 5 (ARM) | Arm, where Windows 10 and 11 are 64-bit only |
| `[Environment]::Is64BitOperatingSystem` | 64-bit or 32-bit Windows on Intel and AMD processors, also from a 32-bit process |

`Win32_OperatingSystem.OSArchitecture` would be simpler, but Microsoft documents it as localizable, so the script doesn't use it. Unlike the WMI-based application scripts, this script also runs on Windows Server, where it reports `False`.

The entry names follow Microsoft's documentation and a published console example. Your console may word an entry slightly differently; only the names in the script's list are accepted.

## Operating system language script

`Get-OperatingSystemLanguageRequirement.ps1` works like a Configuration Manager requirement rule with **Device › Operating system language › One of**. List the allowed languages in `$AllowedLanguages` by culture name, the `Name` that Microsoft's `New-CMRequirementRuleOperatingSystemLanguageValue` cmdlet filters cultures by. The script writes `True` when Windows was installed in one of them, and `False` otherwise:

```powershell
[string[]]$AllowedLanguages = @(
    'en-US'
    'en-GB'
)
```

| Requirement | Output data type | Operator | Value |
|---|---|---|---|
| Installed in one of the selected languages (Configuration Manager *One of*) | Boolean | Equals | True |
| Installed in none of them (Configuration Manager *None of*) | Boolean | Equals | False |

The script exits 0 with `True` or `False`, except on a script error (exit 2): an unknown culture name, a name without a region, or an empty list.

- **It checks the language Windows was installed in, not the display language.** The script reads `Win32_OperatingSystem.OSLanguage`, a language code identifier such as 1033 for `en-US`. A device installed in English (United States) that shows Windows in German through a language pack still reports `en-US`.
- **Microsoft doesn't document which value Configuration Manager's application requirement reads.** It does document that a task sequence's operating system language condition compares against `OSLanguage`, so the script uses the same property. If your Configuration Manager rule behaved differently on devices with language packs, expect this script to differ there.
- **Each entry is one language and region.** `en-US` doesn't match `en-GB`, and `en` alone is rejected, because `OSLanguage` never reports a language without a region.

To read the value on a device as a culture name:

```powershell
[cultureinfo]::GetCultureInfo([int](Get-CimInstance -ClassName Win32_OperatingSystem).OSLanguage).Name
```

## Computer model script

`Get-ComputerModelRequirement.ps1` works like a Configuration Manager collection query on `SMS_G_System_COMPUTER_SYSTEM.Model`. List the allowed models in `$AllowedModels`, and the script writes `True` when the device's model is one of them, and `False` otherwise. It compares only the model string, so the same script works for any manufacturer. Put each model on its own line in quotes; commenting out a line drops that model:

```powershell
[string[]]$AllowedModels = @(
    'Latitude 5440'
    'Latitude 7440'
    'HP EliteBook 840 G10 Notebook PC'
    'Surface Laptop 5'
)
```

The shipped entries are examples; replace them with the models the app supports. Leave out commas between lines: with them, commenting out the last entry leaves a trailing comma, and the script no longer parses.

**Entries match exactly.** A device matches an entry only when its whole `Model` value is the same, ignoring case, as in a WQL `Model = '...'` query. There are no wildcards: `*` and `?` are ordinary characters, so `'Latitude 54*'` doesn't match *Latitude 5440*, and `'Latitude 5440'` doesn't match *Latitude 5440 2-in-1*. List every model in full, exactly as the device reports it.

| Requirement | Output data type | Operator | Value |
|---|---|---|---|
| Device is one of the listed models | Boolean | Equals | True |
| Device is none of the listed models, e.g. to keep the app off hardware it doesn't support | Boolean | Equals | False |

The script exits 0 with `True` or `False`, except on a script error (exit 2): an empty list or entry, a failed WMI query, or a `Model` that's empty. A device whose model can't be read therefore meets neither rule, rather than matching *Equals False*.

**Finding the model string.** The script reads `Win32_ComputerSystem.Model` from `root\cimv2`, the property Configuration Manager hardware inventory collects as `SMS_G_System_COMPUTER_SYSTEM.Model`, so the values in your collection queries and Resource Explorer work as they are. To read it on a device:

```powershell
(Get-CimInstance -ClassName Win32_ComputerSystem).Model
```

- Leading and trailing spaces, which some manufacturers pad the value with, are removed before comparing.
- Lenovo reports the machine type in `Model`, e.g. `20XW003JUS`, and keeps the product name, e.g. *ThinkPad X1 Carbon Gen 9*, in `Win32_ComputerSystemProduct.Version`, which this script doesn't read. List each Lenovo machine type exactly as `Model` reports it: the shorter `20XW` doesn't match `20XW003JUS`.
- Self-built and some white-label devices report placeholders such as *System Product Name*. Don't list those: every such device would match.

Like the operating system script, this one also runs on Windows Server, and it queries no Windows Installer classes.

## Computer manufacturer script

`Get-ComputerManufacturerRequirement.ps1` is the computer model script for `SMS_G_System_COMPUTER_SYSTEM.Manufacturer`. List the allowed manufacturers in `$AllowedManufacturers`, and the script writes `True` when the device's `Win32_ComputerSystem.Manufacturer` is one of them, and `False` otherwise:

```powershell
[string[]]$AllowedManufacturers = @(
    'Dell Inc.'
    'HP'
    'Hewlett-Packard'
    'LENOVO'
    'Microsoft Corporation'
)
```

Everything about matching is the same as in the [computer model script](#computer-model-script): whole string, ignoring case, no wildcards, spaces trimmed, and an empty value exits 2 so the device meets neither rule. One vendor can report several names across product generations, such as `HP` and `Hewlett-Packard`, so list every name your devices report.

| Requirement | Output data type | Operator | Value |
|---|---|---|---|
| Device is from one of the listed manufacturers | Boolean | Equals | True |
| Device is from none of them | Boolean | Equals | False |

```powershell
(Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
```

## Chassis type script

`Get-ChassisTypeRequirement.ps1` works like a Configuration Manager collection query on `SMS_G_System_SYSTEM_ENCLOSURE.ChassisTypes`, the usual way to tell laptops from desktops. `$AllowedChassisTypes` lists every chassis type number with its name; uncomment a line to select it, like ticking a check box. The script writes `True` when the device reports any selected number, and `False` otherwise:

```powershell
[int[]]$AllowedChassisTypes = @(
    # 3     # Desktop
    8       # Portable
    9       # Laptop
    10      # Notebook
    # 13    # All in One
    14      # Sub Notebook
    # 30    # Tablet
    31      # Convertible
    32      # Detachable
    # ... all 36 numbers are in the script
)
```

The shipped selection is an example for laptops. Commonly used groups, to adjust for your hardware:

| Group | Numbers |
|---|---|
| Laptops | 8, 9, 10, 14, 31, 32 (the shipped selection) |
| Tablets | 11, 30 |
| Desktops | 3, 4, 5, 6, 7, 13, 15, 16, 35 |
| Servers | 17, 23, 28 |

| Requirement | Output data type | Operator | Value |
|---|---|---|---|
| Device has one of the selected chassis types | Boolean | Equals | True |
| Device has none of them | Boolean | Equals | False |

The script exits 0 with `True` or `False`, except on a script error (exit 2): an empty list, a number outside 1 to 36, a failed WMI query, or a device that reports no chassis type.

- `Win32_SystemEnclosure.ChassisTypes` is an array, and a device can have more than one enclosure. Any selected number among them is a match, as a WQL `ChassisTypes in (...)` query matches any enclosure.
- The number is whatever the manufacturer wrote to the firmware. Virtual machines often report 1 (Other) or 3 (Desktop), and small desktops report 3, 15 or 35 depending on the vendor, so check real devices first.
- Microsoft's `Win32_SystemEnclosure` page names 1 to 24 and 30 to 32. The names for 25 to 29 and 33 to 36 are from the DMTF SMBIOS specification.

```powershell
(Get-CimInstance -ClassName Win32_SystemEnclosure).ChassisTypes
```

## Active Directory scripts

Both scripts are for devices joined to an on-premises Active Directory domain, including Microsoft Entra hybrid joined devices. A device that isn't domain-joined, such as a Microsoft Entra joined device, is in no site and no OU, so both write `False`: an *Equals False* rule matches it.

**Both read the registry, not a domain controller**, so they also work when the device is away from the corporate network. The cost is that the value can be out of date:

| Script | Registry value | Updated |
|---|---|---|
| Site | `SiteName`, else `DynamicSiteName`, in `HKLM\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters` | When Netlogon rediscovers the site, which needs a domain controller |
| OU | `Distinguished-Name` in `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine` | At each computer Group Policy refresh that reaches a domain controller |

Neither key is redirected for 32-bit processes, so the rule's 32-bit setting doesn't change the result. A domain-joined device with no value recorded exits 2 and meets neither rule.

### Active Directory site script

`Get-ActiveDirectorySiteRequirement.ps1` works like a Configuration Manager requirement rule with **Device › Active Directory site › One of**. List the site names in `$AllowedSites`:

```powershell
[string[]]$AllowedSites = @(
    'London'
    'Wells'
)
```

| Requirement | Output data type | Operator | Value |
|---|---|---|---|
| Device is in one of the listed sites (Configuration Manager *One of*) | Boolean | Equals | True |
| Device is in none of them, or isn't domain-joined (Configuration Manager *None of*) | Boolean | Equals | False |

- Site names match whole, ignoring case, with no wildcards.
- `SiteName` is the site an administrator assigned, by policy or by hand, and it wins when it has a value. Otherwise the script uses `DynamicSiteName`, the site Netlogon discovered. Microsoft doesn't spell out that order in one place, so check a device that has both.
- A laptop taken off the network keeps reporting the site of the office it last connected from. That makes this script a poor test of where a device *is*; it tells you the site it last belonged to.

To read the site on a device: `nltest /dsgetsite`.

### Organizational unit script

`Get-OrganizationalUnitRequirement.ps1` works like a Configuration Manager requirement rule with **Device › Organizational unit (OU) › One of**. Each entry in `$AllowedOrganizationalUnits` is a hashtable in the form Microsoft's `New-CMRequirementRuleOUValue` cmdlet takes: the OU's distinguished name, and whether to include its child OUs.

```powershell
[hashtable[]]$AllowedOrganizationalUnits = @(
    @{ OU = 'OU=Workstations,DC=contoso,DC=com'; IsIncludeSubOU = $true }
    @{ OU = 'OU=Kiosks,OU=Shared Devices,DC=contoso,DC=com'; IsIncludeSubOU = $false }
)
```

| `IsIncludeSubOU` | The computer account matches when it is |
|---|---|
| `$false` | Directly in that OU |
| `$true` | In that OU, or in any OU below it |

| Requirement | Output data type | Operator | Value |
|---|---|---|---|
| Device is in one of the listed OUs (Configuration Manager *One of*) | Boolean | Equals | True |
| Device is in none of them, or isn't domain-joined (Configuration Manager *None of*) | Boolean | Equals | False |

The script exits 2 on an empty list, or an entry without both settings: a missing or misspelled `IsIncludeSubOU` is an error, not a silent `$false`.

- Distinguished names are compared whole, ignoring case and spaces around the commas between their parts. A comma inside a name, written `\,`, is handled. A container such as `CN=Computers,DC=contoso,DC=com` works like an OU.
- The device's OU is its recorded distinguished name without the first part, the computer's own `CN`.
- **Microsoft doesn't document the `Distinguished-Name` registry value.** Confirm it on your devices before relying on the rule. After a computer account moves, the value changes at the next Group Policy refresh that reaches a domain controller.

```powershell
(Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine').'Distinguished-Name'
```

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

- **PSScriptAnalyzer 1.25**: default rules, plus the compatibility rules for Windows PowerShell 5.1 (Windows 10 1607 and 1809, Windows Server 2019 profiles). No findings.
- **WMI class audit**: every WMI call in the repository is `Get-CimInstance` on `Win32_InstalledWin32Program`, `Win32_OperatingSystem`, `Win32_Processor`, `Win32_ComputerSystem` or `Win32_SystemEnclosure`. No script uses a Windows Installer provider class.
- **25 file and WMI script cases**, covering every `$OutputType`, missing and present apps, several matching entries (highest version wins, compared as numbers, unreadable entries skipped), configuration errors and a missing WMI class.
- **13 Acrobat cases**, covering both tracks, unpadded and four-part versions, several products installed together, add-ins, a wrong publisher, a release of 100, and a missing WMI class. Plus a check that the integer keeps eight real versions from Adobe's release notes in order.
- **31 operating system cases**, covering every entry, both Windows 10 and 11 boundaries (builds 21996 and 22000), 32-bit Windows on a 64-bit processor, Arm reported as ARM or ARM64, multi-session against 64-bit entries, Windows Server, domain controllers, Windows 8.1, misspelled entries and an empty list.
- **24 computer model cases**, covering listed and unlisted models, models that are a prefix of an entry or longer than one, entries containing `*` or `?` (matched literally, not as wildcards), padded and differently cased `Model` values, a Lenovo machine type and its prefix, a commented-out entry, an empty, blank or null `Model`, an empty list or entry, and a failed WMI query.
- **21 operating system language cases**, covering listed and unlisted languages, regions of one language told apart (`de-DE` and `de-AT`, `zh-CN` and `zh-TW`), a name without a region, an unknown name, a display name in place of a culture name, a commented-out entry, an empty list or entry, a missing `OSLanguage`, and a failed WMI query.
- **21 computer manufacturer cases**, mirroring the computer model cases: listed and unlisted manufacturers, prefixes and longer strings, `*` and `?` matched literally, padded and differently cased values, a commented-out entry, an empty, blank or null value, an empty list or entry, and a failed WMI query.
- **30 chassis type cases**, covering the shipped selection, a desktop selection, the lowest and highest numbers, several values in one array and several enclosures, an enclosure without a value, commented-out and uncommented lines, numbers outside 1 to 36, an empty list, a device reporting no chassis type, and a failed WMI query.
- **23 Active Directory site cases**, covering listed and unlisted sites, an assigned site overriding the discovered one, an empty assigned site, differently cased and padded names, a device that isn't domain-joined (with stale or unreadable registry data), a domain-joined device with no site, a missing registry key, an empty list or entry, and a failed WMI query.
- **35 organizational unit cases**, covering an OU with and without child OUs, child and grandchild OUs, parents, look-alike OU names, other domains and child domains, a container, the domain root, case and spacing differences, escaped commas, several entries, a device that isn't domain-joined, a missing, blank or parentless distinguished name, a missing registry key, and entries with a missing, misspelled or non-Boolean setting.

The cases run in PowerShell 7.6 with `Get-CimInstance` and, for the Active Directory scripts, `Get-ItemProperty` stubbed, because the test machine has no WMI or registry. No script has run on a Windows device yet.

## Repository layout

```
IntuneRequirementScripts/
├── ActiveDirectory/
│   ├── Get-ActiveDirectorySiteRequirement.ps1   Device is in one of the listed AD sites
│   └── Get-OrganizationalUnitRequirement.ps1    Computer account is in one of the listed OUs
├── Applications/
│   ├── Get-AdobeAcrobatRequirement.ps1      Adobe Acrobat version as one integer
│   ├── Get-AppRequirementByFile.ps1         App present / version, by file
│   └── Get-AppRequirementByWmi.ps1          App present / version, by Win32_InstalledWin32Program
├── Hardware/
│   ├── Get-ChassisTypeRequirement.ps1           Device has one of the selected chassis types
│   ├── Get-ComputerManufacturerRequirement.ps1  Device is from one of the listed manufacturers
│   └── Get-ComputerModelRequirement.ps1         Device is one of the listed computer models
└── OperatingSystem/
    ├── Get-OperatingSystemLanguageRequirement.ps1   Windows was installed in one of the selected languages
    └── Get-OperatingSystemRequirement.ps1           Device runs one of the selected operating systems
```

## Sources

Checked on November 3, 2026, the computer model sources on November 12, 2026, and the language, chassis type and Active Directory sources on November 16, 2026:

- [Add and assign Win32 apps to Microsoft Intune](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32) — requirement rule settings; STDOUT is read when the exit code is 0 (the page doesn't say what another exit code means for a requirement rule); for detection scripts, a non-zero exit or any STDERR output means not installed
- [win32LobAppPowerShellScriptRequirement](https://learn.microsoft.com/en-us/graph/api/resources/intune-apps-win32lobapppowershellscriptrequirement?view=graph-rest-1.0), [detection type](https://learn.microsoft.com/en-us/graph/api/resources/intune-apps-win32lobapppowershellscriptdetectiontype?view=graph-rest-1.0) and [operator](https://learn.microsoft.com/en-us/graph/api/resources/intune-apps-win32lobappdetectionoperator?view=graph-rest-1.0) — output data types and operators
- [IntuneWin32App `New-IntuneWin32AppRequirementRuleScript`](https://www.powershellgallery.com/packages/IntuneWin32App/1.5.0/Content/Public%5CNew-IntuneWin32AppRequirementRuleScript.ps1) — operators allowed per type; Boolean stored as `true`/`false`
- [Troubleshoot Win32 app issues](https://learn.microsoft.com/en-us/intune/intune-service/apps/apps-win32-troubleshoot) — log locations
- [Win32_InstalledWin32Program class](https://learn.microsoft.com/en-us/windows/win32/wmisdk/win32-installedwin32program)
- [Windows Installer reconfigured all installed applications (KB 974524)](https://learn.microsoft.com/en-us/troubleshoot/windows-server/admin-development/windows-installer-reconfigured-all-applications)
- [WOW64 implementation details](https://learn.microsoft.com/en-us/windows/win32/winprog64/wow64-implementation-details) — environment variables in 32-bit and 64-bit processes
- [Adobe Acrobat release notes](https://www.adobe.com/devnet-docs/acrobatetk/tools/ReleaseNotesDC/index.html) — current version numbers for each track
- [Supported clients and devices for Configuration Manager](https://learn.microsoft.com/en-us/intune/configmgr/core/plan-design/configs/supported-operating-systems-for-clients-and-devices) — Windows 10 and Windows 11 Enterprise multi-session platforms, selected separately from their parent platform
- [Support for Windows 11 in Configuration Manager](https://learn.microsoft.com/en-us/intune/configmgr/core/plan-design/configs/support-for-windows-11) — build 22000 or later is Windows 11; the All Windows 11 (ARM64) platform
- [Applications aren't deployed to Windows 10 ARM64 devices](https://support.microsoft.com/help/4338726) — All Windows 10 (ARM64) must be selected explicitly
- [`New-CMRequirementRuleOperatingSystemValue`](https://learn.microsoft.com/en-us/powershell/module/configurationmanager/new-cmrequirementruleoperatingsystemvalue?view=sccm-ps) — *One of* / *None of* operating system rules and platform names
- [Windows 11 operating system requirement in Configuration Manager (Alkane Solutions)](https://www.alkanesolutions.co.uk/2025/03/14/windows-11-operating-system-requirement-in-configuration-manager/) — console names such as *All Windows 10 (64-bit)*; apps limited to Windows 10 not deploying to Windows 11
- [Windows Enterprise multi-session FAQ](https://learn.microsoft.com/en-us/azure/virtual-desktop/windows-multisession-faq) — multi-session reports ProductType 3, like Windows Server
- [Configure automatic updates for Azure Virtual Desktop session hosts](https://learn.microsoft.com/en-us/azure/virtual-desktop/configure-automatic-updates) — OperatingSystemSKU 175 for Windows 10 and 11 Enterprise multi-session
- [Win32_OperatingSystem](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-operatingsystem) and [Win32_Processor](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-processor) — ProductType, OperatingSystemSKU, localizable OSArchitecture, and processor Architecture values
- [Win32_ComputerSystem](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-computersystem) — the Model property
- [Computer make and model with Lenovo real models](https://learn.microsoft.com/en-us/archive/blogs/alex_semi/computer-make-model-with-lenovo-real-models) — Lenovo keeps the product name in `Win32_ComputerSystemProduct.Version`, not `Win32_ComputerSystem.Model`
- [Document Cloud tracks explained: Continuous vs Classic](https://community.adobe.com/t5/acrobat-reader-discussions/document-cloud-tracks-explained-quot-continuous-quot-vs-quot-classic-quot/td-p/7226460) — the track digit in the build number
- [`New-CMRequirementRuleOperatingSystemLanguageValue`](https://learn.microsoft.com/en-us/powershell/module/configurationmanager/new-cmrequirementruleoperatingsystemlanguagevalue?view=sccm-ps) — *One of* / *None of* operating system language rules, with cultures chosen by name such as `en-US`
- [`New-CMTSStepConditionOperatingSystemLanguage`](https://learn.microsoft.com/en-us/powershell/module/configurationmanager/new-cmtsstepconditionoperatingsystemlanguage?view=sccm-ps) — a task sequence compares its language condition with `Win32_OperatingSystem.OSLanguage`
- [`New-CMRequirementRuleOUValue`](https://learn.microsoft.com/en-us/powershell/module/configurationmanager/new-cmrequirementruleouvalue?view=sccm-ps) — the `OU` and `IsIncludeSubOU` hashtable, and *One of* / *None of* OU rules
- [`New-CMRequirementRuleActiveDirectorySiteValue`](https://learn.microsoft.com/en-us/powershell/module/configurationmanager/new-cmrequirementruleactivedirectorysitevalue?view=sccm-ps) — *One of* / *None of* Active Directory site rules by site name
- [Win32_SystemEnclosure](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-systemenclosure) — `ChassisTypes` is an array from SMBIOS; names for values 1 to 24 and 30 to 32
- [Registry keys affected by WOW64](https://learn.microsoft.com/en-us/windows/win32/winprog64/shared-registry-keys) — `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy` is shared, and `HKLM\SYSTEM` isn't among the redirected keys
- [MS-NRPC abstract data model](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-nrpc/b8d168ac-ebb6-42f4-bfb2-7a84377f2cbc) — `DynamicSiteName`, the dynamically determined site name of the computer

## License

[MIT](LICENSE)
