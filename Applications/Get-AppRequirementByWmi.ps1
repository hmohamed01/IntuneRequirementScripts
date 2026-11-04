#Requires -Version 5.1

<#
.SYNOPSIS
    Intune Win32 app requirement script: detects an application through WMI.

.DESCRIPTION
    Queries root\cimv2 Win32_InstalledWin32Program with Get-CimInstance, keeps the entries
    whose display name (and optionally publisher) match, and writes exactly one value to
    STDOUT for an Intune requirement rule. Copy the script, edit the Configuration block,
    and upload it under the app's Requirements > Add > Requirement type: Script.

    The script never queries Win32_Product, or any other class served by the Windows
    Installer WMI provider (Msi.mof, Msiprov.dll): enumerating products through that
    provider makes Windows Installer check and reconfigure every installed MSI product
    (Event ID 1035, KB 974524). Win32_InstalledWin32Program is defined in Aeinv.mof, a
    different provider.

    Win32_InstalledWin32Program is documented for Windows clients only. On Windows Server
    the query fails and the script exits 2.

.OUTPUTS
    WHAT INTUNE SHOULD EXPECT

    At most one line on STDOUT, set by $OutputType:

      $OutputType  STDOUT, installed  STDOUT, not installed    Intune output data type
      -----------  -----------------  -----------------------  -----------------------
      Boolean      True               False                    Boolean
      String       Installed          NotInstalled             String
      Integer      24                 (nothing, exit code 1)   Integer
      Version      24.8               (nothing, exit code 1)   Version

    Version is the version text from Installed apps, cleaned up: the leading number is
    kept ('24.08' -> 24.8, '1.2.3 build 7' -> 1.2.3) and a one-part version is padded
    ('5' -> 5.0). Integer is its first part. When several entries match, such as x86 and
    x64 builds, the highest readable version is reported.

    Intune reads STDOUT only when the exit code is 0, then parses it as the output data
    type selected on the rule. Any other exit code means the rule isn't met, whatever the
    operator. Diagnostics go to STDERR, so they never reach the value Intune parses.

      Exit code  Meaning
      ---------  ---------------------------------------------------------------
      0          One line written to STDOUT
      1          Nothing to report (Integer, Version): the app isn't installed,
                 or no matching entry has a number in its version text
      2          Script error, e.g. an invalid Configuration value or no WMI class

    INTUNE RULE EXAMPLES

      Requirement                 Output data type  Operator                  Value
      --------------------------  ----------------  ------------------------  ---------
      App is installed            Boolean           Equals                    True
      App isn't installed         Boolean           Equals                    False
      App is installed            String            Equals                    Installed
      Version 24.8 or later       Version           Greater than or equal to  24.8
      Older than 24.8             Version           Less than                 24.8
      Major version 24 or later   Integer           Greater than or equal to  24

    Enter Version values with as many parts as the script writes for the app. Run it once
    on a device to see the exact form. A missing app never meets an Integer or Version
    rule, so "Less than" targets old installs only. To target devices without the app,
    use Boolean, Equals, False.

.NOTES
    Intune rule settings:
      Run script as 32-bit process on 64-bit clients  : No
      Run this script using the logged on credentials : No
      Enforce script signature check                  : No, unless you sign the script
      Select output data type                         : the type for $OutputType (.OUTPUTS)
#>

$ErrorActionPreference = 'Stop'

trap {
    [Console]::Error.WriteLine("Requirement script error: $($_.Exception.Message)")
    exit 2
}

# --- Configuration -----------------------------------------------------------

# Display name as listed in Settings > Apps > Installed apps. Wildcards: * and ?
# Make it specific enough to skip companion entries, such as an app's updater.
[ValidateNotNullOrEmpty()]
[string]$NamePattern = '7-Zip*'

# Publisher, with the same wildcards. '*' matches any publisher, including none.
[ValidateNotNullOrEmpty()]
[string]$PublisherPattern = '*'

# What the script reports. Must match the output data type selected on the Intune rule.
# .OUTPUTS at the top shows what each choice writes and the Intune rule that reads it.
[ValidateSet('Boolean', 'String', 'Integer', 'Version')]
[string]$OutputType = 'Version'

# -----------------------------------------------------------------------------

function ConvertTo-ComparableVersion {
    # Win32_InstalledWin32Program.Version is free text ('24.08', '1.2.3 build 7', '').
    # Keep the leading numeric part, pad a one-part version to two parts, and return
    # $null when nothing usable remains.
    param([string]$VersionText)

    if ($VersionText -notmatch '^\s*[vV]?(\d+(?:\.\d+){0,3})') { return $null }
    $numericText = if ($Matches[1].Contains('.')) { $Matches[1] } else { "$($Matches[1]).0" }

    $parsedVersion = $null
    if ([version]::TryParse($numericText, [ref]$parsedVersion)) { return $parsedVersion }
    return $null
}

function Select-ReportedProgram {
    # Several entries can match one pattern: x86 and x64 builds side by side, or two
    # versions of a runtime. Report the highest readable version, as the Acrobat script
    # does: "Greater than or equal to" is met when at least one install meets it, and
    # "Less than" only when every readable install is older. When no entry has a
    # readable version, return the first one so the caller exits 1.
    param([object[]]$Programs)

    $parsedPrograms = foreach ($program in $Programs) {
        [pscustomobject]@{
            Program = $program
            Version = ConvertTo-ComparableVersion -VersionText $program.Version
        }
    }
    $highestProgram = $parsedPrograms |
        Where-Object { $null -ne $_.Version } |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1

    if ($null -eq $highestProgram) { return $Programs[0] }
    return $highestProgram.Program
}

$matchingPrograms = @(
    Get-CimInstance -ClassName Win32_InstalledWin32Program -Property Name, Vendor, Version |
        Where-Object { $_.Name -like $NamePattern -and $_.Vendor -like $PublisherPattern }
)
$isInstalled = $matchingPrograms.Count -gt 0

$installedVersion = $null
if ($isInstalled -and $OutputType -in 'Integer', 'Version') {
    $reportedProgram = Select-ReportedProgram -Programs $matchingPrograms
    $installedVersion = ConvertTo-ComparableVersion -VersionText $reportedProgram.Version
}

$requirementValue = switch ($OutputType) {
    'Boolean' { [string]$isInstalled }
    'String'  { if ($isInstalled) { 'Installed' } else { 'NotInstalled' } }
    'Integer' { if ($null -ne $installedVersion) { [string]$installedVersion.Major } }
    'Version' { if ($null -ne $installedVersion) { $installedVersion.ToString() } }
}

if ($null -eq $requirementValue) {
    $reason = if ($isInstalled) { 'Version text not readable' } else { 'Not installed' }
    [Console]::Error.WriteLine("${reason}: $NamePattern")
    exit 1
}

# The one line Intune parses: True, False, Installed, NotInstalled, e.g. 24, or e.g. 24.8.
Write-Output $requirementValue
exit 0
