#requires -Version 5.1
<#
Run with Windows PowerShell 5.1 and PowerShell 7 on Windows:
  & .\Scripts\Tests\Convert-UpPrinterToPerUser.Tests.ps1
Optional isolated filesystem/ACL checks (run this test script as SYSTEM):
  & .\Scripts\Tests\Convert-UpPrinterToPerUser.Tests.ps1 -FileSystemChecks
Functions are loaded individually; the entry point is exercised only in WhatIf.
All registry/hive commands are mocked; no printers, registry keys, or services
are changed. Default sharing checks use disposable fixtures beside this test.
SYSTEM-only checks use private fixtures under SYSTEM's local AppData.
Cleanup is non-recursive and handles unexpected successful renames.
No Pester dependency is required.
#>
[CmdletBinding()]
param ([switch]$FileSystemChecks)

$ErrorActionPreference = 'Stop'
Write-Host ("Runtime: PowerShell {0} ({1}), {2}-bit; identity: {3}" -f
    $PSVersionTable.PSVersion, $PSVersionTable.PSEdition, ([IntPtr]::Size * 8),
    [Security.Principal.WindowsIdentity]::GetCurrent().User.Value)

function Assert-True {
    param ([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Assert-Throws {
    param ([scriptblock]$Action, [string]$Message, [string]$ExpectedError)
    $threw = $false
    try { & $Action } catch {
        $threw = $true
        if ($ExpectedError) {
            Assert-True ($_.Exception.Message -match $ExpectedError) "$Message (actual error: $($_.Exception.Message); $($_.ScriptStackTrace))"
        }
    }
    Assert-True $threw $Message
}

function Assert-SharingViolation {
    param ([scriptblock]$Action, [string]$Message)
    $blocked = $false
    try { & $Action } catch {
        $exception = $_.Exception.GetBaseException()
        $code = if ($exception -is [ComponentModel.Win32Exception]) {
            $exception.NativeErrorCode
        } else {
            $exception.HResult -band 0xffff
        }
        Assert-True ($code -eq 32) "$Message (expected sharing violation, got $exception)"
        $blocked = $true
    }
    Assert-True $blocked $Message
}

function Remove-TestFixture {
    param (
        [string[]]$Roots,
        [string]$Marker,
        [string[]]$Files = @(),
        [string[]]$Directories = @(),
        [string[]]$Links = @()
    )
    foreach ($root in $Roots) {
        if (-not [IO.Directory]::Exists($root)) { continue }
        Assert-True (([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -eq 0) `
            "Refusing cleanup through a reparse-point fixture root: $root"
        $markerPath = Join-Path $root '.upconvert-test-fixture'
        Assert-True ([IO.File]::Exists($markerPath) -and [IO.File]::ReadAllText($markerPath) -eq $Marker) `
            "Refusing cleanup of an unrecognized fixture: $root"
        foreach ($relative in $Directories) {
            $path = Join-Path $root $relative
            if ([IO.Directory]::Exists($path)) {
                Assert-True (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -eq 0) `
                    "Refusing cleanup through an unexpected reparse point: $path"
            }
        }
        foreach ($relative in $Links) {
            $path = Join-Path $root $relative
            if ([IO.Directory]::Exists($path)) { [IO.Directory]::Delete($path) }
        }
        foreach ($relative in $Files) {
            $path = Join-Path $root $relative
            if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) }
        }
        foreach ($relative in ($Directories | Sort-Object Length -Descending)) {
            $path = Join-Path $root $relative
            if ([IO.Directory]::Exists($path)) { [IO.Directory]::Delete($path) }
        }
        # Unknown contents cause cleanup to fail rather than being removed.
        $remaining = [IO.Directory]::GetFileSystemEntries($root)
        Assert-True ($remaining.Count -eq 1 -and $remaining[0] -eq $markerPath) `
            "Unexpected fixture contents left intact for inspection: $root"
        [IO.File]::Delete($markerPath)
        [IO.Directory]::Delete($root)
    }
}

$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'Convert-UpPrinterToPerUser.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) "Script parses: $($parseErrors -join '; ')"

$parentValidation = $ast.Find({
    param ($node)
    $node -is [Management.Automation.Language.IfStatementAst] -and
        $node.Extent.Text.StartsWith('if (-not $WhatIfMode -and [string]::IsNullOrWhiteSpace($BackupDir))')
}, $true)
Assert-True ($null -ne $parentValidation) 'Explicit backup parent validation exists.'
$parentCheck = [scriptblock]::Create(@'
param ([string]$BackupDir = '', [switch]$WhatIfMode)
'@ + "`r`n" + $parentValidation.Extent.Text)
Assert-Throws { & $parentCheck } 'Unresolved default has an actionable error.' `
    "SYSTEM's LocalApplicationData backup parent could not be resolved.*-BackupDir"
foreach ($empty in @('', '   ')) {
    Assert-Throws { & $parentCheck -BackupDir $empty } 'Supplied empty parent is not blamed on AppData.' `
        'BackupDir cannot be empty or whitespace.*-BackupDir'
}
& $parentCheck -WhatIfMode
& $parentCheck -BackupDir '' -WhatIfMode
& $parentCheck -BackupDir 'C:\ExistingTrustedParent'

# Execute the production allocation try/finally with a synthetic allocation
# failure. No OOM, native directory creation, or privileged token is needed.
$allocationTry = $ast.Find({
    param ($node)
    $node -is [Management.Automation.Language.TryStatementAst] -and
        $node.Body.Statements.Count -gt 0 -and
        $node.Body.Statements[0].Extent.Text -eq
            '$attributes = [Runtime.InteropServices.Marshal]::AllocHGlobal(3 * [IntPtr]::Size)'
}, $true)
Assert-True ($null -ne $allocationTry) 'Native allocation occurs inside the cleanup try.'
$allocationFailure = $allocationTry.Extent.Text.Replace(
    $allocationTry.Body.Statements[0].Extent.Text, "throw 'Injected native allocation failure'")
$attributes = [IntPtr]::Zero
$pinned = [Runtime.InteropServices.GCHandle]::Alloc([byte[]]@(1, 2), 'Pinned')
$allocationThrew = $false
try {
    try { . ([scriptblock]::Create($allocationFailure)) } catch {
        Assert-True ($_.Exception.Message -eq 'Injected native allocation failure') 'Expected injected failure.'
        $allocationThrew = $true
    }
    Assert-True ($allocationThrew -and -not $pinned.IsAllocated) 'Allocation failure always frees the GC handle.'
}
finally {
    if ($pinned.IsAllocated) { $pinned.Free() }
}
Write-Host 'PASS: explicit empty-parent diagnostics and GC handle cleanup on allocation failure.'

foreach ($name in @('Open-PinnedConversionDirectory', 'New-PrivateConversionDirectory',
                     'Read-DafExport', 'Write-ConversionRegFile', 'Convert-OnePrinter')) {
    $definition = $ast.Find({
        param ($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    Assert-True ($null -ne $definition) "Function exists: $name"
    . ([scriptblock]::Create($definition.Extent.Text))
}

$script:REG_PERSYS_BASE = 'HKLM\SYSTEM\CurrentControlSet\Services\DeviceAssociationService\State\Store'
$share = '11111111-2222-3333-4444-555555555555'
$tenant = '66666666-7777-8888-9999-000000000000'
$sid = 'S-1-5-21-100-200-300-1001'
$script:RegCalls = [Collections.Generic.List[string]]::new()
function reg {
    $script:RegCalls.Add(($args -join ' '))
    if ($args[0] -ne 'query') { throw 'Dry run attempted a registry mutation/export.' }
    $script:LASTEXITCODE = 0
}
function Test-HiveLoaded { throw 'Dry run attempted hive handling.' }
function Mount-UserHive { throw 'Must never load a real hive in these tests.' }
function Dismount-UserHive { throw 'Must never unload a real hive in these tests.' }
function Build-PerUserRegContent { throw 'Dry run attempted payload generation.' }

$untouchedPath = Join-Path $PSScriptRoot ([Guid]::NewGuid().ToString('N'))
$result = Convert-OnePrinter -ShareId $share -TenantId $tenant -TargetSIDs @($sid) `
    -Timestamp 'dry-run' -BackupDir $untouchedPath -WhatIfMode -SkipDisassociate
Assert-True $result.Success 'Dry run completes with mocked read-only queries.'
Assert-True ($result.Installs.Count -eq 0) 'Dry run performs no imports.'
Assert-True (-not (Test-Path -LiteralPath $untouchedPath)) 'Dry run creates no directories.'
Assert-True ($script:RegCalls.Count -eq 1) 'Dry run only queries the per-system key.'

$entryPoint = [scriptblock]::Create($ast.Extent.Text)
& $entryPoint -ShareId $share -TenantId $tenant -UserSIDs @($sid) `
    -BackupDir $untouchedPath -WhatIfMode -SkipDisassociate
Assert-True (-not (Test-Path -LiteralPath $untouchedPath)) 'WhatIf entry point creates no directories.'
Assert-True ($script:RegCalls.Count -eq 2) 'WhatIf entry point only adds a read-only query.'
Assert-Throws {
    & $entryPoint -ShareId $share -TenantId $tenant -UserSIDs '..\outside' `
        -BackupDir $untouchedPath -WhatIfMode -SkipDisassociate
} 'Invalid SID path fragments are rejected before conversion.' 'Invalid real-user SID'
Assert-True ($script:RegCalls.Count -eq 2) 'Invalid SID never reaches conversion.'

# Keep assertions strict, but invoke the production function with each caller's
# actual preference. Only registry/hive/payload-building operations are mocked.
& {
    $writeDefinition = $ast.Find({
        param ($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Write-ConversionRegFile'
    }, $true).Extent.Text
    $convertDefinition = $ast.Find({
        param ($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Convert-OnePrinter'
    }, $true).Extent.Text
    $flowRoot = Join-Path $PSScriptRoot ("UPConvert-Flow-$([Guid]::NewGuid().ToString('N'))")
    $null = [IO.Directory]::CreateDirectory($flowRoot)
    $flowFiles = [Collections.Generic.List[string]]::new()
    try {
        foreach ($preference in @('Continue', 'Stop')) {
            foreach ($failure in @('collision', 'open', 'write', 'duplicate', 'duplicate-skip', 'duplicate-whatif')) {
                . ([scriptblock]::Create($writeDefinition))
                if ($failure -eq 'open') {
                    . ([scriptblock]::Create($writeDefinition.Replace(
                        '[IO.FileStream]::new($Path,', '[IO.FileStream]::new(($Path + "\missing"),')))
                } elseif ($failure -eq 'write') {
                    . ([scriptblock]::Create($writeDefinition.Replace(
                        '$writer.Write($Content)', '$writer.Write("partial"); throw "Injected writer failure"')))
                }
                $stamp = "$preference-$failure"
                $payload = Join-Path $flowRoot "PerUser-$sid-MCP-$share-$stamp.reg"
                $flowFiles.Add($payload)
                if ($failure -eq 'collision') { [IO.File]::WriteAllText($payload, 'sentinel') }
                $duplicates = $failure -like 'duplicate*'
                $laterSID = 'S-1-5-21-100-200-300-1002'
                $laterPayload = Join-Path $flowRoot "PerUser-$laterSID-MCP-$share-$stamp.reg"
                $flowFiles.Add($laterPayload)
                $targets = if ($duplicates) {
                    @($sid, $sid.ToLowerInvariant(), $laterSID, $sid)
                } else { @($sid) }
                $state = @{
                    Queries = 0; Imports = 0; ImportPaths = [Collections.Generic.List[string]]::new()
                    SkipSID = $(if ($failure -eq 'duplicate-skip') { $sid } else { '' })
                    WhatIf = ($failure -eq 'duplicate-whatif')
                }
                # A separate runspace avoids the harness's outer try/catch
                # changing how statement-terminating errors propagate.
                $runner = [powershell]::Create()
                try {
                    $body = @'
param ($preference, $state, $share, $tenant, $targets, $stamp, $flowRoot)
$ErrorActionPreference = $preference
function Test-HiveLoaded { param($UserSID) return ($UserSID -ne $state.SkipSID) }
function Mount-UserHive { return $false }
function Build-PerUserRegContent { return 'generated payload' }
function Read-DafExport { return @{ Property = 'mocked property' } }
function reg {
    switch ($args[0]) {
        'query' { $state.Queries++ }
        'export' { }
        'import' { $state.Imports++; $state.ImportPaths.Add($args[1]) }
        default { throw "Unexpected command: $args" }
    }
    $script:LASTEXITCODE = 0
}
'@
                    $writeBody = (Get-Command Write-ConversionRegFile).Definition
                    $body += "`r`nfunction Write-ConversionRegFile {`r`n$writeBody`r`n}`r`n" + $convertDefinition + @'

$REG_PERSYS_BASE = 'mocked-store'
$result = Convert-OnePrinter -ShareId $share -TenantId $tenant -TargetSIDs $targets -Timestamp $stamp -BackupDir $flowRoot -SkipDisassociate -WhatIfMode:$state.WhatIf
'returned-from-conversion'
'@
                    $null = $runner.AddScript($body).AddArgument($preference).AddArgument($state).
                        AddArgument($share).AddArgument($tenant).AddArgument($targets).
                        AddArgument($stamp).AddArgument($flowRoot)
                    $output = @()
                    $invocationError = $null
                    try { $output = $runner.Invoke() } catch { $invocationError = $_ }
                    $errors = @($runner.Streams.Error)
                    $duplicateMessages = @($runner.Streams.Information | Where-Object {
                        $_.MessageData.ToString() -like '*already attempted; skipping duplicate.*'
                    })
                    if ($errors.Count -eq 0 -and $null -ne $invocationError) {
                        $errors = @($invocationError)
                    }
                }
                finally { $runner.Dispose() }
                if ($duplicates) {
                    Assert-True ($output -contains 'returned-from-conversion' -and $errors.Count -eq 0) `
                        "$preference/$failure no-ops duplicates and continues distinct users."
                    Assert-True ($duplicateMessages.Count -eq 2) 'Each duplicate occurrence prints a message.'
                } else {
                    Assert-True ($output -notcontains 'returned-from-conversion' -and $errors.Count -gt 0) `
                        "$preference/$failure fails closed without an enclosing catch."
                    Assert-True ($errors[-1].Exception.Message -like '*Cannot write conversion payload*') `
                        "$preference/$failure surfaces the payload error explicitly."
                }
                $expectedImports = switch ($failure) { 'duplicate' { 2 }; 'duplicate-skip' { 1 }; default { 0 } }
                Assert-True ($state.Imports -eq $expectedImports) "$preference/$failure never imports stale/partial bytes."
                if ($failure -eq 'duplicate') {
                    Assert-True ($state.ImportPaths[0] -eq $payload -and $state.ImportPaths[1] -eq $laterPayload) `
                        'Unique users are imported in first-seen order.'
                } elseif ($failure -eq 'duplicate-skip') {
                    Assert-True ($state.ImportPaths[0] -eq $laterPayload) 'An unavailable first user is not retried.'
                }
                Assert-True ($state.Queries -eq 1) "$preference/$failure queries once per printer, not per SID."
                if ($failure -eq 'collision') {
                    Assert-True ([IO.File]::ReadAllText($payload) -eq 'sentinel') 'Existing payload is unchanged.'
                }
                Assert-True ([IO.File]::Exists($laterPayload) -eq ($failure -in @('duplicate', 'duplicate-skip'))) `
                    'Distinct users proceed only when conversion has not failed or is dry-run.'
            }
        }
    }
    finally {
        foreach ($file in $flowFiles) {
            if ([IO.File]::Exists($file)) { [IO.File]::Delete($file) }
        }
        [IO.Directory]::Delete($flowRoot)
    }
}
Write-Host 'PASS: production collision/open/write/duplicate control flow under Continue and Stop callers.'

Assert-Throws { New-PrivateConversionDirectory -ParentPath '\\localhost\C$\Windows' } `
    'UNC paths are rejected after successfully emitting native declarations.' 'absolute local drive path'
Assert-Throws { New-PrivateConversionDirectory -ParentPath '.' } `
    'Relative paths are rejected.' 'absolute local drive path'
Assert-True ($null -ne ('UPConvert.StagingNative' -as [type])) 'Native declarations are available in memory.'
foreach ($name in @('CreateFileW', 'CreateDirectoryW', 'GetFileInformationByHandleEx',
                     'GetSecurityInfo', 'GetSecurityDescriptorLength', 'LocalFree')) {
    $method = [UPConvert.StagingNative].GetMethod($name)
    Assert-True ($null -ne $method) "Native method exists: $name"
    $import = $method.GetCustomAttributes([Runtime.InteropServices.DllImportAttribute], $false)[0]
    Assert-True $import.SetLastError "Native method preserves error codes: $name"
}

$sharingRoot = Join-Path $PSScriptRoot ("UPConvert-Test-$([Guid]::NewGuid().ToString('N'))")
if (-not [UPConvert.StagingNative]::CreateDirectoryW($sharingRoot, [IntPtr]::Zero)) {
    throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
}
$marker = [Guid]::NewGuid().ToString('N')
$handles = [Collections.Generic.List[Microsoft.Win32.SafeHandles.SafeFileHandle]]::new()
try {
    [IO.File]::WriteAllText((Join-Path $sharingRoot '.upconvert-test-fixture'), $marker)
    $metadataPath = Join-Path $sharingRoot 'metadata'
    $null = [IO.Directory]::CreateDirectory($metadataPath)
    $metadata = [UPConvert.StagingNative]::CreateFileW($metadataPath, 0x20080, 3, [IntPtr]::Zero,
                                                     3, 0x02200000, [IntPtr]::Zero)
    $handles.Add($metadata)
    Assert-True (-not $metadata.IsInvalid) 'Metadata-only control handle opens.'
    [IO.Directory]::Move($metadataPath, "$metadataPath-moved")
    Assert-True ([IO.Directory]::Exists("$metadataPath-moved")) `
        'Control reproduces the original bug: metadata-only handles do not pin directories.'
    $metadata.Dispose()

    $lockedPath = Join-Path $sharingRoot 'locked'
    $null = [IO.Directory]::CreateDirectory($lockedPath)
    $pin = Open-PinnedConversionDirectory -Path $lockedPath
    $handles.Add($pin)
    [gc]::Collect(); [gc]::WaitForPendingFinalizers()
    Assert-True (-not $pin.IsClosed) 'The returned pin remains open after garbage collection.'
    Assert-SharingViolation { [IO.Directory]::Move($lockedPath, "$lockedPath-moved") } `
        'Production pin blocks rename even when the caller can delete the directory.'
    $deleteHandle = [UPConvert.StagingNative]::CreateFileW($lockedPath, 0x10000, 7, [IntPtr]::Zero,
                                                         3, 0x02200000, [IntPtr]::Zero)
    $deleteError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    $handles.Add($deleteHandle)
    Assert-True ($deleteHandle.IsInvalid -and $deleteError -eq 32) 'Production pin blocks new DELETE handles.'
    $pin.Dispose()
    $deleteHandle = [UPConvert.StagingNative]::CreateFileW($lockedPath, 0x10000, 7, [IntPtr]::Zero,
                                                         3, 0x02200000, [IntPtr]::Zero)
    $handles.Add($deleteHandle)
    Assert-True (-not $deleteHandle.IsInvalid) 'DELETE access is available after the pin is released.'
    Assert-SharingViolation {
        $unexpected = Open-PinnedConversionDirectory -Path $lockedPath
        $unexpected.Dispose()
    } `
        'Production pin fails closed when a DELETE handle already exists.'
    $deleteHandle.Dispose()
    [IO.Directory]::Move($lockedPath, "$lockedPath-moved")
    Assert-True ([IO.Directory]::Exists("$lockedPath-moved")) 'Releasing the pin permits rename.'

    $ancestorPath = Join-Path $sharingRoot 'ancestor'
    $childPath = Join-Path $ancestorPath 'child'
    $null = [IO.Directory]::CreateDirectory($childPath)
    $ancestorPin = Open-PinnedConversionDirectory -Path $ancestorPath
    $handles.Add($ancestorPin)
    $childPin = Open-PinnedConversionDirectory -Path $childPath
    $handles.Add($childPin)
    Assert-SharingViolation { [IO.Directory]::Move($childPath, "$childPath-moved") } `
        'Pinned child cannot be renamed independently.'
    Assert-SharingViolation { [IO.Directory]::Move($ancestorPath, "$ancestorPath-moved") } `
        'Pinned ancestor cannot redirect child paths.'
    $childPin.Dispose()
    $ancestorPin.Dispose()
    # Exercise the residue shape from an unexpected child AND parent rename.
    [IO.Directory]::Move($sharingRoot, "$sharingRoot-moved")
}
finally {
    foreach ($handle in $handles) { $handle.Dispose() }
    Remove-TestFixture -Roots @($sharingRoot, "$sharingRoot-moved") -Marker $marker `
        -Directories @('metadata', 'metadata-moved', 'locked', 'locked-moved',
            'ancestor\child', 'ancestor\child-moved', 'ancestor',
            'ancestor-moved\child', 'ancestor-moved\child-moved', 'ancestor-moved')
}
Assert-True (-not [IO.Directory]::Exists($sharingRoot) -and -not [IO.Directory]::Exists("$sharingRoot-moved")) `
    'Cleanup handles the deliberately moved control and released-pin directories.'
Write-Host 'PASS: metadata-only failure reproduction, production pin sharing checks, and moved-fixture cleanup.'

$profile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
$profileAcl = Get-Acl -LiteralPath $profile
$profileOwner = $profileAcl.GetOwner([Security.Principal.SecurityIdentifier]).Value
$trusted = @('S-1-5-18', 'S-1-5-32-544',
    'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
$untrustedWriters = @($profileAcl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) |
    Where-Object {
        $_.AccessControlType -eq 'Allow' -and $_.IdentityReference.Value -notin $trusted -and
        ($_.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -eq 0 -and
        ($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::WriteAttributes) -ne 0
    })
if ($profileOwner -notin $trusted -or $untrustedWriters.Count -gt 0) {
    Assert-Throws { New-PrivateConversionDirectory -ParentPath $profile } `
        'An untrusted profile is rejected before any directory creation.' `
        'Untrusted backup ancestor owner|Untrusted write access|not reparse points'
    Write-Host 'PASS: native ancestor inspection rejects an untrusted profile.'
} else {
    Write-Host 'SKIP: profile is not an untrusted-owner/writer fixture.'
}

if (-not $FileSystemChecks) {
    Write-Host 'PASS: parsing, read-only dry run, native declarations, sharing checks, and invalid path rejection. SYSTEM-only checks not requested.'
    return
}

Assert-True ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18') `
    'Isolated filesystem checks require SYSTEM; the full conversion is never invoked.'

function Close-Staging {
    param ($Staging)
    if ($null -ne $Staging) {
        foreach ($handle in $Staging.Handles) { $handle.Dispose() }
    }
}

$fixture = $null
$run = $null
$junction = $null
$runLeaf = $null
$fixtureMarker = [Guid]::NewGuid().ToString('N')
try {
    $fixture = New-PrivateConversionDirectory -ParentPath (
        [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData))
    [IO.File]::WriteAllText((Join-Path $fixture.Path '.upconvert-test-fixture'), $fixtureMarker)
    $run = New-PrivateConversionDirectory -ParentPath $fixture.Path
    $runLeaf = [IO.Path]::GetFileName($run.Path)
    $acl = Get-Acl -LiteralPath $run.Path
    Assert-True $acl.AreAccessRulesProtected 'Run directory disables ACL inheritance.'
    Assert-True ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-18') `
        'Run directory is SYSTEM-owned.'
    $rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
    Assert-True ($rules.Count -eq 2) 'Run directory has exactly two grants.'
    foreach ($rule in $rules) {
        Assert-True ($rule.IdentityReference.Value -in @('S-1-5-18', 'S-1-5-32-544')) `
            'Only SYSTEM and Administrators receive access.'
        Assert-True ($rule.FileSystemRights -eq [Security.AccessControl.FileSystemRights]::FullControl) `
            'Trusted identities retain full control.'
    }
    Assert-SharingViolation { [IO.Directory]::Move($run.Path, "$($run.Path)-moved") } `
        'Open staging handle prevents directory replacement.'
    Assert-SharingViolation { [IO.Directory]::Move($fixture.Path, "$($fixture.Path)-moved") } `
        'Open ancestor handles prevent parent replacement.'
    $unsafe = Join-Path $fixture.Path 'unsafe'
    $null = [IO.Directory]::CreateDirectory($unsafe)
    $unsafeAcl = Get-Acl -LiteralPath $unsafe
    $unsafeAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
        [Security.Principal.SecurityIdentifier]::new('S-1-5-32-545'),
        [Security.AccessControl.FileSystemRights]::Modify,
        [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
        [Security.AccessControl.PropagationFlags]::None,
        [Security.AccessControl.AccessControlType]::Allow))
    Set-Acl -LiteralPath $unsafe -AclObject $unsafeAcl
    $inherited = Join-Path $unsafe 'inherited'
    $null = [IO.Directory]::CreateDirectory($inherited)
    Assert-Throws { New-PrivateConversionDirectory -ParentPath $inherited } `
        'SYSTEM ownership does not excuse a permissive ancestor DACL.'
    [IO.Directory]::Move($unsafe, "$unsafe-moved")
    Assert-True ([IO.Directory]::Exists("$unsafe-moved")) 'Failure releases handles.'

    $junction = Join-Path $fixture.Path 'junction'
    $null = New-Item -ItemType Junction -Path $junction -Target $run.Path
    Assert-Throws { New-PrivateConversionDirectory -ParentPath $junction } `
        'Reparse-point ancestors are rejected.'

    $script:ExportContent = @"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\DeviceAssociationService\State\Store\MCP#$share\Properties\{93906aa3-c281-43a8-816c-f6c1dd94c442}\0004]
@=hex(ffff0012):50,00,00,00
"@
    $script:GeneratedContent = "Windows Registry Editor Version 5.00`r`n`r`n"
    $script:ImportCount = 0
    function Test-HiveLoaded { return $true }
    function Build-PerUserRegContent { return $script:GeneratedContent }
    function reg {
        switch ($args[0]) {
            'query' { }
            'export' { [IO.File]::WriteAllText($args[2], $script:ExportContent, [Text.Encoding]::Unicode) }
            'import' {
                Assert-True ([IO.Path]::GetDirectoryName($args[1]) -eq $run.Path) `
                    'Import consumes only the private run directory.'
                Assert-True ([IO.File]::ReadAllText($args[1], [Text.Encoding]::Unicode) -eq $script:GeneratedContent) `
                    'Import consumes the generated bytes.'
                $script:ImportCount++
            }
            default { throw "Unexpected registry command: $args" }
        }
        $script:LASTEXITCODE = 0
    }
    $result = Convert-OnePrinter -ShareId $share -TenantId $tenant -TargetSIDs @($sid) `
        -Timestamp 'first' -BackupDir $run.Path -SkipDisassociate
    Assert-True ($result.Success -and $result.Installs.Count -eq 1 -and $script:ImportCount -eq 1) `
        'Mocked export/parse/generate/import flow succeeds.'
    Assert-True ([IO.File]::Exists($result.Backup)) 'Useful per-system backup remains.'
    Assert-True ([IO.File]::Exists($result.Installs[0].RegFile)) 'Generated payload remains.'
    foreach ($file in @($result.Backup, $result.Installs[0].RegFile)) {
        $fileAcl = Get-Acl -LiteralPath $file
        $fileRules = @($fileAcl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
        Assert-True ($fileRules.Count -eq 2) 'Intermediate file inherits only two grants.'
        foreach ($rule in $fileRules) {
            Assert-True ($rule.IsInherited -and $rule.IdentityReference.Value -in @('S-1-5-18', 'S-1-5-32-544') -and
                $rule.FileSystemRights -eq [Security.AccessControl.FileSystemRights]::FullControl) `
                'Export and import files inherit SYSTEM/Administrators-only access.'
        }
    }
    Assert-Throws {
        Convert-OnePrinter -ShareId $share -TenantId $tenant -TargetSIDs @($sid) `
            -Timestamp 'first' -BackupDir $run.Path -SkipDisassociate
    } 'Existing backups are not overwritten.'
    $collision = Join-Path $run.Path "PerUser-$sid-MCP-$share-second.reg"
    [IO.File]::WriteAllText($collision, 'sentinel')
    Assert-Throws {
        Convert-OnePrinter -ShareId $share -TenantId $tenant -TargetSIDs @($sid) `
            -Timestamp 'second' -BackupDir $run.Path -SkipDisassociate
    } 'Payload creation refuses existing files.'
    Assert-True ([IO.File]::ReadAllText($collision) -eq 'sentinel') 'Collision preserves the existing file.'
    Assert-True ($script:ImportCount -eq 1) 'Collision never imports an existing payload.'
    Write-Host 'PASS: private ACLs, path pins, unsafe path rejection, mocked conversion, and collisions.'
}
finally {
    Close-Staging $run
    Close-Staging $fixture
    if ($null -ne $fixture) {
        $directories = @('unsafe\inherited', 'unsafe', 'unsafe-moved\inherited', 'unsafe-moved')
        $files = @()
        if ($runLeaf) {
            foreach ($leaf in @($runLeaf, "$runLeaf-moved")) {
                $directories += $leaf
                foreach ($stamp in @('first', 'second')) {
                    $files += "$leaf\PerSystem-MCP-$share-$stamp.reg"
                    $files += "$leaf\PerUser-$sid-MCP-$share-$stamp.reg"
                }
            }
        }
        Remove-TestFixture -Roots @($fixture.Path, "$($fixture.Path)-moved") -Marker $fixtureMarker `
            -Files $files -Directories $directories -Links @('junction')
    }
}
