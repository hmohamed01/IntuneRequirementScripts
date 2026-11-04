#Requires -Version 5.1

<#
.SYNOPSIS
    Intune Win32 app requirement script: reports the installed Adobe Acrobat version as an integer.

.DESCRIPTION
    Finds Adobe Acrobat products (Acrobat and Acrobat Reader, Continuous and Classic tracks,
    32-bit and 64-bit) in root\cimv2 Win32_InstalledWin32Program and writes the highest
    installed version to STDOUT as one integer, for an Intune rule that compares Integer
    output with "Greater than or equal to".

    Entries whose version isn't in Adobe's format, such as an add-in listed under an
    Acrobat name, are ignored. When several Acrobat products are installed, the highest
    version is reported.

    The script never queries Win32_Product, or any other class served by the Windows
    Installer WMI provider (Msi.mof, Msiprov.dll): enumerating products through that
    provider makes Windows Installer check and reconfigure every installed MSI product
    (Event ID 1035, KB 974524). Win32_InstalledWin32Program is defined in Aeinv.mof and
    is documented for Windows clients only; on Windows Server the script exits 2.

.OUTPUTS
    WHAT INTUNE SHOULD EXPECT

    At most one line on STDOUT: the highest installed Acrobat version, as an integer.

      On the device                              STDOUT       Exit code
      -----------------------------------------  -----------  ---------
      Acrobat 26.002.22031 (Continuous)          260222031    0
      Acrobat 2024, 24.001.30429 (Classic)       240130429    0
      No Acrobat product installed               (nothing)    1
      Only entries without an Adobe version      (nothing)    1
      Script error, e.g. no WMI class            (nothing)    2

    Microsoft documents that Intune reads STDOUT when the exit code is 0. It doesn't
    document what another exit code means for a requirement rule; expect the rule not to
    be met, as with a detection script that exits non-zero. Diagnostics go to STDERR,
    never STDOUT, and only when the exit code isn't 0.

    INTUNE RULE

      Select output data type : Integer
      Operator                : Greater than or equal to
      Value                   : the minimum Acrobat version, converted as shown below

      Requirement                     Operator                  Value
      ------------------------------  ------------------------  ---------
      Acrobat 26.002.22031 or later   Greater than or equal to  260222031
      Older than 26.002.22031         Less than                 260222031

    With no Acrobat product installed the script exits 1 with no output, so expect neither
    rule to match.

    CONVERTING AN ADOBE VERSION TO THE INTUNE VALUE

    Adobe versions are year.release.build. The build has five digits, and its first digit
    is the track: 2 for Continuous, 3 for Classic. The integer packs the three parts:

        year * 10000000 + release * 100000 + build

      Adobe version   Track                    Integer for Intune
      --------------  -----------------------  ------------------
      26.002.22031    Continuous               260222031
      25.001.20756    Continuous               250120756
      24.001.30429    Classic (Acrobat 2024)   240130429
      20.005.30838    Classic (Acrobat 2020)   200530838

    Read 260222031 as 26 02 22031: the year, the release without its leading zero, and
    the build exactly as Adobe writes it. To convert any version in PowerShell:

        $v = [version]'26.002.22031'; $v.Major * 10000000 + $v.Minor * 100000 + $v.Build

    Compare within one track. Inside a track the integers sort exactly as the versions
    do; across tracks they sort by year and release first.

    Why not just remove the dots? 2600222031 is larger than 2,147,483,647, the largest
    32-bit integer, and Intune doesn't document whether Integer output is 32-bit. If it
    is, that number would fail to parse on every device and the rule would never match.
    The packed form stays below 1,000,000,000. It needs the release below 100, which
    Adobe's releases always have been; a release of 100 or more makes the script exit 2
    rather than report a number that sorts wrongly.

.NOTES
    Intune rule settings:
      Run script as 32-bit process on 64-bit clients  : No
      Run this script using the logged on credentials : No
      Enforce script signature check                  : No, unless you sign the script
      Select output data type                         : Integer (operator and value: .OUTPUTS)
#>

$ErrorActionPreference = 'Stop'

trap {
    [Console]::Error.WriteLine("Requirement script error: $($_.Exception.Message)")
    exit 2
}

# --- Configuration -----------------------------------------------------------

# Display names to consider. Wildcards: * and ?
[ValidateNotNullOrEmpty()]
[string]$NamePattern = 'Adobe Acrobat*'

# Publisher, with the same wildcards.
[ValidateNotNullOrEmpty()]
[string]$PublisherPattern = 'Adobe*'

# -----------------------------------------------------------------------------

function ConvertTo-AcrobatVersionNumber {
    # Returns $null for text that isn't year.release.build with a 2xxxx or 3xxxx build.
    param([string]$VersionText)

    if ($VersionText -notmatch '^\s*(\d{1,2}\.\d{1,3}\.[23]\d{4})(?:\.\d+)?\s*$') { return $null }
    $acrobatVersion = [version]$Matches[1]

    if ($acrobatVersion.Minor -ge 100) {
        throw "Release $($acrobatVersion.Minor) in Acrobat version $VersionText can't be encoded as an integer."
    }
    return $acrobatVersion.Major * 10000000 + $acrobatVersion.Minor * 100000 + $acrobatVersion.Build
}

$acrobatPrograms = @(
    Get-CimInstance -ClassName Win32_InstalledWin32Program -Property Name, Vendor, Version |
        Where-Object { $_.Name -like $NamePattern -and $_.Vendor -like $PublisherPattern }
)

if ($acrobatPrograms.Count -eq 0) {
    [Console]::Error.WriteLine("Not installed: $NamePattern")
    exit 1
}

$versionNumbers = @(
    $acrobatPrograms |
        ForEach-Object { ConvertTo-AcrobatVersionNumber -VersionText $_.Version } |
        Where-Object { $null -ne $_ }
)

if ($versionNumbers.Count -eq 0) {
    $foundEntries = ($acrobatPrograms | ForEach-Object { "$($_.Name) [$($_.Version)]" }) -join '; '
    [Console]::Error.WriteLine("No Adobe-format version: $foundEntries")
    exit 1
}

# The one line Intune parses: the highest version as an integer, e.g. 260222031 for 26.002.22031.
Write-Output ($versionNumbers | Sort-Object -Descending | Select-Object -First 1)
exit 0
