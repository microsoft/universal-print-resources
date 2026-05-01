<#
.SYNOPSIS
    Detects and disassociates per-system Universal Print (UP) printer installations.

.DESCRIPTION
    On Windows 10, Universal Print printers were installed per-system (no SID adornment
    in the printer name). On Windows 11, UP printers are expected to be per-user, with
    the printer name adorned with the user's SID (e.g., "S-1-12-1-...:PrinterName").

    This script detects legacy per-system UP printers by checking:
      1. The printer uses "Universal Print Class Driver"
      2. The printer name does NOT have a SID prefix (i.e., not per-user)

    For each detected printer, it reads the DeviceContainerId from the PnPData registry
    subkey, converts it to a GUID, and forms the AEP ID as "MCP#<guid>".

    It then disassociates the per-system printer via: pairtool.exe /disassociate <AEP_ID>

    The printer will be re-provisioned as per-user on the next sign-in or cloud print
    discovery cycle.

    When printers are successfully disassociated, their names are written to a
    timestamped file in C:\Users\Public (accessible to all users on the machine).

.PARAMETER ReportOnly
    When specified, the script only reports detected per-system UP printers without
    taking any remediation action. Use this first to validate findings.

.PARAMETER RemovedPrintersPath
    Optional path for the file listing removed printer names. Defaults to a
    timestamped file in C:\Users\Public (accessible to all users on the machine).

.PARAMETER LogPath
    Optional path to write a log file. Defaults to a timestamped file in the script
    directory.

.EXAMPLE
    # Dry-run: report only
    .\Delete-PerSystemUPPrinters.ps1 -ReportOnly

.EXAMPLE
    # Disassociate all per-system UP printers
    .\Delete-PerSystemUPPrinters.ps1

.NOTES
    Requires elevation (Run as Administrator).
    Built-in pairtool.exe must be present on the system (ships with Windows).
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$ReportOnly,

    [string]$LogPath,

    [string]$RemovedPrintersPath,

    [Alias('h','?')]
    [switch]$Help
)

if ($Help) {
    Write-Host @"

Delete-PerSystemUPPrinters.ps1
==============================
Detects legacy per-system Universal Print printers (from Windows 10) and
disassociates them. The printers will re-provision as per-user on next
sign-in or cloud print discovery cycle.

USAGE:
  .\Delete-PerSystemUPPrinters.ps1 [-ReportOnly] [-LogPath <path>] [-RemovedPrintersPath <path>] [-Help]

OPTIONS:
  -ReportOnly         List detected per-system UP printers without making changes.
                      Run this first to see what would be remediated.

  (default)           Disassociate per-system UP printers. They will re-provision
                      as per-user on next sign-in or discovery cycle.

  -LogPath <path>     Write log to the specified file path. Defaults to a
                      timestamped file in the script directory.

  -RemovedPrintersPath <path>
                      Write removed printer names to the specified file.
                      Defaults to a timestamped file in C:\Users\Public.

  -Help, -h, -?       Show this help message.

EXAMPLES:
  .\Delete-PerSystemUPPrinters.ps1 -ReportOnly        # Dry-run, report only
  .\Delete-PerSystemUPPrinters.ps1                     # Disassociate per-system printers

NOTES:
  - Requires elevation (Run as Administrator).
  - Uses built-in pairtool.exe (ships with Windows).
  - A log file is always written alongside the script.
  - Removed printer names are written to C:\Users\Public (accessible to all users).

"@
    return
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    if ($script:LogFile) {
        $line | Out-File -FilePath $script:LogFile -Append -Encoding utf8
    }
}

function Test-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Convert-BinaryToGuid {
    <#
    .SYNOPSIS
        Converts a 16-byte binary array (REG_BINARY DeviceContainerId) to a GUID string.
    #>
    param([byte[]]$Bytes)

    if ($Bytes.Length -ne 16) {
        throw "DeviceContainerId binary must be exactly 16 bytes, got $($Bytes.Length)."
    }

    $guid = [System.Guid]::new($Bytes)
    return $guid.ToString('D').ToLowerInvariant()  # e.g. "5bff7710-6e5a-4f0f-988b-60e3c7036d33"
}

