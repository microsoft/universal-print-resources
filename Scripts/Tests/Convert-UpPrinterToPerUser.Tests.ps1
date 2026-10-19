#requires -Version 5.1
<#
Run with Windows PowerShell 5.1 and PowerShell 7 on Windows:
  & .\Scripts\Tests\Convert-UpPrinterToPerUser.Tests.ps1
Optional isolated filesystem/ACL checks (run this test script as SYSTEM):
  & .\Scripts\Tests\Convert-UpPrinterToPerUser.Tests.ps1 -FileSystemChecks
Functions are loaded individually; the entry point is exercised only in WhatIf.
All registry/hive commands are mocked; no printers, registry keys, or services
are changed. Filesystem checks create and remove only their private fixtures
under SYSTEM's local AppData. No Pester dependency is required.
#>
[CmdletBinding()]
param ([switch]$FileSystemChecks)

$ErrorActionPreference = 'Stop'

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

$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'Convert-UpPrinterToPerUser.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) "Script parses: $($parseErrors -join '; ')"
foreach ($name in @('New-PrivateConversionDirectory', 'Read-DafExport', 'Convert-OnePrinter')) {
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
    Write-Host 'PASS: parsing, read-only dry run, native declaration emission, and invalid path rejection. Filesystem/ACL checks not requested.'
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
try {
    $fixture = New-PrivateConversionDirectory -ParentPath (
        [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData))
    $run = New-PrivateConversionDirectory -ParentPath $fixture.Path
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
    Assert-Throws { [IO.Directory]::Move($run.Path, "$($run.Path)-moved") } `
        'Open staging handle prevents directory replacement.'
    Assert-Throws { [IO.Directory]::Move($fixture.Path, "$($fixture.Path)-moved") } `
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
    if ($null -ne $junction -and [IO.Directory]::Exists($junction)) {
        [IO.Directory]::Delete($junction)
    }
    if ($null -ne $fixture) {
        Remove-Item -LiteralPath $fixture.Path -Recurse -Force
    }
}
