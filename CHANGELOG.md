# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.0] - 2026-11-16

### Added
- `OperatingSystem/Get-OperatingSystemLanguageRequirement.ps1` — Win32 app requirement script that mirrors a Configuration Manager *Operating system language One of* requirement rule: list culture names such as `en-US`, and the script writes `True` when `Win32_OperatingSystem.OSLanguage`, the language Windows was installed in, is one of them, otherwise `False`; a name without a region, or an unknown name, exits 2
- `ActiveDirectory/Get-OrganizationalUnitRequirement.ps1` — Win32 app requirement script that mirrors a Configuration Manager *Organizational unit (OU) One of* requirement rule: each entry takes the OU's distinguished name and `IsIncludeSubOU`, as `New-CMRequirementRuleOUValue` does; the computer's distinguished name is read from the registry value Group Policy records, so the script works off the network; a device that isn't domain-joined writes `False`
- `ActiveDirectory/Get-ActiveDirectorySiteRequirement.ps1` — Win32 app requirement script that mirrors a Configuration Manager *Active Directory site One of* requirement rule: list site names, and the script writes `True` when the site Netlogon recorded for the device (`SiteName`, else `DynamicSiteName`) is one of them, otherwise `False`; a device that isn't domain-joined writes `False`
- `Hardware/Get-ComputerManufacturerRequirement.ps1` — Win32 app requirement script that works like a collection query on `SMS_G_System_COMPUTER_SYSTEM.Manufacturer`, with the same exact, case-insensitive matching as the computer model script
- `Hardware/Get-ChassisTypeRequirement.ps1` — Win32 app requirement script that works like a collection query on `SMS_G_System_SYSTEM_ENCLOSURE.ChassisTypes`: select chassis type numbers 1 to 36 by uncommenting them, and the script writes `True` when the device reports any one of them, otherwise `False`
- README: a table mapping each built-in Configuration Manager device condition to the script, or the built-in Intune requirement rule, that replaces it

## [0.5.0] - 2026-11-12

### Added
- `Hardware/Get-ComputerModelRequirement.ps1` — Win32 app requirement script that works like a Configuration Manager collection query on `SMS_G_System_COMPUTER_SYSTEM.Model`: list the allowed models, and the script writes `True` when the device's `Win32_ComputerSystem.Model` is one of them, otherwise `False`, for any manufacturer; entries match the whole model exactly, ignoring case, with no wildcards; an empty model exits 2, so neither an Equals True nor an Equals False rule matches a device it can't identify

### Changed
- README: an overview table near the top lists every script; the file, WMI and Acrobat sections are grouped under *Application scripts*, alongside *Operating system script* and *Computer model script*; the steps for adding a rule in Intune now cover the operating system and computer model scripts too

### Fixed
- README: the WMI class audit under Verification now includes `Win32_OperatingSystem` and `Win32_Processor`, which the operating system script queries

## [0.4.0] - 2026-11-04

### Added
- `OperatingSystem/Get-OperatingSystemRequirement.ps1` — Win32 app requirement script that mirrors a Configuration Manager *Operating system One of* requirement rule: select any of All Windows 10 (32-bit, 64-bit, ARM64), All Windows 11 (64-bit, ARM64), and Windows 10 or Windows 11 Enterprise multi-session, and the script writes `True` when the device runs one of them, otherwise `False`; each entry matches exactly one Windows version, architecture and edition, as in Configuration Manager

### Changed
- README and every script's `.OUTPUTS` help now separate what Microsoft documents (Intune reads STDOUT when the exit code is 0) from what it doesn't (what a non-zero exit means for a requirement rule, which the scripts assume leaves the rule unmet)
- README links to the moved *Add and assign Win32 apps to Microsoft Intune* page

## [0.3.0] - 2026-11-03

### Added
- Integer and Version output in `Applications/Get-AppRequirementByWmi.ps1`: `Select-ReportedProgram` is implemented and reports the highest readable version when several entries match, the same rule as the Acrobat script; entries without a readable version are skipped, and the script exits 1 when none is readable

## [0.2.0] - 2026-11-03

### Added
- `Applications/Get-AdobeAcrobatRequirement.ps1` — Win32 app requirement script that reports the highest installed Adobe Acrobat or Acrobat Reader version (Continuous or Classic, 32-bit or 64-bit) as one integer, `year × 10,000,000 + release × 100,000 + build` (26.002.22031 → 260222031), for Integer *Greater than or equal to* rules; the encoding stays within 32-bit range
- `.OUTPUTS` help section in every script: the exact STDOUT for each case, the exit codes, and the Intune rule (data type, operator, value) that reads it; the Acrobat script also explains how to convert an Adobe version to the Intune value

### Fixed
- `Get-Help` ignored every script's comment-based help because `#Requires` sat directly above it; a blank line now separates them

## [0.1.0] - 2026-11-03

### Added
- `Applications/Get-AppRequirementByFile.ps1` — Win32 app requirement script that detects an app by a file path and reports Boolean, String, Integer (major version) or Version output from the file's version resource
- `Applications/Get-AppRequirementByWmi.ps1` — Win32 app requirement script that detects an app by display name and publisher in `Win32_InstalledWin32Program`, with the same four output types; never queries `Win32_Product` or any other Windows Installer provider class, which would trigger an MSI consistency check
- README covering how Intune evaluates requirement scripts, the shared output and exit-code contract, and Intune rule recipes for each output type
