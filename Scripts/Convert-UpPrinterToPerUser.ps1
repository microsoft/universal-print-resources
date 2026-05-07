# Convert per-system Universal Print printer(s) to per-user installs for all real users,
# or detect per-system UP printers (no elevation required).
#
# Modes:
#   -Detect          Checks for legacy per-system UP printers (no elevation, no SYSTEM, no ShareId/TenantId).
#                    Exit 0 = found, Exit 1 = none found.
#
#   -AllUPPrinters   Converts every per-system UP printer found in the DAF store. Run as SYSTEM.
#
#   (default)        Converts a single per-system printer (-ShareId) to per-user installs. Run as SYSTEM.
#     1. Backs up the per-system DAF entry for MCP#<ShareId> to a .reg file.
#     2. Reads the per-system properties (capabilities, tenant, audience, URL, display name, etc.).
#     3. Disassociates the per-system AEP via pairtool (running as SYSTEM).
#     4. For each real user on the box (loading logged-off hives as needed), writes per-user DAF
#        entries with a freshly-generated instance GUID for each install.
#     5. Restarts DeviceAssociationService and Spooler (once, after all printers are processed).

[CmdletBinding(DefaultParameterSetName = 'ConvertOne')]
param (
    [Parameter(ParameterSetName = 'Detect', Mandatory = $true,
               HelpMessage = "Detect per-system UP printers. Does not require elevation or ShareId/TenantId.")]
    [switch]$Detect,

    [Parameter(ParameterSetName = 'ConvertOne', Mandatory = $true,
               HelpMessage = "ShareId (GUID) of the printer to convert.")]
    [string]$ShareId,

    [Parameter(ParameterSetName = 'ConvertAll', Mandatory = $true,
               HelpMessage = "Convert every per-system UP printer found in the DAF store.")]
    [switch]$AllUPPrinters,

    [Parameter(ParameterSetName = 'ConvertOne', Mandatory = $true,
               HelpMessage = "AAD Tenant ID GUID; written to {93906aa3-...}\0007 for each user.")]
    [Parameter(ParameterSetName = 'ConvertAll', Mandatory = $true,
               HelpMessage = "AAD Tenant ID GUID; written to {93906aa3-...}\0007 for each user, for every printer.")]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'ConvertOne', HelpMessage = "Only target these user SIDs. Omit to target all real users with profiles.")]
    [Parameter(ParameterSetName = 'ConvertAll', HelpMessage = "Only target these user SIDs. Omit to target all real users with profiles.")]
    [string[]]$UserSIDs,

    [Parameter(ParameterSetName = 'ConvertOne', HelpMessage = "Directory for backup .reg files. Defaults to %TEMP%\UPConvert.")]
    [Parameter(ParameterSetName = 'ConvertAll', HelpMessage = "Directory for backup .reg files. Defaults to %TEMP%\UPConvert.")]
    [string]$BackupDir = "$env:TEMP\UPConvert",

    [Parameter(ParameterSetName = 'ConvertOne', HelpMessage = "Dry run. Read state, plan changes, and print what WOULD be done. Make no changes.")]
    [Parameter(ParameterSetName = 'ConvertAll', HelpMessage = "Dry run. Read state, plan changes, and print what WOULD be done. Make no changes.")]
    [switch]$WhatIfMode,

    [Parameter(ParameterSetName = 'ConvertOne', HelpMessage = "Skip the pairtool disassociation step (e.g., if the per-system AEP is already gone).")]
    [Parameter(ParameterSetName = 'ConvertAll', HelpMessage = "Skip the pairtool disassociation step (e.g., if the per-system AEP is already gone).")]
    [switch]$SkipDisassociate,

    [Parameter(ParameterSetName = 'ConvertOne', HelpMessage = "Skip the service restart at the end.")]
    [Parameter(ParameterSetName = 'ConvertAll', HelpMessage = "Skip the service restart at the end.")]
    [switch]$SkipRestart
)

# --- Detect mode (no elevation required) --------------------------------------

