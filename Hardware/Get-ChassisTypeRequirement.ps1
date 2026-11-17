#Requires -Version 5.1

<#
.SYNOPSIS
    Intune Win32 app requirement script: checks whether the device has one of the allowed chassis types.

.DESCRIPTION
    Works like a Configuration Manager collection query on
    SMS_G_System_SYSTEM_ENCLOSURE.ChassisTypes, the usual way to tell laptops from
    desktops. Select the allowed chassis type numbers in the Configuration block, and the
    script writes True when the device reports any one of them, and False otherwise.

    The chassis types come from Win32_SystemEnclosure.ChassisTypes in root\cimv2, which
    Windows reads from the SMBIOS System Enclosure or Chassis structure. The property is
    an array, and a device can have more than one enclosure; the device meets the
    requirement when any reported number is selected, as a WQL ChassisTypes in (...)
    query matches any enclosure.

    To see a device's chassis types, run this on it:
      (Get-CimInstance -ClassName Win32_SystemEnclosure).ChassisTypes

    The number is whatever the manufacturer wrote to the firmware. Virtual machines
    often report 1 (Other) or 3 (Desktop), and small desktops report 3, 15 or 35
    depending on the vendor, so check real devices before relying on a selection.

    No Windows Installer provider class is queried, so the script can't start an MSI
    consistency check.

.OUTPUTS
    WHAT INTUNE SHOULD EXPECT

    One line on STDOUT:

      On the device                                  STDOUT    Exit code
      ---------------------------------------------  --------  ---------
      At least one selected chassis type             True      0
      No selected chassis type                       False     0
      Script error, e.g. an empty list, a number     (none)    2
        outside 1 to 36, or no chassis type reported

    False is written with exit code 0 because Microsoft documents that Intune reads
    STDOUT when the exit code is 0; that is what lets an Equals False ("None of") rule
    match. Microsoft doesn't document what exit code 2 means for a requirement rule;
    expect the rule not to be met, as with a detection script that exits non-zero, so a
    device that reports no chassis type meets neither rule below. Diagnostics go to
    STDERR, never STDOUT, and only when the exit code isn't 0.

    INTUNE RULE

      Requirement                                     Output data type  Operator  Value
      ----------------------------------------------  ----------------  --------  -----
      Device has one of the selected chassis types    Boolean           Equals    True
      Device has none of them                         Boolean           Equals    False

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

# Chassis types that meet the requirement, by their Win32_SystemEnclosure.ChassisTypes
# number. The device meets the requirement when it reports any one of them. Uncomment a
# line to select that chassis type, like ticking its check box; comment it out to clear
# it. The shipped selection is an example for "laptops". A number outside 1 to 36, or an
# empty list, makes the script exit 2.
# Names for 1 to 24 and 30 to 32 are from Microsoft's Win32_SystemEnclosure page; the
# others are from the DMTF SMBIOS specification.
[ValidateNotNullOrEmpty()]
[ValidateRange(1, 36)]
[int[]]$AllowedChassisTypes = @(
    # 1     # Other
    # 2     # Unknown
    # 3     # Desktop
    # 4     # Low Profile Desktop
    # 5     # Pizza Box
    # 6     # Mini Tower
    # 7     # Tower
    8       # Portable
    9       # Laptop
    10      # Notebook
    # 11    # Hand Held
    # 12    # Docking Station
    # 13    # All in One
    14      # Sub Notebook
    # 15    # Space-Saving
    # 16    # Lunch Box
    # 17    # Main System Chassis
    # 18    # Expansion Chassis
    # 19    # SubChassis
    # 20    # Bus Expansion Chassis
    # 21    # Peripheral Chassis
    # 22    # Storage Chassis
    # 23    # Rack Mount Chassis
    # 24    # Sealed-Case PC
    # 25    # Multi-system Chassis
    # 26    # Compact PCI
    # 27    # Advanced TCA
    # 28    # Blade
    # 29    # Blade Enclosure
    # 30    # Tablet
    31      # Convertible
    32      # Detachable
    # 33    # IoT Gateway
    # 34    # Embedded PC
    # 35    # Mini PC
    # 36    # Stick PC
)

# -----------------------------------------------------------------------------

$deviceChassisTypes = @(
    Get-CimInstance -ClassName Win32_SystemEnclosure -Property ChassisTypes |
        ForEach-Object { $_.ChassisTypes } |
        Where-Object { $null -ne $_ }
)
if ($deviceChassisTypes.Count -eq 0) {
    throw 'Win32_SystemEnclosure.ChassisTypes is empty.'
}

$meetsRequirement = @($deviceChassisTypes | Where-Object { $AllowedChassisTypes -contains $_ }).Count -gt 0

# The one line Intune parses: True or False.
Write-Output ([string]$meetsRequirement)
exit 0
