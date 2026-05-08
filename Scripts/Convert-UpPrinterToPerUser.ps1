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
# SIG # Begin signature block
# MIIoKwYJKoZIhvcNAQcCoIIoHDCCKBgCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCALIohlUzqwUvan
# YjYBi+jEwBxlpdYwcazmkgBQB8GZtKCCDXYwggX0MIID3KADAgECAhMzAAAEhV6Z
# 7A5ZL83XAAAAAASFMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjUwNjE5MTgyMTM3WhcNMjYwNjE3MTgyMTM3WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDASkh1cpvuUqfbqxele7LCSHEamVNBfFE4uY1FkGsAdUF/vnjpE1dnAD9vMOqy
# 5ZO49ILhP4jiP/P2Pn9ao+5TDtKmcQ+pZdzbG7t43yRXJC3nXvTGQroodPi9USQi
# 9rI+0gwuXRKBII7L+k3kMkKLmFrsWUjzgXVCLYa6ZH7BCALAcJWZTwWPoiT4HpqQ
# hJcYLB7pfetAVCeBEVZD8itKQ6QA5/LQR+9X6dlSj4Vxta4JnpxvgSrkjXCz+tlJ
# 67ABZ551lw23RWU1uyfgCfEFhBfiyPR2WSjskPl9ap6qrf8fNQ1sGYun2p4JdXxe
# UAKf1hVa/3TQXjvPTiRXCnJPAgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUuCZyGiCuLYE0aU7j5TFqY05kko0w
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzUwNTM1OTAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBACjmqAp2Ci4sTHZci+qk
# tEAKsFk5HNVGKyWR2rFGXsd7cggZ04H5U4SV0fAL6fOE9dLvt4I7HBHLhpGdE5Uj
# Ly4NxLTG2bDAkeAVmxmd2uKWVGKym1aarDxXfv3GCN4mRX+Pn4c+py3S/6Kkt5eS
# DAIIsrzKw3Kh2SW1hCwXX/k1v4b+NH1Fjl+i/xPJspXCFuZB4aC5FLT5fgbRKqns
# WeAdn8DsrYQhT3QXLt6Nv3/dMzv7G/Cdpbdcoul8FYl+t3dmXM+SIClC3l2ae0wO
# lNrQ42yQEycuPU5OoqLT85jsZ7+4CaScfFINlO7l7Y7r/xauqHbSPQ1r3oIC+e71
# 5s2G3ClZa3y99aYx2lnXYe1srcrIx8NAXTViiypXVn9ZGmEkfNcfDiqGQwkml5z9
# nm3pWiBZ69adaBBbAFEjyJG4y0a76bel/4sDCVvaZzLM3TFbxVO9BQrjZRtbJZbk
# C3XArpLqZSfx53SuYdddxPX8pvcqFuEu8wcUeD05t9xNbJ4TtdAECJlEi0vvBxlm
# M5tzFXy2qZeqPMXHSQYqPgZ9jvScZ6NwznFD0+33kbzyhOSz/WuGbAu4cHZG8gKn
# lQVT4uA2Diex9DMs2WHiokNknYlLoUeWXW1QrJLpqO82TLyKTbBM/oZHAdIc0kzo
# STro9b3+vjn2809D0+SOOCVZMIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
# hkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
# IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQg
# Q29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03
# a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akr
# rnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0Rrrg
# OGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy
# 4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9
# sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAh
# dCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8k
# A/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTB
# w3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmn
# Eyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90
# lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0w
# ggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2o
# ynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBa
# BgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsG
# AQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNV
# HSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsG
# AQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABl
# AG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKb
# C5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11l
# hJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6
# I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0
# wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560
# STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQam
# ASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGa
# J+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ah
# XJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA
# 9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33Vt
# Y5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr
# /Xmfwb1tbWrJUnMTDXpQzTGCGgswghoHAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAASFXpnsDlkvzdcAAAAABIUwDQYJYIZIAWUDBAIB
# BQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIKgX+yeuaKJ7S13ixYqDqZxC
# 62xxBMCu7khI81jkG2NgMEQGCisGAQQBgjcCAQwxNjA0oBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEcgBpodHRwczovL3d3dy5taWNyb3NvZnQuY29tIDANBgkqhkiG9w0B
# AQEFAASCAQCYc4OD/AHYBBaGHyQAirNPZyUlTZChuIJkfoaW6hhBHdkKhHdzKrVH
# zt24rR2E8pptkYwcfoYuLbLhuyKQHlub9LbQKZY08izLlmHr4vA/OSEb+sjwUDrD
# 0S8nZvc3zeVxsBapOLHOYgAtOfamX3+oEK3Sjr+XX8K09l0mBtHfLK8t+GEqckLz
# Y7+UKNdsY8jQ5+LRsQ7LuV4IHuzkMMAUZ4bfbrejxF9jV2AWdMasSJRe4wLkRviZ
# lhI41i4AlWYREE4XGzuMRXupURyO/Zuo83zV3kuLK9VRU/UPeOneBnSfMaY6AZfb
# kKBueBDg9VUsoFyzKJ/L71+cDBSsW0YaoYIXkzCCF48GCisGAQQBgjcDAwExghd/
# MIIXewYJKoZIhvcNAQcCoIIXbDCCF2gCAQMxDzANBglghkgBZQMEAgEFADCCAU4G
# CyqGSIb3DQEJEAEEoIIBPQSCATkwggE1AgEBBgorBgEEAYRZCgMBMDEwDQYJYIZI
# AWUDBAIBBQAEIFFyKlM18t2NxcXz7c5BpAjNXtqiyCDeJPH0iKnYITGtAgZp58Kn
# 7fwYDzIwMjYwNTA3MjM0NjAwWjAEgAIB9KCB0aSBzjCByzELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJp
# Y2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjM3MDMtMDVF
# MC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR
# 7TCCByAwggUIoAMCAQICEzMAAAIfOnBp5KIwLpUAAQAAAh8wDQYJKoZIhvcNAQEL
# BQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMjYwMjE5MTkzOTUx
# WhcNMjcwNTE3MTkzOTUxWjCByzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEn
# MCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjM3MDMtMDVFMC1EOTQ3MSUwIwYDVQQD
# ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEF
# AAOCAg8AMIICCgKCAgEAyzvFxTnHxqgKoIs9PgJkJhZd3WdGkxuFBSZKqjXTB8tv
# A2oXggbOjjbn7pMnuceNglpM4ESMvZBNlVsBJ7WfGZIMq8pAtGyKrCA+/uhcYLrH
# k139VcL5tQ/NdOFZnraASZSeLhm7siWVL1w8eeZ1YedMoC082duFpELJz6b0Wb9p
# D3N/X924S8h1bZx7Gv1v/Ola37XfgHxb3gPqjfxGPlxo+XPwzzFwmBAm9Gq2G/dn
# QyVrcM6cga6eIHx5YGNVBKXOJeABhC639ieMK8U801vkjPF4VdXTjj62Iw9PNCG2
# ai/AfiBdEQnZ9uvWF6xiukCB4qc5ymXAkvIzd9GAB50yVTeWc7Orf9mLKgRg6rrw
# 2ne/d+BRU8M71HDt1aCMnfd11sLz/P0ghVSYdtVvKBkE6bRh8pcvhZeIXp1TFWRd
# b+qLDrYq1/BhU4hIZ3/J0XToO8mWACdMcvQrQ3212k5/3H9y6tzfxgmChYwvuZlA
# hPgCYZsTLjHb0lBpiogBXYjwI1E6rFlgQWSZtHgsIHhiRZpkAPle//fASnBPoFC+
# zvXlkQ0MCngHL6Oq8Tb9mOIyqxwOmf8It2v3ylISwjWREvKhna6QwJu6ofuhY2Mc
# rQG5IijOrkzcv1Cz5cLZWGaACQw0D+3mAssMFWzU2x10QUkvjXHAtLEgeFu1Ou8C
# AwEAAaOCAUkwggFFMB0GA1UdDgQWBBTZO9rBg5R9K+Q8L3xkeV8CSPAe2zAfBgNV
# HSMEGDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5o
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBU
# aW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwG
# CCsGAQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRz
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNV
# HRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIH
# gDANBgkqhkiG9w0BAQsFAAOCAgEAZW7tyKMp5z89CtYj23jZ7Ho9m9eZebHZdhQB
# QQRk/ZUXXNoDVfCwCLrD2Bx4VL0Q3LMeJWzDYVSjxruEwy2qjbfwiPkhbRrqnUS6
# VT9VxPXAi8iqyj6XCRSQqj6Vfnn6ALWAZiFEHMccE+1iEO4GoPPq5Cr6zJAqEaik
# tJir/CdbCn4vOfhtroWf9UbXklXWGTmTo/km+MM6J0wk4+xLYDDfwV9+VuXU83e8
# CXRnqWJFYvO9XUqwtk69WRcwEe0uOHawlmaSeqYSWm1TTrDcRSSoEspLoDhls0N9
# fEa9zEz4NrNwZ7PqVD1YDIo3eG1Dh9gZRLCzDMDnKJU02aoNR2K3WNY8aVACPYqY
# wUESDS/zu9OWfv39i4zZiUKKAlSVV9uGnaWedfUrH2sxqKlxrfdW5qiqNHyNPSJe
# LFB4eIoeq6YkAwZci+75rwno8FcWHr2OKlcE2f6N4L5fkdJRcWEvX3iDODXhtPlr
# A2e4y3IuTBXrjcKLEGN89ul4NaI9FPbvp3Efbk1PsQZifAbZQnYUNd0TTF+T/pK0
# WDwd1wqfSZul2jtffeat9gCGZtZswRiOsh5b4l2hAuU8xojtS17j7V2VNl/d6ECW
# zKHt7/PuQjyq0GpRlsmLodmt1dacG4/ltBRJhBT6bvEyPqmDtSCEFlEkbxY17YeT
# m9NoTDIwggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3
# DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIw
# MAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAx
# MDAeFw0yMTA5MzAxODIyMjVaFw0zMDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
# 5OGmTOe0ciELeaLL1yR5vQ7VgtP97pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/
# XE/HZveVU3Fa4n5KWv64NmeFRiMMtY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1
# hlDcwUTIcVxRMTegCjhuje3XD9gmU3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7
# M62AW36MEBydUv626GIl3GoPz130/o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3K
# Ni1wjjHINSi947SHJMPgyY9+tVSP3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy
# 1cCGMFxPLOJiss254o2I5JasAUq7vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF80
# 3RKJ1v2lIH1+/NmeRd+2ci/bfV+AutuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQc
# NIIP8BDyt0cY7afomXw/TNuvXsLz1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahha
# YQFzymeiXtcodgLiMxhy16cg8ML6EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkL
# iWHzNgY1GIRH29wb0f2y1BzFa/ZcUlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV
# 2xo3xwgVGD94q0W29R6HXtqPnhZyacaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIG
# CSsGAQQBgjcVAQQFAgMBAAEwIwYJKwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUp
# zxD/LwTuMB0GA1UdDgQWBBSfpxVdAF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBT
# MFEGDCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYI
# KwYBBQUHAwgwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGG
# MA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186a
# GMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3Br
# aS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsG
# AQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcN
# AQELBQADggIBAJ1VffwqreEsH2cBMSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1
# OdfCcTY/2mRsfNB1OW27DzHkwo/7bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYA
# A7AFvonoaeC6Ce5732pvvinLbtg/SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbz
# aN9l9qRWqveVtihVJ9AkvUCgvxm2EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6L
# GYnn8AtqgcKBGUIZUnWKNsIdw2FzLixre24/LAl4FOmRsqlb30mjdAy87JGA0j3m
# Sj5mO0+7hvoyGtmW9I/2kQH2zsZ0/fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0
# SCyxTkctwRQEcb9k+SS+c23Kjgm9swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxko
# JLo4S5pu+yFUa2pFEUep8beuyOiJXk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFm
# PWn9y8FBSX5+k77L+DvktxW/tM4+pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC482
# 2rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7
# vzhwRNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIDUDCC
# AjgCAQEwgfmhgdGkgc4wgcsxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJzAl
# BgNVBAsTHm5TaGllbGQgVFNTIEVTTjozNzAzLTA1RTAtRDk0NzElMCMGA1UEAxMc
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUASyDI
# NT+7Dbgl6Zmx9iF09rV3hBCggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMDANBgkqhkiG9w0BAQsFAAIFAO2nVqQwIhgPMjAyNjA1MDcxODIxMjRa
# GA8yMDI2MDUwODE4MjEyNFowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA7adWpAIB
# ADAKAgEAAgIbZAIB/zAHAgEAAgITrzAKAgUA7aioJAIBADA2BgorBgEEAYRZCgQC
# MSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqG
# SIb3DQEBCwUAA4IBAQAN79ofgl0df2w0kq5UVxqdoNS4IZZsOQKdr3Jd+OHkKLcn
# fn9FSQEvvR97Lz8rVJSB3JB6sxIzpDCIzESOE8edU2ICHl06KdY3pvv6rfZ1NgRm
# IDNENDyOGRAKQ3uQQYloZqkOZV2SVYqfKv+d1ARwMQ11PJ61Y++7bx6/5QdxyQhC
# TP/T8Pt910Jlh2xi//Ci87vBS97kP+kp+y/CNILf96T4srqzNUqivGGNErlV8/Ex
# xLY4ti5V6sJ6M33QXUQTUmKwe35e5TVCjVgXdn5jDcsCnv4ZEXzJtScleX/NyvpZ
# w/cnUXofKZvCQDAgokbYwz0yWNkYghNUP2AhERUBMYIEDTCCBAkCAQEwgZMwfDEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIfOnBp5KIwLpUAAQAAAh8w
# DQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAv
# BgkqhkiG9w0BCQQxIgQg8Hz5dcBa/6OzWEidc01XZZ2trwsY4BC5DEfzljb1s3ww
# gfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCCwJArfVpArDLVEZBbuk2ND91F3
# UZwomLj2YXt8pC38FDCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwAhMzAAACHzpwaeSiMC6VAAEAAAIfMCIEIPsHCnKahFLJIdDatC+U779sqH8D
# 4Hi8/2p63MNlIWaXMA0GCSqGSIb3DQEBCwUABIICAG9IxzROIicmcJKU+7S726Dg
# xEn+u9U7dSMBk+fLB+KVpZjpNEMOu0GnGJGHcnm55kF2TVCzTGuIPgc/e50PA+ho
# ez7M/yGlFu6tC9f5S8aeuGnVos2KvaJwFK3E213llvDhiLF++Dkv4RDHNaSkMePH
# zCPR72/tY5OCeQ7uvKW1l8kcvMj3kCFyTQVq4U5kjdneJDpuu/9e20SRMdTk/MFY
# ISC7BSUKLLQE2xmAimYjJC4752Uofn9HmKhbyznVUcF9tawYhIshnG4jw+0u5c4I
# GuuF5EYk16LWWKGTK58RoRoop5P0hl/4Mi0iFwPit2liiF3nRYbt0E+6kSh0+Kxo
# 9ah0bXd2akZD9gTf/e7i93u65jUFvriBfSkEX5ZYKkS5siDsBPYjon9KrQ9qhnxi
# 23dddX1/fmWHpHd6erZ0unM4JgeNm+nmgrC60xHoclZqaOMGLb5FRWIcxCv9Ehxf
# rHbam1zfGHDwrbWtrxdXL1PYbzt+3lW+r+6zxFthyXeZ/kOAidisR9+EO3ck8aio
# rSDqkj25B0B6m/Tv6FhRIs9zxNRCCYFSg3BxvBl+W0DJrvFN9BQjjGTwC8D1JQhO
# hXLabaWSLv/vqgzoYCe5X4XkXZSnjgWoDPE6Pgg6NevkW9BaQ+JbuzwPO+L1R/QS
# bzewWt6kLzF07JAc2K/V
# SIG # End signature block
