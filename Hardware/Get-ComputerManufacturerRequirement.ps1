#Requires -Version 5.1

<#
.SYNOPSIS
    Intune Win32 app requirement script: checks whether the device is from one of the allowed manufacturers.

.DESCRIPTION
    Works like a Configuration Manager collection query on
    SMS_G_System_COMPUTER_SYSTEM.Manufacturer. List the allowed manufacturers in the
    Configuration block, and the script writes True when the device's manufacturer is one
    of them, and False otherwise.

    A manufacturer matches an entry only when the whole string is the same, ignoring case,
    as in a WQL Manufacturer = '...' query. There are no wildcards: * and ? are ordinary
    characters, so 'Dell*' doesn't match Dell Inc., and 'HP' doesn't match Hewlett-Packard.

    The manufacturer comes from Win32_ComputerSystem.Manufacturer in root\cimv2, the
    property that Configuration Manager hardware inventory collects as
    SMS_G_System_COMPUTER_SYSTEM.Manufacturer. Leading and trailing spaces are removed
    before comparing.

    To see a device's manufacturer, run this on it:
      (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer

    One vendor can report several names across its product generations, e.g. HP and
    Hewlett-Packard. List every name your devices report.

    No Windows Installer provider class is queried, so the script can't start an MSI
    consistency check.

.OUTPUTS
    WHAT INTUNE SHOULD EXPECT

    One line on STDOUT:

      On the device                                  STDOUT    Exit code
      ---------------------------------------------  --------  ---------
      One of the allowed manufacturers               True      0
      Any other manufacturer                         False     0
      Script error, e.g. an empty list, or an        (none)    2
        empty Manufacturer value

    False is written with exit code 0 because Microsoft documents that Intune reads
    STDOUT when the exit code is 0; that is what lets an Equals False ("None of") rule
    match. Microsoft doesn't document what exit code 2 means for a requirement rule;
    expect the rule not to be met, as with a detection script that exits non-zero, so a
    device whose manufacturer can't be read meets neither rule below. Diagnostics go to
    STDERR, never STDOUT, and only when the exit code isn't 0.

    INTUNE RULE

      Requirement                                     Output data type  Operator  Value
      ----------------------------------------------  ----------------  --------  -----
      Device is from one of the listed manufacturers  Boolean           Equals    True
      Device is from none of them                     Boolean           Equals    False

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

# Manufacturers that meet the requirement, exactly as Win32_ComputerSystem.Manufacturer
# reports them. The device meets the requirement when its manufacturer equals any one of
# them, ignoring case; * and ? are not wildcards. Put each manufacturer on its own line,
# in quotes; comment out a line to drop that manufacturer. These entries are examples:
# replace them with the manufacturers for this app. An empty list makes the script exit 2.
[ValidateNotNullOrEmpty()]
[string[]]$AllowedManufacturers = @(
    'Dell Inc.'
    'HP'
    'Hewlett-Packard'
    'LENOVO'
    'Microsoft Corporation'
)

# -----------------------------------------------------------------------------

$computerManufacturer = "$((Get-CimInstance -ClassName Win32_ComputerSystem -Property Manufacturer).Manufacturer)".Trim()
if (-not $computerManufacturer) {
    throw 'Win32_ComputerSystem.Manufacturer is empty.'
}

$meetsRequirement = $AllowedManufacturers -contains $computerManufacturer

# The one line Intune parses: True or False.
Write-Output ([string]$meetsRequirement)
exit 0
