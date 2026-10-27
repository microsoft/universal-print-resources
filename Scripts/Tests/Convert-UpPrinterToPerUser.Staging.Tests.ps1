# Run safely from the repository root with powershell.exe or pwsh.exe:
# -NoProfile -File .\Scripts\Tests\Convert-UpPrinterToPerUser.Staging.Tests.ps1
# No elevation or actual printer/registry/hive/service changes are performed.
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
        $script:runCount = 0
        $script:builtContents = @()
        $script:importCount = 0
        function New-PrivateStagingDirectory {
            # Only the production parent/ACL creation is replaced. File creation,
            # parser, registry builder, and cleanup remain production code.
            if ($Case -eq 'parent-failure') { Write-Error 'Injected unsafe staging parent' }
            $script:runCount++
            $script:stage = Join-Path $fixture "stage-$script:runCount"
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
                    $exportShare = ($args[1] -split 'MCP#')[-1]
                    $export = "Windows Registry Editor Version 5.00`r`n`r`n" +
                        "[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\DeviceAssociationService\State\Store\MCP#$exportShare\Properties\$CAT_AUTH\0002]`r`n" +
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
                    if ($script:builtContents -cnotcontains $payload) { throw 'Imported payload differs from unchanged builder output' }
                    $script:importCount++
                    if ($Case -in @('import-failure','driver-import-failure','import-exception') -and $script:importCount -eq 1) {
                        Write-Host 'IMPORT_FAILED'
                        if ($Case -eq 'import-exception') { throw 'Injected uncertain native import completion' }
                        $global:LASTEXITCODE = 5
                        return
                    }
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
        function Dismount-UserHive {
            Write-Host 'HIVE_DISMOUNTED'
            $script:hiveLoaded = $false
        }
        function Restart-Service {
            [CmdletBinding()]
            param($Name, [switch]$Force)
            Write-Host "RESTARTED:$Name"
            if ($Case -eq 'driver-service-failure' -and $Name -eq 'DeviceAssociationService') {
                Write-Error 'Injected service restart failure'
            }
        }
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
            if ($Case -in @('build-failure', 'mounted-build-failure') -or
                ($Case -eq 'driver-failure' -and $ShareId -ne $share)) {
                Write-Error 'Injected preparation failure'
                return
            }
            $content = & $script:originalBuild @PSBoundParameters
            $script:builtContents += $content
            return $content
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
        if ($Case -in @('driver-failure','driver-import-failure','driver-service-failure')) {
            $shareIdsToConvert = @($share, '22222222-2222-3333-4444-555555555555')
            $targetSIDs = $arguments.TargetSIDs
            $TenantId = $arguments.TenantId
            $timestamp = 'test'
            $WhatIfMode = $false
            $SkipDisassociate = $false
            $SkipRestart = $false
            $results = @()
            $driver = (($text -split '# --- Convert each printer[^\r\n]*\r?\n')[1] -split '# SIG # Begin signature block')[0]
            if (-not $driver) { throw 'Could not identify production conversion/finalization blocks' }
            . ([scriptblock]::Create($driver))
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
            $remaining = @([IO.Directory]::GetFiles($fixture, 'PerUser-*.reg', [IO.SearchOption]::AllDirectories))
            $backups = @([IO.Directory]::GetFiles($fixture, 'PerSystem-*.reg', [IO.SearchOption]::AllDirectories))
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
        'read-failure', 'backup-collision', 'export-failure', 'import-failure', 'import-exception',
        'driver-failure', 'driver-import-failure', 'driver-service-failure')) {
        $output = (& $runtime -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath `
            -Case $caseValue -Preference $preferenceValue 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE
        $expectedPayloads = switch ($caseValue) {
            'success' { 2 } 'mounted-success' { 2 } 'write-failure' { 1 } 'hive-unavailable' { 2 }
            'import-failure' { 2 } 'import-exception' { 2 } 'driver-failure' { 2 }
            'driver-import-failure' { 4 } 'driver-service-failure' { 4 }
            default { 0 }
        }
        if ($output -notmatch "PAYLOADS_REMAINING:$expectedPayloads") {
            throw "$caseValue/$preferenceValue retained unexpected payloads:`n$output"
        }
        $postDisassociation = $caseValue -in @('success', 'mounted-success', 'hive-unavailable',
            'import-failure', 'import-exception', 'driver-failure', 'driver-import-failure','driver-service-failure')
        if ($postDisassociation) {
            if ($output -notmatch '(?s)EXPORTED.*BUILT.*BUILT.*DISASSOCIATED.*HIVE_CHECKED') {
                throw "Payloads were not fully prepared before disassociation:`n$output"
            }
        } elseif ($output -match 'DISASSOCIATED|IMPORTED') {
            throw "Preflight failure reached destructive migration:`n$output"
        }
        if ($caseValue -in @('parent-failure','read-failure','backup-collision','export-failure') -and
            $output -match 'HIVE_CHECKED|BUILT') {
            throw "Backup failure reached hive/payload preflight:`n$output"
        }
        if ($caseValue -eq 'mounted-success' -and
            $output -notmatch '(?s)BUILT.*DISASSOCIATED.*HIVE_MOUNTED.*IMPORTED.*HIVE_DISMOUNTED') {
            throw "Owned hive was not unloaded:`n$output"
        }
        if ($caseValue -in @('success', 'mounted-success')) {
            if ($exitCode -ne 0 -or $output -notmatch 'INSTALLS:2' -or $output -notmatch 'RETURNED:True') {
                throw "Success case failed under ${preferenceValue}:`n$output"
            }
        } elseif ($caseValue -eq 'hive-unavailable') {
            if ($exitCode -ne 0 -or $output -notmatch 'INSTALLS:0' -or
                $output -notmatch 'RETURNED:False' -or $output -match 'IMPORTED') {
                throw "Unavailable hives were not reported as incomplete migration:`n$output"
            }
        } elseif ($caseValue -eq 'export-failure') {
            if ($exitCode -ne 0 -or $output -notmatch 'RETURNED:False' -or $output -notmatch 'BACKUPS_REMAINING:0') {
                throw "Export failure handling failed:`n$output"
            }
        } elseif ($caseValue -in @('driver-failure','driver-import-failure','driver-service-failure')) {
            $failedCount = if ($caseValue -eq 'driver-service-failure') { 0 } else { 1 }
            $succeededCount = if ($caseValue -eq 'driver-service-failure') { 2 } else { 1 }
            $imports = switch ($caseValue) { 'driver-failure' { 2 } 'driver-import-failure' { 3 } default { 4 } }
            if ($exitCode -ne 1 -or $output -match 'AFTER_DRIVER|RETURNED:' -or
                $output -notmatch 'RESTARTED:DeviceAssociationService' -or
                $output -notmatch 'RESTARTED:Spooler' -or $output -notmatch "Failed\s+:\s+$failedCount" -or
                $output -notmatch "Succeeded\s+:\s+$succeededCount" -or
                ([regex]::Matches($output, '(?m)^IMPORTED\r?$')).Count -ne $imports -or
                $output -notmatch 'backup=') {
                throw "Production loop did not finalize/report failure:`n$output"
            }
            if ($caseValue -eq 'driver-import-failure' -and $output -notmatch 'installs=1/2') {
                throw "Partial progress was missing from failure summary:`n$output"
            }
        } elseif ($caseValue -in @('import-failure','import-exception')) {
            if ($exitCode -ne 0 -or $output -notmatch 'RETURNED:False' -or
                $output -notmatch 'INSTALLS:1' -or $output -notmatch 'IMPORT_FAILED.*' -or
                $output -notmatch 'IMPORTED') { throw "Later users were not completed/reported:`n$output" }
        } else {
            if ($exitCode -ne 0 -or $output -match 'IMPORTED' -or
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
$systemTemp = [IO.Path]::Combine(
    [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows), 'SystemTemp')
Assert-SystemTempParent -Path $systemTemp
$checks++
foreach ($sddl in @(
    'O:SYG:SYD:PAI(A;;GA;;;BU)',
    'O:SYG:SYD:PAI(A;;FRFX;;;BU)',
    'O:SYG:SYD:PAI(A;OICIIO;GA;;;BU)',
    'O:BUG:SYD:PAI(A;;FA;;;SY)',
    'O:SYG:SYD:NO_ACCESS_CONTROL'
)) {
    $script:testAcl = [Security.AccessControl.DirectorySecurity]::new()
    $script:testAcl.SetSecurityDescriptorSddlForm($sddl)
    $rejected = $false
    try { Assert-SystemTempParent -Path $systemTemp }
    catch { $rejected = $true }
    if (-not $rejected) { throw "Unsupported SystemTemp ACL accepted: $sddl" }
    $checks++
}
$script:testAcl.SetSecurityDescriptorSddlForm('O:SYG:SYD:PAI(A;;FA;;;SY)')
function Get-Item {
    return [pscustomobject]@{ PSIsContainer = $true; Attributes = [IO.FileAttributes]::ReparsePoint }
}
$rejected = $false
try { Assert-SystemTempParent -Path $systemTemp }
catch { $rejected = $true }
if (-not $rejected) { throw 'Reparse SystemTemp accepted' }
$checks++
function Get-Item {
    return [pscustomobject]@{ PSIsContainer = $false; Attributes = [IO.FileAttributes]::Normal }
}
$rejected = $false
try { Assert-SystemTempParent -Path $systemTemp }
catch { $rejected = $true }
if (-not $rejected) { throw 'Nondirectory SystemTemp accepted' }
$checks++
function Get-Item { Write-Error 'SystemTemp does not exist' }
$rejected = $false
try { Assert-SystemTempParent -Path $systemTemp }
catch { $rejected = $true }
if (-not $rejected) { throw 'Missing SystemTemp accepted' }
$checks++
Write-Host "Passed $checks focused staging checks on PowerShell $($PSVersionTable.PSVersion)."