if ($Detect) {
    $printersRegPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers'

    if (-not (Test-Path $printersRegPath)) {
        Write-Host "No per-system Universal Print printers found."
        exit 1
    }

    $printerKeys = Get-ChildItem -Path $printersRegPath -ErrorAction SilentlyContinue
    $detectedCount = 0

    foreach ($printerKey in $printerKeys) {
        $printerName = $printerKey.PSChildName

        # Skip SID-adorned printers (already per-user)
        if ($printerName -match '^S-1-\d+-\d+') {
            continue
        }

        # Check driver name
        try {
            $driverName = (Get-ItemProperty -Path $printerKey.PSPath -Name 'Printer Driver' -ErrorAction SilentlyContinue).'Printer Driver'
        }
        catch {
            continue
        }

        if ($driverName -eq 'Universal Print Class Driver') {
            Write-Host "  Found: $printerName" -ForegroundColor DarkGray
            $detectedCount++
        }
    }

    if ($detectedCount -gt 0) {
        Write-Host "Yes, per-system Universal Print printers were found. Count: $detectedCount"
        exit 0
    }
    else {
        Write-Host "No per-system Universal Print printers found."
        exit 1
    }
}

# --- Constants ----------------------------------------------------------------

# DEVPROP categories (from devpkey.h / DAF):
$CAT_PNP_INSTANCE   = '{3b2ce006-5e61-4fde-bab8-9b8aac9b26df}'  # PnP container/device instance
$CAT_PRINT_DEVICEID = '{87b5d949-b013-46fe-8410-01d2b5474b7b}'  # Print device ID/capabilities
$CAT_AUTH           = '{93906aa3-c281-43a8-816c-f6c1dd94c442}'  # Auth (authority/tenant/audience/...)
$CAT_PRINTER_URL    = '{a35996ab-11cf-4935-8b61-a6761081ecdf}'  # Printer URL category
$CAT_AEP_IDENTITY   = '{e7c3fb29-caa7-4f47-8c8b-be59b330d4c5}'  # AEP unique GUID + display name
$CAT_RESERVED_USER  = '{7a42a889-79a7-43a7-91eb-0411e984dac6}'  # Per-user only (empty string)
$CAT_RESERVED_AB    = '{a45c254e-df1c-4efd-8020-67d146a850e0}'  # Reserved (empty/INT32 3)

# SWD#MCP# subkey categories:
$CAT_SWD_DEVPATH    = '{78c34fc8-104a-4aca-9ea4-524d52996e57}'  # SWD\MCP\<id>
$CAT_SWD_AEPGUID    = '{8c7ed206-3f8a-4827-b3ab-ae9e1faefc6c}'  # AEP GUID

# DEVPROP type DWORDs (must include the 0xFFFF**** magic — that's how the
# registry distinguishes a DEVPROP type from a stock REG_* type).
# Use [Convert]::ToUInt32 because PowerShell parses 0xFFFF**** literals as Int32 and they overflow.
$DEVPROP_BYTE        = [Convert]::ToUInt32('FFFF0011', 16)
$DEVPROP_STRING      = [Convert]::ToUInt32('FFFF0012', 16)
$DEVPROP_STRING_LIST = [Convert]::ToUInt32('FFFF2012', 16)  # STRING with TYPEMOD_LIST
$DEVPROP_GUID        = [Convert]::ToUInt32('FFFF000D', 16)
$DEVPROP_INT32       = [Convert]::ToUInt32('FFFF0007', 16)

$REG_PERSYS_BASE  = 'HKLM\SYSTEM\CurrentControlSet\Services\DeviceAssociationService\State\Store'
$REG_PERUSR_BASE_REL = 'Software\Microsoft\Device Association Framework\Store'

# --- Validation ---------------------------------------------------------------

$guidRegex = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
if ($PSCmdlet.ParameterSetName -eq 'ConvertOne' -and $ShareId -notmatch $guidRegex) {
    Write-Host "ERROR: ShareId '$ShareId' is not a valid GUID." -ForegroundColor Red
    exit 1
}
if ($TenantId -notmatch $guidRegex) {
    Write-Host "ERROR: TenantId '$TenantId' is not a valid GUID." -ForegroundColor Red
    exit 1
}

if (-not $WhatIfMode) {
    $whoami = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    if ($whoami -ne 'NT AUTHORITY\SYSTEM') {
        Write-Host "ERROR: This script must run as NT AUTHORITY\SYSTEM (currently '$whoami')." -ForegroundColor Red
        Write-Host "       Use ``psexec -s -i pwsh`` to get a SYSTEM PowerShell prompt." -ForegroundColor Yellow
        exit 1
    }
}

