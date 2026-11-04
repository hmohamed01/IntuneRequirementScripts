#Requires -Version 5.1

<#
.SYNOPSIS
    Intune Win32 app requirement script: detects an application by a file it installs.

.DESCRIPTION
    Checks one file path and writes exactly one value to STDOUT for an Intune
    requirement rule. Copy the script, edit the Configuration block, and upload it
    under the app's Requirements > Add > Requirement type: Script.

    The version comes from the file's version resource. A file without one reports 0.0.0.0.

.OUTPUTS
    WHAT INTUNE SHOULD EXPECT

    At most one line on STDOUT, set by $OutputType:

      $OutputType  STDOUT, installed  STDOUT, not installed    Intune output data type
      -----------  -----------------  -----------------------  -----------------------
      Boolean      True               False                    Boolean
      String       Installed          NotInstalled             String
      Integer      24                 (nothing, exit code 1)   Integer
      Version      24.8.0.0           (nothing, exit code 1)   Version

    Integer is the file's major version. Version always has four parts.

    Microsoft documents that Intune reads STDOUT when the exit code is 0, as the output
    data type selected on the rule. It doesn't document what another exit code means for
    a requirement rule; expect the rule not to be met, as with a detection script that
    exits non-zero. Diagnostics go to STDERR, never STDOUT, and only when the exit code
    isn't 0.

      Exit code  Meaning
      ---------  ----------------------------------------------------------
      0          One line written to STDOUT
      1          Nothing to report: the file isn't there (Integer, Version)
      2          Script error, e.g. an invalid Configuration value

    INTUNE RULE EXAMPLES

      Requirement                 Output data type  Operator                  Value
      --------------------------  ----------------  ------------------------  ---------
      App is installed            Boolean           Equals                    True
      App isn't installed         Boolean           Equals                    False
      App is installed            String            Equals                    Installed
      Version 24.8.0.0 or later   Version           Greater than or equal to  24.8.0.0
      Older than 24.8.0.0         Version           Less than                 24.8.0.0
      Major version 24 or later   Integer           Greater than or equal to  24

    Enter Version values with all four parts, as the script writes them: 24.8.0.0, not 24.8.
    A missing app exits 1 with no output, so expect it not to meet an Integer or Version
    rule: "Less than" targets old installs only. To target devices without the app, use
    Boolean, Equals, False, which exits 0 as Microsoft documents.

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

# Full path to a file the application installs. Environment variables are expanded.
# On 64-bit Windows, %ProgramW6432% is always the 64-bit Program Files folder, in a
# 32-bit or a 64-bit process. %ProgramFiles% is not: a 32-bit process gets the x86 folder.
[ValidateNotNullOrEmpty()]
[string]$FilePath = '%ProgramW6432%\7-Zip\7z.exe'

# What the script reports. Must match the output data type selected on the Intune rule.
# .OUTPUTS at the top shows what each choice writes and the Intune rule that reads it.
[ValidateSet('Boolean', 'String', 'Integer', 'Version')]
[string]$OutputType = 'Version'

# -----------------------------------------------------------------------------

$resolvedPath = [Environment]::ExpandEnvironmentVariables($FilePath)
$isInstalled = Test-Path -LiteralPath $resolvedPath -PathType Leaf

$installedVersion = $null
if ($isInstalled) {
    $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($resolvedPath)
    $installedVersion = [version]::new(
        $versionInfo.FileMajorPart, $versionInfo.FileMinorPart,
        $versionInfo.FileBuildPart, $versionInfo.FilePrivatePart)
}

$requirementValue = switch ($OutputType) {
    'Boolean' { [string]$isInstalled }
    'String'  { if ($isInstalled) { 'Installed' } else { 'NotInstalled' } }
    'Integer' { if ($isInstalled) { [string]$installedVersion.Major } }
    'Version' { if ($isInstalled) { $installedVersion.ToString() } }
}

if ($null -eq $requirementValue) {
    [Console]::Error.WriteLine("Not installed: $resolvedPath")
    exit 1
}

# The one line Intune parses: True, False, Installed, NotInstalled, e.g. 24, or e.g. 24.8.0.0.
Write-Output $requirementValue
exit 0
