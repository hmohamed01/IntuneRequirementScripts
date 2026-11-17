#Requires -Version 5.1

<#
.SYNOPSIS
    Intune Win32 app requirement script: checks whether Windows was installed in one of the selected languages.

.DESCRIPTION
    Mirrors a Configuration Manager requirement rule with Category Device, Condition
    Operating system language and the One of operator. List the allowed languages in the
    Configuration block by culture name, e.g. en-US, the Name that Microsoft's
    New-CMRequirementRuleOperatingSystemLanguageValue cmdlet filters cultures by. The
    script writes True when the operating system language is any one of them, and False
    otherwise.

    The operating system language is Win32_OperatingSystem.OSLanguage in root\cimv2: the
    language Windows was installed in, as a language code identifier (LCID), e.g. 1033
    for en-US. Microsoft documents that a Configuration Manager task sequence compares
    its operating system language condition with this property. It doesn't document
    which value the application requirement reads, so this script uses the same one.

    OSLanguage is not the display language. A device installed in English (United
    States) that has a German language pack, and shows Windows in German, still reports
    en-US.

    Each entry is one language and region, matched exactly: en-US doesn't match en-GB.
    List every one you want to allow. A language without a region, such as en, is
    rejected, because OSLanguage never reports one.

    To see a device's operating system language as a culture name, run this on it:
      [cultureinfo]::GetCultureInfo([int](Get-CimInstance -ClassName Win32_OperatingSystem).OSLanguage).Name

    No Windows Installer provider class is queried, so the script can't start an MSI
    consistency check.

.OUTPUTS
    WHAT INTUNE SHOULD EXPECT

    One line on STDOUT:

      On the device                                  STDOUT    Exit code
      ---------------------------------------------  --------  ---------
      Installed in one of the selected languages     True      0
      Installed in any other language                False     0
      Script error, e.g. an unknown culture name     (none)    2
        or an empty list

    False is written with exit code 0 because Microsoft documents that Intune reads
    STDOUT when the exit code is 0; that is what lets an Equals False ("None of") rule
    match. Microsoft doesn't document what exit code 2 means for a requirement rule;
    expect the rule not to be met, as with a detection script that exits non-zero.
    Diagnostics go to STDERR, never STDOUT, and only when the exit code isn't 0.

    INTUNE RULE

      Requirement                                     Output data type  Operator  Value
      ----------------------------------------------  ----------------  --------  -----
      Installed in one of them (Configuration         Boolean           Equals    True
        Manager "One of")
      Installed in none of them (Configuration        Boolean           Equals    False
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

# Operating system languages that meet the requirement, as culture names with a region,
# e.g. en-US. The device meets the requirement when Windows was installed in any one of
# them. Put each language on its own line, in quotes; comment out a line to drop that
# language. These entries are examples: replace them with the languages for this app.
# An unknown name, a name without a region, or an empty list makes the script exit 2.
[ValidateNotNullOrEmpty()]
[string[]]$AllowedLanguages = @(
    'en-US'
    'en-GB'
)

# -----------------------------------------------------------------------------

# Windows gives every culture name it doesn't know the placeholder LCID 4096.
$unknownCultureLanguageId = 4096

$allowedLanguageIds = @(
    foreach ($languageName in $AllowedLanguages) {
        $culture = [cultureinfo]::GetCultureInfo($languageName)
        if ($culture.IsNeutralCulture -or $culture.LCID -eq $unknownCultureLanguageId) {
            throw "'$languageName' is not a culture name with a language and a region, such as en-US."
        }
        $culture.LCID
    }
)

$operatingSystemLanguageId = (Get-CimInstance -ClassName Win32_OperatingSystem -Property OSLanguage).OSLanguage
if (-not $operatingSystemLanguageId) {
    throw 'Win32_OperatingSystem.OSLanguage is empty.'
}

$meetsRequirement = $allowedLanguageIds -contains $operatingSystemLanguageId

# The one line Intune parses: True or False.
Write-Output ([string]$meetsRequirement)
exit 0