function Test-IsSidAdorned {
    <#
    .SYNOPSIS
        Returns $true if the printer name starts with a SID prefix (per-user pattern).
        Per-user UP printers look like: S-1-12-1-xxxxxxxxx-xxxxxxxxx-xxxxxxxxx-xxxxxxxxx:PrinterName
    #>
    param([string]$PrinterName)

    return $PrinterName -match '^S-1-\d+-\d+'
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Set up logging
if (-not $LogPath) {
    $LogPath = Join-Path $PSScriptRoot ("Delete-PerSystemUP_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
$script:LogFile = $LogPath

Write-Log "=== Delete-PerSystemUPPrinters started ==="
Write-Log "Mode: $(if ($ReportOnly) { 'REPORT ONLY' } else { 'DISASSOCIATE' })"

# Check elevation
if (-not (Test-IsElevated)) {
    Write-Log "This script must be run as Administrator." -Level 'ERROR'
    throw "Elevation required. Please run this script as Administrator."
}

# Verify pairtool exists (unless report-only)
$pairtoolPath = Join-Path $env:SystemRoot 'System32\pairtool.exe'
if (-not $ReportOnly -and -not (Test-Path $pairtoolPath)) {
    Write-Log "pairtool.exe not found at $pairtoolPath" -Level 'ERROR'
    throw "pairtool.exe is required for remediation but was not found."
}

# Registry path for spooler printers
$printersRegPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers'

if (-not (Test-Path $printersRegPath)) {
    Write-Log "Printers registry key not found: $printersRegPath" -Level 'ERROR'
    throw "Printers registry path does not exist."
}

# Enumerate all printer subkeys
$printerKeys = Get-ChildItem -Path $printersRegPath -ErrorAction SilentlyContinue
$detectedCount = 0
$remediatedCount = 0
$errorCount = 0

# File to record removed printer names (default: C:\Users\Public, accessible to all users)
if (-not $RemovedPrintersPath) {
    $RemovedPrintersPath = Join-Path $env:PUBLIC ("Delete-PerSystemUP_RemovedPrinters_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
$removedPrintersFile = $RemovedPrintersPath
$removedPrinterNames = [System.Collections.Generic.List[string]]::new()

Write-Log "Found $($printerKeys.Count) total printer entries to examine."
Write-Log ("-" * 70)

foreach ($printerKey in $printerKeys) {
    $printerName = $printerKey.PSChildName

    # Skip SID-adorned printers (already per-user)
    if (Test-IsSidAdorned -PrinterName $printerName) {
        continue
    }

    # Check driver name
    try {
        $driverName = (Get-ItemProperty -Path $printerKey.PSPath -Name 'Printer Driver' -ErrorAction SilentlyContinue).'Printer Driver'
    }
    catch {
        continue
    }

    if ($driverName -ne 'Universal Print Class Driver') {
        continue
    }

    # This is a per-system Universal Print printer
    $detectedCount++
    Write-Log "DETECTED per-system UP printer: '$printerName'"

    # Read DeviceContainerId from PnPData subkey
    $pnpDataPath = Join-Path $printerKey.PSPath 'PnPData'
    $aepId = $null

    try {
        if (Test-Path $pnpDataPath) {
            $containerIdBytes = (Get-ItemProperty -Path $pnpDataPath -Name 'DeviceContainerId' -ErrorAction Stop).DeviceContainerId

            if ($containerIdBytes -and $containerIdBytes.Length -eq 16) {
                $guidString = Convert-BinaryToGuid -Bytes $containerIdBytes
                $aepId = "MCP#$guidString"
                Write-Log "  DeviceContainerId : {$guidString}"
                Write-Log "  AEP ID            : $aepId"
            }
            else {
                Write-Log "  DeviceContainerId is missing or unexpected size ($($containerIdBytes.Length) bytes)." -Level 'WARN'
            }

            # Also log the DeviceInstanceId for reference
            $instanceId = (Get-ItemProperty -Path $pnpDataPath -Name 'DeviceInstanceId' -ErrorAction SilentlyContinue).DeviceInstanceId
            if ($instanceId) {
                Write-Log "  DeviceInstanceId  : $instanceId"
            }
        }
        else {
            Write-Log "  PnPData subkey not found for this printer." -Level 'WARN'
        }
    }
    catch {
        Write-Log "  Error reading PnPData: $_" -Level 'ERROR'
        $errorCount++
        continue
    }

    if (-not $aepId) {
        Write-Log "  Could not determine AEP ID. Skipping remediation for this printer." -Level 'WARN'
        continue
    }

    # Also log the port for reference
    try {
        $port = (Get-ItemProperty -Path $printerKey.PSPath -Name 'Port' -ErrorAction SilentlyContinue).Port
        if ($port) {
            Write-Log "  Port              : $port"
        }
    }
    catch { }

    # Remediate
    if ($ReportOnly) {
        Write-Log "  [REPORT ONLY] Would run: pairtool.exe /disassociate $aepId"
    }
    else {
        if ($PSCmdlet.ShouldProcess($printerName, "Disassociate AEP ID '$aepId' via pairtool")) {
            Write-Log "  Executing: pairtool.exe /disassociate $aepId"
            try {
                $result = & $pairtoolPath /disassociate $aepId 2>&1
                $exitCode = $LASTEXITCODE

                foreach ($line in $result) {
                    Write-Log "    pairtool: $line"
                }

                if ($exitCode -eq 0) {
                    Write-Log "  SUCCESS: Disassociated '$printerName'."
                    $remediatedCount++
                    $removedPrinterNames.Add($printerName)
                }
                else {
                    Write-Log "  pairtool /disassociate exited with code $exitCode for '$printerName'." -Level 'WARN'
                    $errorCount++
                }
            }
            catch {
                Write-Log "  Error running pairtool /disassociate: $_" -Level 'ERROR'
                $errorCount++
            }
        }
    }

    Write-Log ("-" * 70)
}

# Summary
Write-Log ""
Write-Log "=== Summary ==="
Write-Log "Total printers examined : $($printerKeys.Count)"
Write-Log "Per-system UP detected  : $detectedCount"
if (-not $ReportOnly) {
    Write-Log "Successfully remediated : $remediatedCount"
}
Write-Log "Errors                  : $errorCount"
Write-Log "Log file                : $LogPath"

# Write removed printer names to the shared temp file
if ($removedPrinterNames.Count -gt 0) {
    try {
        $removedPrinterNames | Out-File -FilePath $removedPrintersFile -Encoding utf8
        Write-Log "List of removed printers: $removedPrintersFile"
    }
    catch {
        Write-Log "Failed to write removed printers file: $_" -Level 'WARN'
    }
}
else {
    Write-Log "No printers were removed; skipping removed-printers file."
}

Write-Log "=== Delete-PerSystemUPPrinters completed ==="
