#Requires -Version 5.1

<#
.SYNOPSIS
    Intune Win32 app requirement script: checks whether the device is in one of the allowed Active Directory sites.

.DESCRIPTION
    Mirrors a Configuration Manager requirement rule with Category Device, Condition
    Active Directory site and the One of operator. List the allowed site names in the
    Configuration block, and the script writes True when the device's site is one of
    them, and False otherwise.

    A site matches an entry only when the whole name is the same, ignoring case. There
    are no wildcards: * and ? are ordinary characters.

    How the device is identified:
      - Domain membership: Win32_ComputerSystem.PartOfDomain in root\cimv2. A device
        that isn't joined to an Active Directory domain, such as a Microsoft Entra
        joined device, is in no site, so the result is False.
      - Site: the registry key HKLM\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters.
        SiteName, the site an administrator assigned, is used when it has a value;
        otherwise DynamicSiteName, the site the Netlogon service discovered.

    The registry is read, not a domain controller, so the script also works when the
    device can't reach the domain. The site is then the last one Netlogon discovered: a
    laptop taken home keeps reporting the site of the office it last connected from,
    until it reaches a domain controller again.

    To see a device's site, run this on it:
      nltest /dsgetsite

    No Windows Installer provider class is queried, so the script can't start an MSI
    consistency check.

.OUTPUTS
    WHAT INTUNE SHOULD EXPECT

    One line on STDOUT:

      On the device                                  STDOUT    Exit code
      ---------------------------------------------  --------  ---------
      Domain-joined, in one of the allowed sites     True      0
      Domain-joined, in any other site               False     0
      Not joined to an Active Directory domain       False     0
      Script error, e.g. an empty list, or a         (none)    2
        domain-joined device with no site recorded

    False is written with exit code 0 because Microsoft documents that Intune reads
    STDOUT when the exit code is 0; that is what lets an Equals False ("None of") rule
    match. Microsoft doesn't document what exit code 2 means for a requirement rule;
    expect the rule not to be met, as with a detection script that exits non-zero, so a
    domain-joined device whose site can't be read meets neither rule below. Diagnostics
    go to STDERR, never STDOUT, and only when the exit code isn't 0.

    INTUNE RULE

      Requirement                                     Output data type  Operator  Value
      ----------------------------------------------  ----------------  --------  -----
      Device is in one of the sites (Configuration    Boolean           Equals    True
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

# Active Directory sites that meet the requirement, by site name as Active Directory
# Sites and Services shows it. The device meets the requirement when its site equals any
# one of them, ignoring case; * and ? are not wildcards. Put each site on its own line,
# in quotes; comment out a line to drop that site. These entries are examples: replace
# them with the sites for this app. An empty list makes the script exit 2.
[ValidateNotNullOrEmpty()]
[string[]]$AllowedSites = @(
    'London'
    'Wells'
)

# -----------------------------------------------------------------------------

$isDomainJoined = (Get-CimInstance -ClassName Win32_ComputerSystem -Property PartOfDomain).PartOfDomain

$meetsRequirement = $false
if ($isDomainJoined) {
    $netlogonParameters = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
    $assignedSite = "$($netlogonParameters.SiteName)".Trim()
    $discoveredSite = "$($netlogonParameters.DynamicSiteName)".Trim()
    $deviceSite = if ($assignedSite) { $assignedSite } else { $discoveredSite }
    if (-not $deviceSite) {
        throw 'The device is domain-joined, but Netlogon has recorded no site (SiteName and DynamicSiteName are empty).'
    }

    $meetsRequirement = $AllowedSites -contains $deviceSite
}

# The one line Intune parses: True or False.
Write-Output ([string]$meetsRequirement)
exit 0