if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}

# --- Helpers (hive load/unload, copied/adapted from upcleanup.ps1) ------------

function Get-AllRealUserSIDs {
    # User profiles from ProfileList: S-1-5-21-* (domain/local) and S-1-12-1-* (Entra/AAD).
    $sids = @()
    $result = reg query 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' 2>$null
    if ($result) {
        foreach ($line in $result) {
            if ($line.Trim() -match 'ProfileList\\(S-1-(?:5-21|12-1)-[\d-]+)$') {
                $sids += $Matches[1]
            }
        }
    }
    return $sids
}

function Get-AllPerSystemShareIds {
    # Enumerate all MCP#<ShareId> subkeys under the per-system DAF store. Returns
    # an array of bare ShareId GUID strings (no MCP# prefix).
    $shareIds = @()
    $result = reg query $REG_PERSYS_BASE 2>$null
    if ($result) {
        foreach ($line in $result) {
            if ($line.Trim() -match 'MCP#([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$') {
                $shareIds += $Matches[1]
            }
        }
    }
    return $shareIds
}

function Get-ProfileImagePath {
    param ([string]$UserSID)
    $out = reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$UserSID" /v ProfileImagePath 2>$null
    if ($out) {
        $m = [regex]::Match(($out -join "`n"), 'ProfileImagePath\s+REG_EXPAND_SZ\s+(.+)')
        if ($m.Success) { return $m.Groups[1].Value.Trim() }
    }
    return $null
}

