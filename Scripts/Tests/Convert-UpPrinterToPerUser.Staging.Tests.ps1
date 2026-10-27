param (
    [string]$Case,
    [ValidateSet('Continue', 'Stop', 'SilentlyContinue')][string]$Preference = 'Continue'
)

$ErrorActionPreference = 'Stop'

# No Pester dependency: each error-path case runs without an enclosing catch in
# its own process, so the harness cannot make a nonterminating error terminate.
$source = Join-Path $PSScriptRoot '..\Convert-UpPrinterToPerUser.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    $source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
foreach ($definition in $ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst]
}, $false)) {
    . ([scriptblock]::Create($definition.Extent.Text))
}
$text = [IO.File]::ReadAllText($source)
$constants = (($text -split '# --- Constants[^\r\n]*\r?\n')[1] -split '# --- Validation')[0]
. ([scriptblock]::Create($constants))

if ($Case) {
    $ErrorActionPreference = $Preference
    $fixture = Join-Path ([IO.Path]::GetTempPath()) "UPConvert-test-$([Guid]::NewGuid().ToString('N'))"
    $marker = Join-Path $fixture '.upconvert-test'
    $stage = Join-Path $fixture 'stage'
    $null = [IO.Directory]::CreateDirectory($fixture)
    [IO.File]::WriteAllText($marker, 'UPConvert isolated test fixture')
    try {
        function New-PrivateStagingDirectory {
            # Only the production parent/ACL creation is replaced. File creation,
            # parser, registry builder, and cleanup remain production code.
            if ($Case -eq 'parent-failure') { Write-Error 'Injected unsafe staging parent' }
            $null = [IO.Directory]::CreateDirectory($stage)
            if ($Case -eq 'backup-collision') {
                [IO.File]::WriteAllText((Join-Path $stage "PerSystem-MCP-$share-test.reg"), 'KEEP')
            }
            return $stage
        }
        function reg {
            $global:LASTEXITCODE = 0
            switch ($args[0]) {
                'query' { return }
                'export' {
                    Write-Host 'EXPORTED'
                    if ($Case -eq 'export-failure') {
                        [IO.File]::WriteAllText($args[2], 'partial')
                        $global:LASTEXITCODE = 1
                        return
                    }
                    $export = "Windows Registry Editor Version 5.00`r`n`r`n" +
                        "[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\DeviceAssociationService\State\Store\MCP#$share\Properties\$CAT_AUTH\0002]`r`n" +
                        "@=hex(ffff0012):61,00,00,00`r`n"
                    [IO.File]::WriteAllText($args[2], $export, [Text.Encoding]::Unicode)
                    if ($Case -eq 'read-failure') { [IO.File]::Delete($args[2]) }
                    return
                }
                'import' {
                    if ([IO.Path]::GetDirectoryName($args[1]) -ne $stage) { throw 'Import escaped private staging' }
                    $bytes = [IO.File]::ReadAllBytes($args[1])
                    if ($bytes[0] -ne 0xff -or $bytes[1] -ne 0xfe) { throw 'Missing UTF-16LE BOM' }
                    $payload = [IO.File]::ReadAllText($args[1], [Text.Encoding]::Unicode)
                    if (-not $payload.StartsWith('Windows Registry Editor Version 5.00')) { throw 'Partial import' }
                    if ($payload -notmatch 'HKEY_USERS\\S-1-5-21-1-2-3-100[12]\\') { throw 'Wrong user destination' }
                    if ($payload -cne $script:lastBuiltContent) { throw 'Imported payload differs from unchanged builder output' }
                    Write-Host 'IMPORTED'
                    return
                }
                default { throw "Unexpected reg command: $args" }
            }
        }
        $script:hiveLoaded = $false
        function Test-HiveLoaded {
            Write-Host 'HIVE_CHECKED'
            if ($Case -eq 'hive-unavailable') { return $false }
            if ($Case -in @('mounted-build-failure', 'mounted-success')) { return $script:hiveLoaded }
            return $true
        }
        function Mount-UserHive {
            Write-Host 'HIVE_MOUNTED'
            if ($Case -eq 'hive-unavailable') { return $false }
            $script:hiveLoaded = $true
            return $true
        }
        function Dismount-UserHive { Write-Host 'HIVE_DISMOUNTED' }
        function Test-Path {
            return $true
        }
        Set-Item -LiteralPath "Function:\$env:SystemRoot\System32\pairtool.exe" -Value {
            Write-Host 'DISASSOCIATED'
            $global:LASTEXITCODE = 0
        }
        $script:originalBuild = ${function:Build-PerUserRegContent}
        function Build-PerUserRegContent {
            param ($UserSID, $ShareId, $InstanceGuid, $TenantId, $PerSystem)
            Write-Host 'BUILT'
            if ($Case -in @('build-failure', 'driver-failure', 'mounted-build-failure')) {
                Write-Error 'Injected preparation failure'
                return
            }
            $script:lastBuiltContent = & $script:originalBuild @PSBoundParameters
            return $script:lastBuiltContent
        }
        if ($Case -eq 'write-failure') {
            $script:writeCount = 0
            $script:originalWrite = ${function:Write-NewStagingFile}
            function Write-NewStagingFile {
                param ([string]$Path, [string]$Content = '')
                $script:writeCount++
                if ($script:writeCount -eq 3) {
                    & $script:originalWrite -Path ([IO.Path]::Combine($stage, 'missing\payload.reg')) -Content $Content
                } else {
                    & $script:originalWrite -Path $Path -Content $Content
                }
            }
        }
        $share = '11111111-2222-3333-4444-555555555555'
        $arguments = @{
            ShareId = $share
            TenantId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
            TargetSIDs = @('S-1-5-21-1-2-3-1001', 'S-1-5-21-1-2-3-1002')
            Timestamp = 'test'
            SkipDisassociate = $false
        }
        if ($Case -eq 'driver-failure') {
            $shareIdsToConvert = @($share)
            $targetSIDs = $arguments.TargetSIDs
            $TenantId = $arguments.TenantId
            $timestamp = 'test'
            $WhatIfMode = $false
            $SkipDisassociate = $false
            $results = @()
            $driver = $ast.EndBlock.Statements | Where-Object {
                $_ -is [Management.Automation.Language.ForEachStatementAst] -and
                $_.Variable.VariablePath.UserPath -eq 'sid' -and
                $_.Condition.Extent.Text -eq '$shareIdsToConvert'
            }
            if (@($driver).Count -ne 1) { throw 'Could not identify production conversion loop' }
            . ([scriptblock]::Create($driver.Extent.Text))
            Write-Host 'AFTER_DRIVER'
        }
        $result = Convert-OnePrinter @arguments
        Write-Host "RETURNED:$($result.Success)"
        Write-Host "INSTALLS:$($result.Installs.Count)"
        Write-Host "PREPARATION_FAILED:$($result.PreparationFailed)"
        Write-Host "PREFERENCE_AFTER:$ErrorActionPreference"
    }
    finally {
        if ([IO.File]::Exists($marker) -and
            [IO.File]::ReadAllText($marker) -eq 'UPConvert isolated test fixture') {
            $remaining = @()
            $backups = @()
            if ([IO.Directory]::Exists($stage)) {
                $remaining = @([IO.Directory]::GetFiles($stage, 'PerUser-*.reg'))
                $backups = @([IO.Directory]::GetFiles($stage, 'PerSystem-*.reg'))
            }
            Write-Host "PAYLOADS_REMAINING:$($remaining.Count)"
            Write-Host "BACKUPS_REMAINING:$($backups.Count)"
            if ($Case -eq 'backup-collision') {
                Write-Host "COLLISION_CONTENT:$([IO.File]::ReadAllText((Join-Path $stage "PerSystem-MCP-$share-test.reg")))"
            }
            # Only this marked, uniquely named fixture is removed.
            [IO.Directory]::Delete($fixture, $true)
        } else {
            Write-Warning "Fixture marker missing; refusing cleanup: $fixture"
        }
    }
    exit 0
}

