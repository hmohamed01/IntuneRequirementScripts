#Requires -Version 5.1

<#
.SYNOPSIS
    Intune Win32 app requirement script: checks whether the device is one of the allowed computer models.

.DESCRIPTION
    Works like a Configuration Manager collection query on
    SMS_G_System_COMPUTER_SYSTEM.Model. List the allowed models in the Configuration
    block, and the script writes True when the device's model is one of them, and False
    otherwise. It compares only the model string, so one copy of the script works for any
    manufacturer.

    A model matches an entry only when the whole string is the same, ignoring case, as in
    a WQL Model = '...' query. There are no wildcards: * and ? are ordinary characters, so
    'Latitude 54*' doesn't match Latitude 5440, and 'Latitude 5440' doesn't match
    Latitude 5440 2-in-1.

    The model comes from Win32_ComputerSystem.Model in root\cimv2, the property that
    Configuration Manager hardware inventory collects as SMS_G_System_COMPUTER_SYSTEM.Model.
    Leading and trailing spaces, which some manufacturers pad the value with, are removed
    before comparing.

    To see a device's model, run this on it:
      (Get-CimInstance -ClassName Win32_ComputerSystem).Model

    Lenovo reports the machine type in Model, e.g. 20XW003JUS, not the product name, so
    list each Lenovo machine type in full.

    No Windows Installer provider class is queried, so the script can't start an MSI
    consistency check.

.OUTPUTS
    WHAT INTUNE SHOULD EXPECT

    One line on STDOUT:

      On the device                                  STDOUT    Exit code
      ---------------------------------------------  --------  ---------
      One of the allowed models                      True      0
      Any other model                                False     0
      Script error, e.g. an empty list, or an        (none)    2
        empty Model value

    False is written with exit code 0 because Microsoft documents that Intune reads
    STDOUT when the exit code is 0; that is what lets an Equals False ("None of") rule
    match. Microsoft doesn't document what exit code 2 means for a requirement rule;
    expect the rule not to be met, as with a detection script that exits non-zero, so a
    device whose model can't be read meets neither rule below. Diagnostics go to STDERR,
    never STDOUT, and only when the exit code isn't 0.

    INTUNE RULE

      Requirement                                     Output data type  Operator  Value
      ----------------------------------------------  ----------------  --------  -----
      Device is one of the listed models              Boolean           Equals    True
      Device is none of the listed models             Boolean           Equals    False

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

# Computer models that meet the requirement, exactly as Win32_ComputerSystem.Model
# reports them. The device meets the requirement when its model equals any one of them,
# ignoring case; * and ? are not wildcards. Put each model on its own line, in quotes;
# comment out a line to drop that model. These entries are examples: replace them with
# the models for this app. An empty list makes the script exit 2.
[ValidateNotNullOrEmpty()]
[string[]]$AllowedModels = @(
    'Latitude 5440'
    'Latitude 7440'
    'HP EliteBook 840 G10 Notebook PC'
    'Surface Laptop 5'
)

# -----------------------------------------------------------------------------

$computerModel = "$((Get-CimInstance -ClassName Win32_ComputerSystem -Property Model).Model)".Trim()
if (-not $computerModel) {
    throw 'Win32_ComputerSystem.Model is empty.'
}

$meetsRequirement = $AllowedModels -contains $computerModel

# The one line Intune parses: True or False.
Write-Output ([string]$meetsRequirement)
exit 0