function Test-HiveLoaded {
    param ([string]$UserSID)
    $null = reg query "HKU\$UserSID" /ve 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Mount-UserHive {
    # Returns $true if WE loaded it (caller should unload), $false if it was already loaded or failed.
    param ([string]$UserSID)
    if (Test-HiveLoaded -UserSID $UserSID) { return $false }
    $profilePath = Get-ProfileImagePath -UserSID $UserSID
    if (-not $profilePath) {
        Write-Host "  WARN: No ProfileImagePath for $UserSID." -ForegroundColor Yellow
        return $false
    }
    $ntuser = Join-Path $profilePath 'NTUSER.DAT'
    if (-not (Test-Path -LiteralPath $ntuser)) {
        Write-Host "  WARN: NTUSER.DAT not found at $ntuser." -ForegroundColor Yellow
        return $false
    }
    Write-Host "  Loading hive HKU\$UserSID from $ntuser" -ForegroundColor DarkGray
    $null = reg load "HKU\$UserSID" $ntuser 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Dismount-UserHive {
    param ([string]$UserSID)
    [gc]::Collect(); [gc]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds 500
    $null = reg unload "HKU\$UserSID" 2>$null
}

# --- .reg parser: extract DEVPROP values from a per-system MCP export ---------

function Read-DafExport {
    # Returns a hashtable keyed by "<categoryGuid>\<PID>" → @{ Type = uint32; Bytes = byte[] }
    param ([string]$RegFilePath, [string]$AnchorMcpKey)

    $lines = [IO.File]::ReadAllLines($RegFilePath, [Text.Encoding]::Unicode)
    $props = @{}
    $currentSubpath = $null  # path under MCP#<ShareId>

    $hexLineRegex = '^\s*(?<name>@|"[^"]*")\s*=\s*hex\((?<type>[0-9a-fA-F]+)\)\s*:\s*(?<rest>.*)$'
    $keyHeaderRegex = '^\[(?<path>[^\]]+)\]\s*$'

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        if ($line -match $keyHeaderRegex) {
            $fullPath = $Matches['path']
            # Anchor under the MCP key for this ShareId; track sub-path
            $idx = $fullPath.IndexOf($AnchorMcpKey, [StringComparison]::OrdinalIgnoreCase)
            if ($idx -ge 0) {
                $tail = $fullPath.Substring($idx + $AnchorMcpKey.Length).TrimStart('\')
                $currentSubpath = $tail
            } else {
                $currentSubpath = $null
            }
            continue
        }

        if (-not $currentSubpath) { continue }

        if ($line -match $hexLineRegex) {
            $typeHex = $Matches['type']
            $rest = $Matches['rest']

            # Collect line continuations (trailing backslash)
            $accum = $rest
            while ($accum.TrimEnd() -match '\\$') {
                $accum = $accum.TrimEnd().TrimEnd('\')
                $i++
                if ($i -ge $lines.Count) { break }
                $accum += $lines[$i].TrimStart()
            }

            # Parse hex bytes
            $tokens = @($accum -split '[,\s\\]+' | Where-Object { $_ -match '^[0-9a-fA-F]{1,2}$' })
            $bytes = @()
            if ($tokens.Count -gt 0) {
                $bytes = [byte[]]@($tokens | ForEach-Object { [Convert]::ToByte($_, 16) })
            }
            $type = [Convert]::ToUInt32($typeHex, 16)

            # Key is the sub-path (e.g. "Properties\{cat}\PID")
            $props[$currentSubpath] = @{ Type = $type; Bytes = $bytes }
        }
    }

    return $props
}

# --- Encoding helpers for building per-user .reg content ----------------------

function Convert-StringToUtf16Bytes {
    # Returns UTF-16LE bytes including a trailing null terminator (2 bytes of 0).
    param ([string]$Text)
    $b = [Text.Encoding]::Unicode.GetBytes($Text)
    return $b + [byte[]](0, 0)
}

function Convert-StringListToUtf16Bytes {
    # MULTI_SZ-style: each string null-terminated, then an extra null terminator at the end.
    param ([string[]]$Strings)
    $out = New-Object System.Collections.Generic.List[byte]
    foreach ($s in $Strings) {
        $b = [Text.Encoding]::Unicode.GetBytes($s)
        $out.AddRange($b)
        $out.Add(0); $out.Add(0)
    }
    # Final terminator
    $out.Add(0); $out.Add(0)
    return ,([byte[]]$out.ToArray())
}

function Convert-GuidToBytes {
    # Returns the 16-byte little-endian GUID encoding (matches Microsoft's stored format).
    param ([string]$GuidStr)
    return [Guid]::new($GuidStr).ToByteArray()
}

function Format-RegHexLine {
    # Format a .reg line: '@=hex(TYPE):bb,bb,bb' wrapped with backslash continuations every ~22 bytes.
    param (
        [uint32]$TypeDword,
        [byte[]]$Bytes,
        [string]$ValueName = '@'
    )
    $prefix = if ($ValueName -eq '@') { '@' } else { "`"$ValueName`"" }
    $head = "{0}=hex({1:x8}):" -f $prefix, $TypeDword
    if (-not $Bytes -or $Bytes.Count -eq 0) { return "$head" }

    $tokens = @($Bytes | ForEach-Object { '{0:x2}' -f $_ })
    # First-line budget: aim for ~76 chars total per line (matches reg export style)
    $line = $head
    $sb = New-Object System.Text.StringBuilder
    $tokensPerLine = 22  # rough match to reg export
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $tok = $tokens[$i]
        $isLast = ($i -eq $tokens.Count - 1)
        $atWrap = ((($i + 1) % $tokensPerLine) -eq 0)
        if (-not $isLast -and $atWrap) {
            [void]$sb.Append($tok).Append(",\`r`n  ")
        } elseif ($isLast) {
            [void]$sb.Append($tok)
        } else {
            [void]$sb.Append($tok).Append(',')
        }
    }
    return "$line$($sb.ToString())"
}

# --- Build the per-user .reg payload for one user/install ---------------------

function Build-PerUserRegContent {
    param (
        [string]$UserSID,
        [string]$ShareId,
        [string]$InstanceGuid,           # New per-install GUID, formatted "{xxxx-...}"
        [string]$TenantId,               # AAD tenant for {93906aa3-...}\0007
        [hashtable]$PerSystem            # output of Read-DafExport for the per-system MCP
    )

    $base = "HKEY_USERS\$UserSID\$REG_PERUSR_BASE_REL\MCP#$ShareId"

    # Pull values from per-system. Each cell is a hashtable @{Type=...; Bytes=...} or $null.
    function Get-PerSys([string]$relPath) {
        if ($PerSystem.ContainsKey($relPath)) { return $PerSystem[$relPath] }
        return $null
    }

    $shareGuidBytes = Convert-GuidToBytes $ShareId

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("Windows Registry Editor Version 5.00")
    [void]$sb.AppendLine()

    # Parent keys (so reg import creates them if missing)
    $parents = @(
        "HKEY_USERS\$UserSID\Software\Microsoft\Device Association Framework",
        "HKEY_USERS\$UserSID\Software\Microsoft\Device Association Framework\Store",
        $base,
        "$base\Properties"
    )
    foreach ($p in $parents) {
        [void]$sb.AppendLine("[$p]")
        [void]$sb.AppendLine()
    }

    # Helper to emit one property block: [key]\r\n@=hex(type):bytes\r\n
    function Add-Prop {
        param ([string]$KeyPath, [uint32]$Type, [byte[]]$Bytes)
        [void]$sb.AppendLine("[$KeyPath]")
        [void]$sb.AppendLine((Format-RegHexLine -TypeDword $Type -Bytes $Bytes))
        [void]$sb.AppendLine()
    }

    # ---- {3b2ce006-...}\0006 (STRING_LIST) = "SWD\MCP\{InstanceGuid}"
    Add-Prop -KeyPath "$base\Properties\$CAT_PNP_INSTANCE\0006" `
        -Type $DEVPROP_STRING_LIST `
        -Bytes (Convert-StringListToUtf16Bytes @("SWD\MCP\$InstanceGuid"))

    # ---- {3b2ce006-...}\0007 (STRING_LIST) = "{InstanceGuid}"
    Add-Prop -KeyPath "$base\Properties\$CAT_PNP_INSTANCE\0007" `
        -Type $DEVPROP_STRING_LIST `
        -Bytes (Convert-StringListToUtf16Bytes @($InstanceGuid))

    # ---- {3b2ce006-...}\000A (GUID) = ShareId-as-GUID
    Add-Prop -KeyPath "$base\Properties\$CAT_PNP_INSTANCE\000A" `
        -Type $DEVPROP_GUID -Bytes $shareGuidBytes

    # ---- {7a42a889-...}\000A (STRING) = empty
    Add-Prop -KeyPath "$base\Properties\$CAT_RESERVED_USER\000A" `
        -Type $DEVPROP_STRING -Bytes ([byte[]](0,0))

    # ---- {87b5d949-...}\0010 (STRING) = printer capabilities (from per-system)
    $cap = Get-PerSys "Properties\$CAT_PRINT_DEVICEID\0010"
    if ($cap) {
        Add-Prop -KeyPath "$base\Properties\$CAT_PRINT_DEVICEID\0010" `
            -Type $cap.Type -Bytes $cap.Bytes
    }

    # ---- {93906aa3-...}\0002 (STRING) = authority URL (from per-system)
    $auth = Get-PerSys "Properties\$CAT_AUTH\0002"
    if ($auth) {
        Add-Prop -KeyPath "$base\Properties\$CAT_AUTH\0002" `
            -Type $auth.Type -Bytes $auth.Bytes
    }

    # ---- {93906aa3-...}\0003 (STRING) = printer tenant ID (from per-system)
    $ptenant = Get-PerSys "Properties\$CAT_AUTH\0003"
    if ($ptenant) {
        Add-Prop -KeyPath "$base\Properties\$CAT_AUTH\0003" `
            -Type $ptenant.Type -Bytes $ptenant.Bytes
    }

    # ---- {93906aa3-...}\0004 (STRING) = audience (from per-system)
    $aud = Get-PerSys "Properties\$CAT_AUTH\0004"
    if ($aud) {
        Add-Prop -KeyPath "$base\Properties\$CAT_AUTH\0004" `
            -Type $aud.Type -Bytes $aud.Bytes
    }

    # ---- {93906aa3-...}\0005 (BYTE) = 0xFF (from per-system)
    $b5 = Get-PerSys "Properties\$CAT_AUTH\0005"
    if ($b5) {
        Add-Prop -KeyPath "$base\Properties\$CAT_AUTH\0005" `
            -Type $b5.Type -Bytes $b5.Bytes
    } else {
        Add-Prop -KeyPath "$base\Properties\$CAT_AUTH\0005" `
            -Type $DEVPROP_BYTE -Bytes ([byte[]](0xFF))
    }

    # ---- {93906aa3-...}\0007 (STRING) = AAD Tenant ID (from -TenantId param)
    Add-Prop -KeyPath "$base\Properties\$CAT_AUTH\0007" `
        -Type $DEVPROP_STRING -Bytes (Convert-StringToUtf16Bytes $TenantId)

    # ---- {a35996ab-...}\000C (STRING) = printer URL (from per-system)
    $url = Get-PerSys "Properties\$CAT_PRINTER_URL\000C"
    if ($url) {
        Add-Prop -KeyPath "$base\Properties\$CAT_PRINTER_URL\000C" `
            -Type $url.Type -Bytes $url.Bytes
    }

    # ---- {a35996ab-...}\0010 (BYTE) = 0xFF
    $u10 = Get-PerSys "Properties\$CAT_PRINTER_URL\0010"
    if ($u10) {
        Add-Prop -KeyPath "$base\Properties\$CAT_PRINTER_URL\0010" `
            -Type $u10.Type -Bytes $u10.Bytes
    } else {
        Add-Prop -KeyPath "$base\Properties\$CAT_PRINTER_URL\0010" `
            -Type $DEVPROP_BYTE -Bytes ([byte[]](0xFF))
    }

    # ---- {a45c254e-...}\0002 (STRING) = empty
    Add-Prop -KeyPath "$base\Properties\$CAT_RESERVED_AB\0002" `
        -Type $DEVPROP_STRING -Bytes ([byte[]](0,0))

    # ---- {e7c3fb29-...}\0002 (GUID) = ShareId-as-GUID
    Add-Prop -KeyPath "$base\Properties\$CAT_AEP_IDENTITY\0002" `
        -Type $DEVPROP_GUID -Bytes $shareGuidBytes

    # ---- {e7c3fb29-...}\0004 (STRING) = display name (from per-system)
    $dn = Get-PerSys "Properties\$CAT_AEP_IDENTITY\0004"
    if ($dn) {
        Add-Prop -KeyPath "$base\Properties\$CAT_AEP_IDENTITY\0004" `
            -Type $dn.Type -Bytes $dn.Bytes
    }

    # ---- SWD#MCP#{InstanceGuid} subkey + properties --------------------------
    $swd = "$base\SWD#MCP#$InstanceGuid"
    [void]$sb.AppendLine("[$swd]"); [void]$sb.AppendLine()
    [void]$sb.AppendLine("[$swd\Properties]"); [void]$sb.AppendLine()

    # SWD\{78c34fc8-...}\0100 (STRING) = "SWD\MCP\{InstanceGuid}"
    Add-Prop -KeyPath "$swd\Properties\$CAT_SWD_DEVPATH\0100" `
        -Type $DEVPROP_STRING -Bytes (Convert-StringToUtf16Bytes "SWD\MCP\$InstanceGuid")

    # SWD\{8c7ed206-...}\0002 (GUID) = ShareId-as-GUID
    Add-Prop -KeyPath "$swd\Properties\$CAT_SWD_AEPGUID\0002" `
        -Type $DEVPROP_GUID -Bytes $shareGuidBytes

    # SWD\{a45c254e-...}\0011 (INT32) = 3
    Add-Prop -KeyPath "$swd\Properties\$CAT_RESERVED_AB\0011" `
        -Type $DEVPROP_INT32 `
        -Bytes ([BitConverter]::GetBytes([int32]3))

    return $sb.ToString()
}

# --- Main ---------------------------------------------------------------------

function Convert-OnePrinter {
    param (
        [Parameter(Mandatory = $true)][string]$ShareId,
        [Parameter(Mandatory = $true)][string]$TenantId,
        [Parameter(Mandatory = $true)][string[]]$TargetSIDs,
        [Parameter(Mandatory = $true)][string]$Timestamp,
        [Parameter(Mandatory = $true)][string]$BackupDir,
        [switch]$WhatIfMode,
        [switch]$SkipDisassociate
    )

    $regPerSysKey = "$REG_PERSYS_BASE\MCP#$ShareId"
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "Converting printer ShareId: $ShareId" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    # 1) Verify per-system entry exists
    $null = reg query $regPerSysKey 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Per-system DAF entry not found: $regPerSysKey" -ForegroundColor Red
        return [pscustomobject]@{ ShareId = $ShareId; Success = $false; Error = 'no DAF entry'; Installs = @() }
    }

    # 2) Backup per-system entry
    $backupFile = Join-Path $BackupDir "PerSystem-MCP-$ShareId-$Timestamp.reg"
    Write-Host "Step 1: Exporting per-system DAF entry to backup..." -ForegroundColor Cyan
    Write-Host "  $backupFile"
    $null = reg export $regPerSysKey $backupFile /y 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: reg export failed for $regPerSysKey" -ForegroundColor Red
        return [pscustomobject]@{ ShareId = $ShareId; Success = $false; Error = 'export failed'; Installs = @() }
    }

    # 3) Parse per-system properties
    Write-Host "Step 2: Parsing per-system DAF properties..." -ForegroundColor Cyan
    $perSystem = Read-DafExport -RegFilePath $backupFile -AnchorMcpKey "MCP#$ShareId"
    if ($perSystem.Count -eq 0) {
        Write-Host "ERROR: No DAF properties parsed from $backupFile" -ForegroundColor Red
        return [pscustomobject]@{ ShareId = $ShareId; Success = $false; Error = 'parse failed'; Installs = @() }
    }
    Write-Host "  Found $($perSystem.Count) properties."

    # 4) Disassociate per-system AEP via pairtool
    if (-not $SkipDisassociate) {
        Write-Host "Step 3: Disassociating per-system AEP via pairtool..." -ForegroundColor Cyan
        $pairtool = "$env:SystemRoot\System32\pairtool.exe"
        if (-not (Test-Path $pairtool)) {
            Write-Host "ERROR: pairtool.exe not found at $pairtool." -ForegroundColor Red
            return [pscustomobject]@{ ShareId = $ShareId; Success = $false; Error = 'pairtool missing'; Installs = @() }
        }
        if ($WhatIfMode) {
            Write-Host "  [WHATIF] Would run: $pairtool -disassociate `"MCP#$ShareId`""
        } else {
            Write-Host "  Running: $pairtool -disassociate `"MCP#$ShareId`""
            # Capture stdout/stderr so it doesn't leak into the function's pipeline output
            # (otherwise pairtool's text lines get returned alongside our [pscustomobject] result).
            $pairtoolOutput = & $pairtool -disassociate "MCP#$ShareId" 2>&1
            $rc = $LASTEXITCODE
            foreach ($line in $pairtoolOutput) {
                Write-Host "    $line" -ForegroundColor DarkGray
            }
            if ($rc -ne 0) {
                Write-Host "  WARN: pairtool returned 0x$($rc.ToString('X8')). Continuing anyway." -ForegroundColor Yellow
            } else {
                Write-Host "  Disassociation succeeded." -ForegroundColor Green
            }
        }
    } else {
        Write-Host "Step 3: Skipping pairtool disassociation (-SkipDisassociate)." -ForegroundColor Yellow
    }

    # 5) For each user, write per-user DAF entry
    Write-Host "Step 4: Writing per-user DAF entries..." -ForegroundColor Cyan
    $installs = @()
    foreach ($sid in $TargetSIDs) {
        Write-Host ""
        Write-Host "  User: $sid" -ForegroundColor White
        $weLoaded = $false
        try {
            if (-not (Test-HiveLoaded -UserSID $sid)) {
                $weLoaded = Mount-UserHive -UserSID $sid
                if (-not (Test-HiveLoaded -UserSID $sid)) {
                    Write-Host "    SKIP: hive not available for $sid." -ForegroundColor Yellow
                    continue
                }
            }

            $instanceGuid = "{$([Guid]::NewGuid().ToString())}"
            $regContent = Build-PerUserRegContent `
                -UserSID $sid `
                -ShareId $ShareId `
                -InstanceGuid $instanceGuid `
                -TenantId $TenantId `
                -PerSystem $perSystem

            $regFile = Join-Path $BackupDir "PerUser-$sid-MCP-$ShareId-$Timestamp.reg"
            $writer = [IO.StreamWriter]::new($regFile, $false, [Text.UnicodeEncoding]::new($false, $true))
            $writer.NewLine = "`r`n"
            $writer.Write($regContent)
            $writer.Dispose()
            Write-Host "    Generated: $regFile" -ForegroundColor DarkGray
            Write-Host "    Instance GUID: $instanceGuid"

            if ($WhatIfMode) {
                Write-Host "    [WHATIF] Would import the .reg file above."
            } else {
                $null = reg import $regFile 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "    Imported successfully." -ForegroundColor Green
                    $installs += [pscustomobject]@{ SID = $sid; InstanceGuid = $instanceGuid; RegFile = $regFile }
                } else {
                    Write-Host "    ERROR: reg import failed (exit $LASTEXITCODE)." -ForegroundColor Red
                }
            }
        }
        finally {
            if ($weLoaded) { Dismount-UserHive -UserSID $sid }
        }
    }

    return [pscustomobject]@{ ShareId = $ShareId; Success = $true; Backup = $backupFile; Installs = $installs }
}

# --- Resolve ShareIds to convert ---------------------------------------------

if ($PSCmdlet.ParameterSetName -eq 'ConvertAll') {
    $shareIdsToConvert = @(Get-AllPerSystemShareIds)
} else {
    $shareIdsToConvert = @($ShareId)
}

Write-Host "=== Convert per-system UP printer(s) to per-user ===" -ForegroundColor Cyan
Write-Host "  Mode           : $($PSCmdlet.ParameterSetName)$(if ($WhatIfMode) { ' (WHATIF)' } else { '' })"
Write-Host "  TenantId param : $TenantId"
Write-Host "  Backup dir     : $BackupDir"
Write-Host "  ShareId(s)     : $($shareIdsToConvert.Count) printer(s)"
foreach ($s in $shareIdsToConvert) { Write-Host "    $s" -ForegroundColor DarkGray }
Write-Host ""

if ($shareIdsToConvert.Count -eq 0) {
    Write-Host "No per-system UP printers found in $REG_PERSYS_BASE. Nothing to do." -ForegroundColor Yellow
    exit 0
}

# --- Resolve target users (once) ---------------------------------------------

Write-Host "Resolving target users..." -ForegroundColor Cyan
if ($UserSIDs -and $UserSIDs.Count -gt 0) {
    $targetSIDs = $UserSIDs
    Write-Host "  Using -UserSIDs filter: $($targetSIDs -join ', ')"
} else {
    $targetSIDs = @(Get-AllRealUserSIDs)
    Write-Host "  Found $($targetSIDs.Count) real user profile(s)."
}
foreach ($s in $targetSIDs) { Write-Host "    $s" -ForegroundColor DarkGray }

if ($targetSIDs.Count -eq 0) {
    Write-Host "No target users. Exiting." -ForegroundColor Yellow
    exit 0
}

# --- Convert each printer ----------------------------------------------------

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$results = @()
foreach ($sid in $shareIdsToConvert) {
    # Force scalar capture: if Convert-OnePrinter ever leaks stdout, $r could become an array.
    # Wrap with @(...) and grab the last element (the [pscustomobject] result we explicitly return).
    $r = @(Convert-OnePrinter -ShareId $sid -TenantId $TenantId -TargetSIDs $targetSIDs `
                              -Timestamp $timestamp -BackupDir $BackupDir `
                              -WhatIfMode:$WhatIfMode -SkipDisassociate:$SkipDisassociate)
    $results += ,($r[-1])
}

# --- Restart services (once) -------------------------------------------------

if (-not $SkipRestart -and -not $WhatIfMode) {
    Write-Host ""
    Write-Host "Restarting services..." -ForegroundColor Cyan
    foreach ($svc in @('DeviceAssociationService', 'Spooler')) {
        Write-Host "  Restarting $svc..."
        try {
            Restart-Service -Name $svc -Force -ErrorAction Stop
            Write-Host "    OK." -ForegroundColor Green
        } catch {
            Write-Host "    WARN: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
} elseif ($SkipRestart) {
    Write-Host ""
    Write-Host "Skipping service restart (-SkipRestart)." -ForegroundColor Yellow
}

# --- Summary -----------------------------------------------------------------

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
$succeeded = @($results | Where-Object { $_.Success })
$failed    = @($results | Where-Object { -not $_.Success })
Write-Host "  Printers processed : $($results.Count)"
Write-Host "  Succeeded          : $($succeeded.Count)"
Write-Host "  Failed             : $($failed.Count)"
foreach ($r in $succeeded) {
    Write-Host ("    [{0}]  installs={1}/{2}  backup={3}" -f $r.ShareId, $r.Installs.Count, $targetSIDs.Count, $r.Backup) -ForegroundColor Green
}
foreach ($r in $failed) {
    Write-Host ("    [{0}]  FAILED: {1}" -f $r.ShareId, $r.Error) -ForegroundColor Red
}
Write-Host "Done."