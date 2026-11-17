#Requires -Version 5.1

<#
.SYNOPSIS
    Intune Win32 app requirement script: checks whether the device's computer account is in one of the allowed organizational units.

.DESCRIPTION
    Mirrors a Configuration Manager requirement rule with Category Device, Condition
    Organizational unit (OU) and the One of operator. List the allowed OUs in the
    Configuration block, each with the same two settings Configuration Manager asks for:
    the OU's distinguished name, and whether to include its child OUs. The script writes
    True when the computer account is in any one of them, and False otherwise.

    Each entry is a hashtable, in the form Microsoft's New-CMRequirementRuleOUValue
    cmdlet takes:
      @{ OU = 'OU=Workstations,DC=contoso,DC=com'; IsIncludeSubOU = $true }

      IsIncludeSubOU   The computer account matches when it is
      --------------   ------------------------------------------------------------
      $false           Directly in that OU
      $true            In that OU, or in any OU below it

    Distinguished names are compared whole, ignoring case and any spaces around the
    commas between their parts. There are no wildcards. A container such as
    CN=Computers,DC=contoso,DC=com works the same way as an OU.

    How the device is identified:
      - Domain membership: Win32_ComputerSystem.PartOfDomain in root\cimv2. A device
        that isn't joined to an Active Directory domain, such as a Microsoft Entra
        joined device, is in no OU, so the result is False.
      - Computer account: the Distinguished-Name value of the registry key
        HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine,
        which Group Policy records each time it processes computer policy. The OU is
        that name without its first part, the computer's own CN.

    The registry is read, not a domain controller, so the script also works when the
    device can't reach the domain. After a computer account moves to another OU, the
    value changes at the next computer Group Policy refresh that reaches a domain
    controller. Microsoft doesn't document this registry value, so confirm it on your
    devices before relying on the rule.

    To see a device's recorded distinguished name, run this on it:
      (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine').'Distinguished-Name'

    No Windows Installer provider class is queried, so the script can't start an MSI
    consistency check.

.OUTPUTS
    WHAT INTUNE SHOULD EXPECT

    One line on STDOUT:

      On the device                                  STDOUT    Exit code
      ---------------------------------------------  --------  ---------
      Domain-joined, in one of the allowed OUs       True      0
      Domain-joined, in any other OU                 False     0
      Not joined to an Active Directory domain       False     0
      Script error, e.g. an invalid entry, or a      (none)    2
        domain-joined device with no recorded
        distinguished name

    False is written with exit code 0 because Microsoft documents that Intune reads
    STDOUT when the exit code is 0; that is what lets an Equals False ("None of") rule
    match. Microsoft doesn't document what exit code 2 means for a requirement rule;
    expect the rule not to be met, as with a detection script that exits non-zero, so a
    domain-joined device whose OU can't be read meets neither rule below. Diagnostics go
    to STDERR, never STDOUT, and only when the exit code isn't 0.

    INTUNE RULE

      Requirement                                     Output data type  Operator  Value
      ----------------------------------------------  ----------------  --------  -----
      Device is in one of the OUs (Configuration      Boolean           Equals    True
        Manager "One of")
      Device is in none of them (Configuration        Boolean           Equals    False
        Manager "None of")

    A None of rule also matches devices that aren't domain-joined.

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

# Organizational units that meet the requirement. Each entry has the OU's distinguished
# name and IsIncludeSubOU: $true also allows computer accounts in the OUs below it,
# $false only those directly in it. The device meets the requirement when its computer
# account is in any one of them. Put each entry on its own line; comment out a line to
# drop that OU. These entries are examples: replace them with the OUs for this app. An
# empty list, or an entry without both settings, makes the script exit 2.
[ValidateNotNullOrEmpty()]
[hashtable[]]$AllowedOrganizationalUnits = @(
    @{ OU = 'OU=Workstations,DC=contoso,DC=com'; IsIncludeSubOU = $true }
    @{ OU = 'OU=Kiosks,OU=Shared Devices,DC=contoso,DC=com'; IsIncludeSubOU = $false }
)

# -----------------------------------------------------------------------------

function ConvertTo-NormalizedDistinguishedName {
    param([string]$DistinguishedName)

    # A comma preceded by a backslash is part of a name, not a separator.
    $DistinguishedName.Trim() -replace '\s*(?<!\\),\s*', ','
}

foreach ($allowedUnit in $AllowedOrganizationalUnits) {
    if ($allowedUnit.OU -isnot [string] -or -not $allowedUnit.OU.Trim()) {
        throw 'Every entry in $AllowedOrganizationalUnits needs an OU distinguished name.'
    }
    if ($allowedUnit.IsIncludeSubOU -isnot [bool]) {
        throw "The entry for '$($allowedUnit.OU)' needs IsIncludeSubOU set to `$true or `$false."
    }
}

$isDomainJoined = (Get-CimInstance -ClassName Win32_ComputerSystem -Property PartOfDomain).PartOfDomain

$meetsRequirement = $false
if ($isDomainJoined) {
    $machinePolicyState = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine'
    $computerDistinguishedName = ConvertTo-NormalizedDistinguishedName -DistinguishedName "$($machinePolicyState.'Distinguished-Name')"
    if (-not $computerDistinguishedName) {
        throw 'The device is domain-joined, but Group Policy has recorded no distinguished name for it.'
    }

    $null, $deviceOrganizationalUnit = $computerDistinguishedName -split '(?<!\\),', 2
    if (-not $deviceOrganizationalUnit) {
        throw "The recorded distinguished name '$computerDistinguishedName' has no parent container."
    }

    foreach ($allowedUnit in $AllowedOrganizationalUnits) {
        $allowedDistinguishedName = ConvertTo-NormalizedDistinguishedName -DistinguishedName $allowedUnit.OU
        $isDirectlyInUnit = $deviceOrganizationalUnit -eq $allowedDistinguishedName
        $isBelowUnit = $deviceOrganizationalUnit.EndsWith(",$allowedDistinguishedName", [StringComparison]::OrdinalIgnoreCase)
        if ($isDirectlyInUnit -or ($allowedUnit.IsIncludeSubOU -and $isBelowUnit)) {
            $meetsRequirement = $true
            break
        }
    }
}

# The one line Intune parses: True or False.
Write-Output ([string]$meetsRequirement)
exit 0