$runtime = (Get-Process -Id $PID).Path
$checks = 0
foreach ($preferenceValue in @('Continue', 'Stop', 'SilentlyContinue')) {
    foreach ($caseValue in @('success', 'mounted-success', 'hive-unavailable',
        'parent-failure', 'build-failure', 'mounted-build-failure', 'write-failure',
        'read-failure', 'backup-collision', 'export-failure', 'driver-failure')) {
        $output = (& $runtime -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath `
            -Case $caseValue -Preference $preferenceValue 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE
        $expectedPayloads = switch ($caseValue) { 'success' { 2 } 'mounted-success' { 2 } 'write-failure' { 1 } default { 0 } }
        if ($output -notmatch "PAYLOADS_REMAINING:$expectedPayloads") {
            throw "$caseValue/$preferenceValue retained unexpected payloads:`n$output"
        }
        $postDisassociation = $caseValue -in @('success', 'mounted-success', 'hive-unavailable',
            'build-failure', 'mounted-build-failure', 'write-failure', 'driver-failure')
        if ($postDisassociation) {
            if ($output -notmatch '(?s)EXPORTED.*DISASSOCIATED.*HIVE_CHECKED') {
                throw "Baseline disassociate/hive ordering changed:`n$output"
            }
            if ($caseValue -ne 'hive-unavailable' -and
                $output -notmatch '(?s)DISASSOCIATED.*HIVE_CHECKED.*BUILT') {
                throw "Payload built before disassociation/hive availability:`n$output"
            }
        } elseif ($output -match 'DISASSOCIATED|HIVE_CHECKED|BUILT|IMPORTED') {
            throw "Backup failure reached migration:`n$output"
        }
        if ($caseValue -in @('mounted-success', 'mounted-build-failure') -and
            $output -notmatch '(?s)HIVE_MOUNTED.*BUILT.*HIVE_DISMOUNTED') {
            throw "Owned hive was not unloaded:`n$output"
        }
        if ($caseValue -in @('success', 'mounted-success')) {
            if ($exitCode -ne 0 -or $output -notmatch 'INSTALLS:2' -or $output -notmatch 'RETURNED:True') {
                throw "Success case failed under ${preferenceValue}:`n$output"
            }
        } elseif ($caseValue -eq 'hive-unavailable') {
            if ($exitCode -ne 0 -or $output -notmatch 'INSTALLS:0' -or
                $output -notmatch 'RETURNED:True' -or $output -match 'BUILT|IMPORTED') {
                throw "Unavailable hive did not skip payload generation:`n$output"
            }
        } elseif ($caseValue -eq 'export-failure') {
            if ($exitCode -ne 0 -or $output -notmatch 'RETURNED:False' -or $output -notmatch 'BACKUPS_REMAINING:0') {
                throw "Export failure handling failed:`n$output"
            }
        } elseif ($caseValue -eq 'driver-failure') {
            if ($exitCode -ne 1 -or $output -match '(?m)^IMPORTED\r?$|AFTER_DRIVER|RETURNED:') {
                throw "Production loop did not abort on preparation failure:`n$output"
            }
        } else {
            $expectedImports = if ($caseValue -eq 'write-failure') { 1 } else { 0 }
            if ($exitCode -ne 0 -or ([regex]::Matches($output, 'IMPORTED')).Count -ne $expectedImports -or
                $output -match 'RETURNED:True' -or
                $output -notmatch 'RETURNED:False' -or $output -notmatch 'PREPARATION_FAILED:True' -or
                $output -notmatch 'ERROR: Private') {
                throw "$caseValue/$preferenceValue did not fail closed:`n$output"
            }
            if ($caseValue -ne 'driver-failure' -and $output -notmatch "PREFERENCE_AFTER:$preferenceValue") {
                throw "Caller preference changed:`n$output"
            }
            if ($caseValue -eq 'backup-collision' -and $output -notmatch 'COLLISION_CONTENT:KEEP') {
                throw "Collision was overwritten or deleted:`n$output"
            }
        }
        $checks++
    }
}

