# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
