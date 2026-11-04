#Requires -Version 5.1

<#
.SYNOPSIS
    Intune Win32 app requirement script: checks whether the device runs one of the selected operating systems.

.DESCRIPTION
    Mirrors a Configuration Manager requirement rule with Category Device, Condition
    Operating system and the One of operator. Select the allowed operating systems in the
    Configuration block, by the names Configuration Manager lists under Windows 10 and
    Windows 11. The script writes True when the device runs any one of them, and False
    otherwise.

    As in Configuration Manager, each entry covers one Windows version, architecture and
    edition, and nothing else:

      Device                                   Entry it matches
      ---------------------------------------  -----------------------------------
      Windows 10, 32-bit                       All Windows 10 (32-bit)
      Windows 10, 64-bit                       All Windows 10 (64-bit)
      Windows 10 on Arm                        All Windows 10 (ARM64)
      Windows 10 Enterprise multi-session      Windows 10 Enterprise multi-session
      Windows 11, 64-bit                       All Windows 11 (64-bit)
      Windows 11 on Arm                        All Windows 11 (ARM64)
      Windows 11 Enterprise multi-session      Windows 11 Enterprise multi-session
      Windows Server, or Windows before 10     none, so the result is always False

    A Windows 10 entry doesn't match Windows 11, and a 64-bit entry doesn't match Arm or
    multi-session devices. Select every entry you want to allow.

    How the device is identified, with Get-CimInstance in root\cimv2:
      - Windows 10 or 11: Win32_OperatingSystem.Version 10.0. Build 22000 or later is
        Windows 11.
      - Multi-session: Win32_OperatingSystem.OperatingSystemSKU 175, Windows Enterprise
        for Virtual Desktops. Multi-session reports ProductType 3, the same as Windows
        Server, so the SKU is checked before the product type.
      - Other Windows clients: ProductType 1, Work Station.
      - Architecture: Win32_Processor.Architecture 12 (ARM64) or 5 (ARM) means Arm,
        where Windows 10 and 11 are 64-bit only. Otherwise
        [Environment]::Is64BitOperatingSystem tells 64-bit from 32-bit Windows, also in
        a 32-bit process. Win32_OperatingSystem.OSArchitecture isn't used, because
        Microsoft documents it as localizable.

    No Windows Installer provider class is queried, so the script can't start an MSI
    consistency check.

.OUTPUTS
    WHAT INTUNE SHOULD EXPECT

    One line on STDOUT:

      On the device                                  STDOUT    Exit code
      ---------------------------------------------  --------  ---------
      One of the selected operating systems          True      0
      Any other operating system                     False     0
      Script error, e.g. a misspelled entry name     (none)    2

    False is written with exit code 0 because Microsoft documents that Intune reads
    STDOUT when the exit code is 0; that is what lets an Equals False ("None of") rule
    match. Microsoft doesn't document what exit code 2 means for a requirement rule;
    expect the rule not to be met, as with a detection script that exits non-zero.
    Diagnostics go to STDERR, never STDOUT, and only when the exit code isn't 0.

    INTUNE RULE

      Requirement                                     Output data type  Operator  Value
      ----------------------------------------------  ----------------  --------  -----
      Device runs one of them (Configuration          Boolean           Equals    True
        Manager "One of")
      Device runs none of them (Configuration         Boolean           Equals    False
        Manager "None of")

.NOTES
    Intune rule settings:
      Run script as 32-bit process on 64-bit clients  : No (Yes gives the same result)
      Run this script using the logged on credentials : No
      Enforce script signature check                  : No, unless you sign the script
      Select output data type                         : Boolean (operator and value: .OUTPUTS)
#>

$ErrorActionPreference = 'Stop'

trap {
    [Console]::Error.WriteLine("Requirement script error: $($_.Exception.Message)")
    exit 2
}

# --- Configuration -----------------------------------------------------------

# Operating systems that meet the requirement, as Configuration Manager lists them under
# Windows 10 and Windows 11. The device meets the requirement when it runs any one of
# them. Comment out a line to leave that entry unselected, like clearing its check box.
# A misspelled entry, or an empty list, makes the script exit 2.
[ValidateNotNullOrEmpty()]
[ValidateSet(
    'All Windows 10 (32-bit)',
    'All Windows 10 (64-bit)',
    'All Windows 10 (ARM64)',
    'Windows 10 Enterprise multi-session',
    'All Windows 11 (64-bit)',
    'All Windows 11 (ARM64)',
    'Windows 11 Enterprise multi-session'
)]
[string[]]$AllowedOperatingSystems = @(
    # 'All Windows 10 (32-bit)'
    'All Windows 10 (64-bit)'
    # 'All Windows 10 (ARM64)'
    # 'Windows 10 Enterprise multi-session'
    'All Windows 11 (64-bit)'
    # 'All Windows 11 (ARM64)'
    # 'Windows 11 Enterprise multi-session'
)

# -----------------------------------------------------------------------------

$operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -Property Version, ProductType, OperatingSystemSKU
$processorArchitecture = @(Get-CimInstance -ClassName Win32_Processor -Property Architecture)[0].Architecture
$is64BitOperatingSystem = [Environment]::Is64BitOperatingSystem

$windowsVersion = [version]$operatingSystem.Version
$isMultiSession = $operatingSystem.OperatingSystemSKU -eq 175
$isWindowsClient = $windowsVersion.Major -eq 10 -and ($isMultiSession -or $operatingSystem.ProductType -eq 1)

$devicePlatform = $null
if ($isWindowsClient) {
    $windowsName = if ($windowsVersion.Build -ge 22000) { 'Windows 11' } else { 'Windows 10' }
    $architecture = if ($processorArchitecture -in 5, 12) { 'ARM64' } elseif ($is64BitOperatingSystem) { '64-bit' } else { '32-bit' }
    $devicePlatform = if ($isMultiSession) { "$windowsName Enterprise multi-session" } else { "All $windowsName ($architecture)" }
}

$meetsRequirement = $null -ne $devicePlatform -and $AllowedOperatingSystems -contains $devicePlatform

# The one line Intune parses: True or False.
Write-Output ([string]$meetsRequirement)
exit 0