# ACL policy cases use synthetic Windows ACLs and metadata; no host ACL is changed.
$script:testAcl = [Security.AccessControl.DirectorySecurity]::new()
$script:testAcl.SetSecurityDescriptorSddlForm('O:SYG:SYD:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)')
function Get-Acl { return $script:testAcl }
function Get-Item {
    return [pscustomobject]@{ PSIsContainer = $true; Attributes = [IO.FileAttributes]::Directory }
}
Assert-ProtectedStagingParent -Path ([Environment]::SystemDirectory)
$script:rootAcl = [Security.AccessControl.DirectorySecurity]::new()
$script:rootAcl.SetSecurityDescriptorSddlForm(
    'O:SYG:SYD:PAI(A;;FA;;;SY)(A;;0x4;;;BU)(A;OICIIO;GA;;;BU)')
$script:testAcl.SetSecurityDescriptorSddlForm(
    'O:SYG:SYD:PAI(A;;FA;;;SY)(A;;FRFX;;;BU)(A;OICIIO;GA;;;BU)')
function Get-Acl {
    param ([string]$LiteralPath)
    if ($LiteralPath -eq [IO.Path]::GetPathRoot([Environment]::SystemDirectory)) { return $script:rootAcl }
    return $script:testAcl
}
Assert-ProtectedStagingParent -Path ([Environment]::SystemDirectory)
$checks++
function Get-Acl { return $script:testAcl }
foreach ($sddl in @(
    'O:SYG:SYD:PAI(A;;0x2;;;BU)',
    'O:SYG:SYD:PAI(A;;0x4;;;BU)',
    'O:SYG:SYD:PAI(A;;0x40;;;BU)',
    'O:SYG:SYD:PAI(A;;0x10000;;;BU)',
    'O:SYG:SYD:PAI(A;;0x40000;;;BU)',
    'O:SYG:SYD:PAI(A;;0x80000;;;BU)',
    'O:SYG:SYD:PAI(A;;0x100;;;BU)',
    'O:SYG:SYD:PAI(A;;GW;;;BU)',
    'O:SYG:SYD:PAI(A;;GA;;;BU)',
    'O:BUG:SYD:PAI(A;;FA;;;SY)',
    'O:SYG:SYD:NO_ACCESS_CONTROL'
)) {
    $script:testAcl = [Security.AccessControl.DirectorySecurity]::new()
    $script:testAcl.SetSecurityDescriptorSddlForm($sddl)
    $rejected = $false
    try { Assert-ProtectedStagingParent -Path ([Environment]::SystemDirectory) }
    catch { $rejected = $true }
    if (-not $rejected) { throw "Unsafe ancestor accepted: $sddl" }
    $checks++
}
$script:testAcl.SetSecurityDescriptorSddlForm('O:SYG:SYD:PAI(A;;FA;;;SY)')
function Get-Item {
    return [pscustomobject]@{ PSIsContainer = $true; Attributes = [IO.FileAttributes]::ReparsePoint }
}
$rejected = $false
try { Assert-ProtectedStagingParent -Path ([Environment]::SystemDirectory) }
catch { $rejected = $true }
if (-not $rejected) { throw 'Reparse ancestor accepted' }
$checks++
Write-Host "Passed $checks focused staging checks on PowerShell $($PSVersionTable.PSVersion)."
