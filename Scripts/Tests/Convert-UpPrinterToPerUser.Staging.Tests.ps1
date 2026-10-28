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
    [IO.File]::WriteAllText((Join-Path $fixture 'NTUSER.DAT'), 'isolated non-hive fixture')
    try {
        $script:runCount = 0
        $script:builtContents = @()
        $script:importCount = 0
        $script:queryCount = 0
        $script:pairCount = 0
        $script:hiveChecks = 0
        $script:mountCount = 0
        $script:unloadCount = 0
        $script:originalUnload = ${function:Dismount-UserHive}
        $script:originalProfile = ${function:Get-ProfileImagePath}
        $script:originalMount = ${function:Mount-UserHive}
        $script:profileQueries = 0
        function Start-Sleep {}
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
        function reg.exe {
            $global:LASTEXITCODE = 0
            switch ($args[0]) {
                'unload' {
                    if ($Case -eq 'driver-unload-exit' -and $script:unloadCount -eq 1) {
                        $global:LASTEXITCODE = 5
                    }
                    return
                }
                'query' {
                    if ($Case -eq 'expanded-profile' -and $args -contains 'ProfileImagePath') {
                        $script:profileQueries++
                        if ($script:profileQueries -gt 2) { throw 'Profile path was reread after preparation' }
                        return '    ProfileImagePath    REG_EXPAND_SZ    %UPConvertProfileFixture%'
                    }
                    $script:queryCount++
                    if ($Case -in @('driver-enumeration-failure','printer-enumeration-failure','query-denied')) {
                        $global:LASTEXITCODE = 1
                        return 'ERROR: Access is denied.'
                    }
                    if ($Case -eq 'driver-query-exception' -and $script:queryCount -eq 1) {
                        throw 'Injected first-printer query exception'
                    }
                    return
                }
                'load' {
                    if ($Case -ne 'expanded-profile' -or
                        $args[2] -cne [IO.Path]::Combine($fixture, 'NTUSER.DAT')) {
                        throw "Wrong expanded hive path: $($args[2])"
                    }
                    $script:hiveLoaded = $true
                    Write-Host 'HIVE_MOUNTED'
                    return
                }
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
                    if ($Case -in @('import-failure','driver-import-failure','import-exception','driver-import-unload-exception','driver-auto-import-error') -and $script:importCount -eq 1) {
                        Write-Host 'IMPORT_FAILED'
                        if ($Case -in @('import-exception','driver-import-unload-exception')) { throw 'Injected uncertain native import completion' }
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
            param([string]$UserSID)
            Write-Host 'HIVE_CHECKED'
            $script:hiveChecks++
            if ($Case -match '^driver-(?:auto|explicit)-') {
                if ($Case -eq 'driver-auto-hive-error' -and $UserSID -match '1002$') {
                    throw [UnauthorizedAccessException]::new('Injected hive access denied')
                }
                return $script:hiveLoaded
            }
            if ($Case -like '*duplicate*') {
                if ($UserSID -cnotin @('S-1-5-21-1-2-3-1001', 'S-1-5-21-1-2-3-1002')) {
                    throw "Noncanonical hive lookup: $UserSID"
                }
                if ($Case -like '*ineligible' -and $UserSID -eq 'S-1-5-21-1-2-3-1001') { return $false }
            }
            if ($Case -eq 'driver-hive-check-exception' -and $script:hiveChecks -eq 1) {
                throw 'Injected first-user hive-check exception'
            }
            if ($Case -in @('mixed-targets','driver-mixed-targets')) { return $script:hiveLoaded }
            if ($Case -in @('hive-unavailable','missing-profile','missing-ntuser')) { return $false }
            if ($Case -in @('mounted-build-failure', 'mounted-success','expanded-profile',
                'driver-mount-exception','driver-unload-exception','driver-import-unload-exception','driver-unload-exit')) {
                return $script:hiveLoaded
            }
            return $true
        }
        function Get-ProfileImagePath {
            param([string]$UserSID)
            if ($Case -eq 'driver-auto-no-eligible') { return $null }
            if ($Case -match '^driver-(?:auto|explicit)-' -and $UserSID -match '1002$') {
                if ($Case -in @('driver-auto-stale','driver-explicit-stale','driver-auto-whatif','driver-auto-import-error')) { return $null }
                if ($Case -in @('driver-auto-missing-ntuser','driver-explicit-missing-ntuser')) { return [IO.Path]::Combine($fixture,'absent') }
                if ($Case -eq 'driver-auto-query-error') { throw 'Injected ProfileImagePath query failed: Access is denied.' }
                if ($Case -eq 'driver-auto-invalid-path') { throw 'ProfileImagePath must be a fully qualified drive or UNC path without dot segments.' }
                if ($Case -eq 'driver-auto-path-error') { return [IO.Path]::Combine($fixture,'denied') }
            }
            if ($Case -like '*duplicate*ineligible' -and $UserSID -eq 'S-1-5-21-1-2-3-1001') { return $null }
            if ($Case -in @('hive-unavailable','missing-profile') -or
                ($Case -in @('mixed-targets','driver-mixed-targets') -and $UserSID -match '1002$')) { return $null }
            if ($Case -eq 'missing-ntuser') { return [IO.Path]::Combine($fixture,'absent') }
            return $fixture
        }
        function Mount-UserHive {
            param([string]$UserSID, [string]$ProfilePath)
            Write-Host 'HIVE_MOUNTED'
            $script:mountCount++
            if ($Case -eq 'driver-auto-mount-failure' -and $UserSID -match '1002$') { return $false }
            if ($Case -eq 'driver-mount-exception' -and $script:mountCount -eq 1) {
                throw 'Injected first-user hive-load exception'
            }
            if ($Case -eq 'hive-unavailable') { return $false }
            $script:hiveLoaded = $true
            return $true
        }
        function Dismount-UserHive {
            param([string]$UserSID)
            Write-Host 'HIVE_DISMOUNTED'
            $script:hiveLoaded = $false
            $script:unloadCount++
            if ($Case -in @('driver-unload-exception','driver-import-unload-exception') -and $script:unloadCount -eq 1) {
                throw 'Injected first-user hive-unload exception'
            }
            if ($Case -eq 'driver-unload-exit') {
                & $script:originalUnload -UserSID $UserSID
            }
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
            [CmdletBinding()]
            param([string]$LiteralPath, [string]$Path, [string]$PathType)
            if ($Case -eq 'driver-auto-path-error' -and $LiteralPath -like '*\denied\NTUSER.DAT') {
                throw [UnauthorizedAccessException]::new('Injected profile file access denied')
            }
            if ($LiteralPath) { return [IO.File]::Exists($LiteralPath) }
            return $true
        }
        Set-Item -LiteralPath "Function:\$env:SystemRoot\System32\pairtool.exe" -Value {
            Write-Host 'DISASSOCIATED'
            $script:pairCount++
            if ($Case -eq 'driver-pair-exception' -and $script:pairCount -eq 1) {
                throw 'Injected first-printer disassociation exception'
            }
            $global:LASTEXITCODE = 0
        }
        $script:originalBuild = ${function:Build-PerUserRegContent}
        function Build-PerUserRegContent {
            param ($UserSID, $ShareId, $InstanceGuid, $TenantId, $PerSystem)
            Write-Host 'BUILT'
            Write-Host "BUILT_FOR:$UserSID"
            if ($Case -in @('build-failure', 'mounted-build-failure','driver-auto-build-error') -or
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
        if ($Case -eq 'expanded-profile') {
            $env:UPConvertProfileFixture = $fixture
            Set-Item Function:\Get-ProfileImagePath $script:originalProfile
            Set-Item Function:\Mount-UserHive $script:originalMount
        }
        $share = '11111111-2222-3333-4444-555555555555'
        $arguments = @{
            ShareId = $share
            TenantId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
            TargetSIDs = @('S-1-5-21-1-2-3-1001', 'S-1-5-21-1-2-3-1002')
            Timestamp = 'test'
            SkipDisassociate = $false
        }
        if ($Case -eq 'invalid-sid') { $arguments.TargetSIDs = @('not-a-sid') }
        if ($Case -eq 'comma-sids') { $arguments.TargetSIDs = @('S-1-5-21-1-2-3-1001,S-1-5-21-1-2-3-1002') }
        if ($Case -eq 'range-sid') { $arguments.TargetSIDs = @('S-1-5-21-1-2-3-4294967296') }
        if ($Case -like '*duplicate*') {
            $arguments.TargetSIDs = @('s-1-5-21-1-2-3-01001', 'S-1-5-21-1-2-3-1001',
                'S-1-5-21-1-2-3-1002', 's-1-5-21-1-2-3-1001', 'S-1-5-21-1-2-3-01002')
        }
        if ($Case -in @('mixed-targets','driver-mixed-targets')) { $arguments.TargetSIDs += 'not-a-sid' }
        if ($Case -eq 'driver-no-targets') { $arguments.TargetSIDs = @('not-a-sid') }
        if ($Case -eq 'whatif') { $arguments.WhatIfMode = $true }
        if ($Case -eq 'driver-auto-invalid-sid') { $arguments.TargetSIDs[1] = 'not-a-sid' }
        if ($Case -eq 'driver-boundary-exception') {
            $script:originalConvert = ${function:Convert-OnePrinter}
            $script:conversionCount = 0
            function Convert-OnePrinter {
                param($ShareId, $TenantId, $TargetSIDs, $Timestamp, [switch]$WhatIfMode, [switch]$SkipDisassociate, [switch]$AutomaticallyEnumeratedTargets)
                $script:conversionCount++
                if ($script:conversionCount -eq 1) { throw 'Injected first-printer outer-boundary exception' }
                & $script:originalConvert @PSBoundParameters
            }
        }
        if ($Case -eq 'printer-enumeration-failure') {
            $resolution = @($ast.EndBlock.Statements | Where-Object {
                $_ -is [Management.Automation.Language.TryStatementAst] -and
                $_.Extent.Text.Contains('$shareIdsToConvert = @(Get-AllPerSystemShareIds)')
            })
            if ($resolution.Count -ne 1) { throw 'Could not identify production printer enumeration' }
            $resolutionText = $resolution[0].Extent.Text.Replace('$PSCmdlet.ParameterSetName', "'ConvertAll'")
            . ([scriptblock]::Create($resolutionText))
            throw 'Printer enumeration failure did not exit'
        }
        if ($Case -like 'driver-*') {
            $shareIdsToConvert = @($share, '22222222-2222-3333-4444-555555555555')
            $targetSIDs = $arguments.TargetSIDs
            $UserSIDs = $arguments.TargetSIDs
            if ($Case -like 'driver-auto-*') {
                $UserSIDs = @()
                function Get-AllRealUserSIDs { return $arguments.TargetSIDs }
            }
            if ($Case -eq 'driver-enumeration-failure') { $UserSIDs = @() }
            $TenantId = $arguments.TenantId
            $WhatIfMode = ($Case -eq 'driver-auto-whatif')
            $SkipDisassociate = $false
            $SkipRestart = $false
            $results = @()
            $statements = @($ast.EndBlock.Statements)
            $start = @($statements | Where-Object {
                if ($Case -like '*duplicate*' -or $Case -eq 'driver-enumeration-failure' -or
                    $Case -match '^driver-(?:auto|explicit)-') {
                    $_.Extent.Text -eq 'Write-Host "Resolving target users..." -ForegroundColor Cyan'
                } else {
                    $_ -is [Management.Automation.Language.AssignmentStatementAst] -and
                    $_.Left.Extent.Text -eq '$timestamp'
                }
            })
            if ($start.Count -ne 1) { throw 'Could not identify production driver assignment' }
            $driver = ($statements | Where-Object {
                $_.Extent.StartOffset -ge $start[0].Extent.StartOffset
            } | ForEach-Object { $_.Extent.Text }) -join "`r`n"
            . ([scriptblock]::Create($driver))
            Write-Host 'AFTER_DRIVER'
            exit 0
        }
        $result = Convert-OnePrinter @arguments
        Write-Host "RETURNED:$($result.Success)"
        Write-Host "INSTALLS:$($result.Installs.Count)"
        Write-Host "PREFERENCE_AFTER:$ErrorActionPreference"
    }
    finally {
        Write-Host "QUERIES:$script:queryCount"
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
$entraTargets = @(Get-UniqueTargetSIDs -TargetSIDs @(
    's-1-12-1-01-2-3-4294967295', 'S-1-12-1-1-2-3-4294967295',
    'S-1-12-1-4-5-6-7') 6>$null)
if (($entraTargets -join ',') -cne 'S-1-12-1-1-2-3-4294967295,S-1-12-1-4-5-6-7') {
    throw 'Entra target canonicalization/order failed'
}
$checks++
foreach ($preferenceValue in @('Continue', 'Stop', 'SilentlyContinue')) {
    foreach ($exit in @(0, 7)) {
        $savedPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = $preferenceValue
            $global:LASTEXITCODE = 123
            $native = Invoke-ConversionNative -Command $env:ComSpec -Arguments @(
                '/d', '/c', "echo harmless-native-probe 1>&2 & exit /b $exit")
            if ($native.ExitCode -ne $exit -or ($native.Output -join ' ') -notmatch 'harmless-native-probe') {
                throw 'Native stderr/exit handling failed'
            }
            if ($ErrorActionPreference -ne $preferenceValue) { throw 'Native boundary changed caller preference' }
            if ($global:LASTEXITCODE -ne 123 -or ($native.Output -join ' ') -match 'System.Management.Automation.RemoteException') {
                throw 'Native boundary changed LASTEXITCODE or leaked exception type text'
            }
        } finally { $ErrorActionPreference = $savedPreference }
        $checks++
    }
}
foreach ($preferenceValue in @('Continue', 'Stop', 'SilentlyContinue')) {
    foreach ($caseValue in @('success', 'mounted-success', 'hive-unavailable',
        'parent-failure', 'build-failure', 'mounted-build-failure', 'write-failure',
        'read-failure', 'backup-collision', 'export-failure', 'import-failure', 'import-exception',
        'driver-failure', 'driver-import-failure', 'driver-service-failure',
        'driver-query-exception', 'driver-pair-exception', 'driver-hive-check-exception',
        'driver-mount-exception', 'driver-unload-exception', 'driver-import-unload-exception',
        'driver-unload-exit','driver-boundary-exception','invalid-sid','comma-sids',
        'range-sid','missing-profile','missing-ntuser','mixed-targets','whatif',
        'driver-no-targets','driver-mixed-targets','duplicates','duplicates-ineligible',
        'driver-duplicates','driver-duplicates-ineligible','expanded-profile','query-denied',
        'driver-enumeration-failure','printer-enumeration-failure',
        'driver-auto-stale','driver-explicit-stale','driver-auto-missing-ntuser',
        'driver-explicit-missing-ntuser','driver-auto-no-eligible','driver-auto-query-error',
        'driver-auto-hive-error','driver-auto-path-error','driver-auto-build-error',
        'driver-auto-import-error','driver-auto-whatif','driver-auto-invalid-sid',
        'driver-auto-mount-failure','driver-auto-invalid-path')) {
        $output = (& $runtime -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath `
            -Case $caseValue -Preference $preferenceValue 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE
        $expectedPayloads = switch ($caseValue) {
            'success' { 2 } 'mounted-success' { 2 } 'write-failure' { 1 } 'hive-unavailable' { 0 }
            'import-failure' { 2 } 'import-exception' { 2 } 'driver-failure' { 2 }
            'driver-import-failure' { 4 } 'driver-service-failure' { 4 }
            'driver-query-exception' { 2 } 'driver-pair-exception' { 4 }
            'driver-hive-check-exception' { 3 } 'driver-mount-exception' { 4 }
            'driver-unload-exception' { 4 } 'driver-import-unload-exception' { 4 }
            'driver-unload-exit' { 4 } 'driver-boundary-exception' { 2 }
            'mixed-targets' { 1 } 'whatif' { 2 }
            'driver-no-targets' { 0 } 'driver-mixed-targets' { 2 }
            'duplicates' { 2 } 'duplicates-ineligible' { 1 }
            'driver-duplicates' { 4 } 'driver-duplicates-ineligible' { 2 }
            'expanded-profile' { 2 }
            'driver-auto-stale' { 2 } 'driver-explicit-stale' { 2 }
            'driver-auto-missing-ntuser' { 2 } 'driver-explicit-missing-ntuser' { 2 }
            'driver-auto-query-error' { 2 } 'driver-auto-hive-error' { 2 }
            'driver-auto-path-error' { 2 } 'driver-auto-invalid-path' { 2 }
            'driver-auto-invalid-sid' { 2 } 'driver-auto-import-error' { 2 }
            'driver-auto-mount-failure' { 4 } 'driver-auto-whatif' { 2 }
            default { 0 }
        }
        if ($output -notmatch "PAYLOADS_REMAINING:$expectedPayloads") {
            throw "$caseValue/$preferenceValue retained unexpected payloads:`n$output"
        }
        $policyCase = $caseValue -match '^driver-(?:auto|explicit)-'
        $postDisassociation = ($caseValue -like 'driver-*' -and -not $policyCase -and $caseValue -notin @('driver-no-targets','driver-mixed-targets','driver-duplicates-ineligible','driver-enumeration-failure')) -or $caseValue -in @('success', 'mounted-success', 'duplicates','expanded-profile',
            'import-failure', 'import-exception')
        if ($postDisassociation) {
            if ($output -notmatch '(?s)EXPORTED.*BUILT.*BUILT.*DISASSOCIATED.*HIVE_CHECKED') {
                throw "Payloads were not fully prepared before disassociation:`n$output"
            }
        } elseif (-not $policyCase -and $caseValue -notin @('mixed-targets','driver-mixed-targets','duplicates-ineligible','driver-duplicates-ineligible') -and $output -match 'DISASSOCIATED|IMPORTED') {
            throw "Preflight failure reached destructive migration:`n$output"
        }
        if ($caseValue -in @('parent-failure','read-failure','backup-collision','export-failure') -and
            $output -match 'HIVE_CHECKED|BUILT') {
            throw "Backup failure reached hive/payload preflight:`n$output"
        }
        if ($caseValue -in @('mounted-success','expanded-profile') -and
            $output -notmatch '(?s)BUILT.*DISASSOCIATED.*HIVE_MOUNTED.*IMPORTED.*HIVE_DISMOUNTED') {
            throw "Owned hive was not unloaded:`n$output"
        }
        if ($policyCase) {
            $warningOnly = $caseValue -in @('driver-auto-stale','driver-auto-missing-ntuser','driver-auto-whatif')
            $expectedExit = if ($warningOnly) { 0 } else { 1 }
            $failedCount = if ($warningOnly) { 0 } elseif ($caseValue -eq 'driver-auto-import-error') { 1 } else { 2 }
            $skips = if ($caseValue -eq 'driver-auto-no-eligible') { 2 } elseif ($warningOnly -or $caseValue -eq 'driver-auto-import-error') { 1 } else { 0 }
            $imports = if ($caseValue -in @('driver-auto-no-eligible','driver-auto-build-error','driver-auto-whatif')) { 0 } elseif ($caseValue -eq 'driver-auto-import-error') { 1 } else { 2 }
            $pairs = if ($caseValue -in @('driver-auto-no-eligible','driver-auto-build-error','driver-auto-whatif')) { 0 } else { 2 }
            if ($exitCode -ne $expectedExit -or $output -notmatch "Failed\s+:\s+$failedCount" -or
                $output -notmatch "Succeeded\s+:\s+$(2 - $failedCount)" -or
                ([regex]::Matches($output, 'WARN: Skipping automatically discovered target')).Count -ne (2 * $skips) -or
                ([regex]::Matches($output, "skipped=$skips")).Count -ne 2 -or
                ([regex]::Matches($output, '(?m)^IMPORTED\r?$')).Count -ne $imports -or
                ([regex]::Matches($output, '(?m)^DISASSOCIATED\r?$')).Count -ne $pairs) {
                throw "Enumeration/explicit eligibility policy failed:`n$output"
            }
            if ($caseValue -eq 'driver-auto-whatif') {
                if ($output -match 'RESTARTED:' -or $output -notmatch '\[WHATIF\]') { throw "WhatIf policy case mutated host operations:`n$output" }
            } elseif ($output -notmatch 'RESTARTED:DeviceAssociationService' -or $output -notmatch 'RESTARTED:Spooler') {
                throw "Policy case did not finalize:`n$output"
            }
            $expectedSummary = if ($warningOnly) {
                if ($caseValue -eq 'driver-auto-whatif') { 'installs=0/1' } else { 'installs=1/1' }
            } elseif ($caseValue -eq 'driver-auto-no-eligible') { 'installs=0/0' }
            elseif ($caseValue -eq 'driver-auto-build-error') { 'installs=0/2' }
            elseif ($caseValue -eq 'driver-auto-import-error') { 'installs=0/1' }
            else { 'installs=1/2' }
            if ($output -notmatch $expectedSummary) { throw "Skipped/failed install summary was misleading:`n$output" }
            $expectedDiagnostic = switch ($caseValue) {
                'driver-auto-no-eligible' { 'No eligible targets.*leaving the per-system printer unchanged' }
                'driver-auto-query-error' { 'Injected ProfileImagePath query failed' }
                'driver-auto-hive-error' { 'Injected hive access denied' }
                'driver-auto-path-error' { 'Injected profile file access denied' }
                'driver-auto-invalid-path' { 'fully qualified drive or UNC path' }
                'driver-auto-invalid-sid' { "Ineligible target 'not-a-sid'" }
                'driver-auto-build-error' { 'Private payload preparation failed' }
                'driver-auto-import-error' { 'reg import failed' }
                'driver-auto-mount-failure' { 'hive not available' }
                default { 'ProfileImagePath is missing|NTUSER.DAT is missing' }
            }
            if ($output -notmatch $expectedDiagnostic) { throw "Policy case lost diagnostic:`n$output" }
        } elseif ($caseValue -eq 'printer-enumeration-failure') {
            if ($exitCode -ne 1 -or $output -notmatch 'Could not enumerate printers.*enumeration failed.*Access is denied' -or
                $output -match 'Nothing to do|No target users|RESTARTED:|RETURNED:|DISASSOCIATED|IMPORTED') {
                throw "Printer enumeration failure was hidden:`n$output"
            }
        } elseif ($caseValue -eq 'driver-enumeration-failure') {
            if ($exitCode -ne 1 -or $output -notmatch 'Could not enumerate target users.*ProfileList query failed.*Access is denied' -or
                $output -match 'Nothing to do|No target users|RESTARTED:|RETURNED:|DISASSOCIATED|IMPORTED') {
                throw "Enumeration failure was hidden:`n$output"
            }
        } elseif ($caseValue -eq 'query-denied') {
            if ($exitCode -ne 0 -or $output -notmatch 'RETURNED:False' -or
                $output -notmatch 'DAF query failed.*exit 1.*Access is denied' -or
                $output -match 'no DAF entry|not found|BUILT|DISASSOCIATED|IMPORTED') {
                throw "DAF query failure was misreported:`n$output"
            }
        } elseif ($caseValue -like '*duplicate*') {
            $printerCount = if ($caseValue -like 'driver-*') { 2 } else { 1 }
            $installs = if ($caseValue -like '*ineligible') { 1 } else { 2 }
            $expectedExit = if ($caseValue -eq 'driver-duplicates-ineligible') { 1 } else { 0 }
            $builtSIDs = @([regex]::Matches($output, '(?m)^BUILT_FOR:(.+)\r?$') |
                ForEach-Object { $_.Groups[1].Value.TrimEnd("`r") })
            $expectedSIDs = @()
            for ($i = 0; $i -lt $printerCount; $i++) {
                if ($installs -eq 2) { $expectedSIDs += 'S-1-5-21-1-2-3-1001' }
                $expectedSIDs += 'S-1-5-21-1-2-3-1002'
            }
            if ($exitCode -ne $expectedExit -or $output -notmatch "QUERIES:$printerCount" -or
                ([regex]::Matches($output, 'already listed; skipping duplicate')).Count -ne 3 -or
                ($builtSIDs -join ',') -cne ($expectedSIDs -join ',') -or
                ([regex]::Matches($output, '(?m)^IMPORTED\r?$')).Count -ne ($installs * $printerCount)) {
                throw "Canonical duplicate handling/order/count failed:`n$output"
            }
            if ($caseValue -like 'driver-*') {
                if (([regex]::Matches($output, "installs=$installs/2")).Count -ne 2 -or
                    $output -notmatch 'RESTARTED:Spooler' -or
                    ($installs -eq 2 -and $output -notmatch 'Succeeded\s+:\s+2')) {
                    throw "Unique-target driver summary failed:`n$output"
                }
            } elseif ($output -notmatch "INSTALLS:$installs" -or
                $output -notmatch "PREFERENCE_AFTER:$preferenceValue") {
                throw "Direct-helper duplicate handling failed:`n$output"
            }
        } elseif ($caseValue -in @('success', 'mounted-success','expanded-profile')) {
            if ($exitCode -ne 0 -or $output -notmatch 'INSTALLS:2' -or $output -notmatch 'RETURNED:True') {
                throw "Success case failed under ${preferenceValue}:`n$output"
            }
        } elseif ($caseValue -in @('hive-unavailable','invalid-sid','comma-sids','range-sid','missing-profile','missing-ntuser')) {
            if ($exitCode -ne 0 -or $output -notmatch 'INSTALLS:0' -or
                $output -notmatch 'RETURNED:False' -or $output -match 'IMPORTED') {
                throw "Unavailable hives were not reported as incomplete migration:`n$output"
            }
            if ($output -notmatch 'No eligible targets') { throw "No-eligible guard missing:`n$output" }
        } elseif ($caseValue -eq 'mixed-targets') {
            if ($exitCode -ne 0 -or $output -notmatch 'RETURNED:False' -or
                $output -notmatch 'INSTALLS:1' -or $output -notmatch 'DISASSOCIATED' -or
                $output -notmatch "Ineligible target 'not-a-sid'" -or $output -notmatch 'ProfileImagePath is missing') {
                throw "Mixed target eligibility was not best-effort:`n$output"
            }
        } elseif ($caseValue -eq 'whatif') {
            if ($exitCode -ne 0 -or $output -notmatch 'RETURNED:True' -or
                $output -notmatch '\[WHATIF\]' -or $output -match '(?m)^IMPORTED\r?$|^DISASSOCIATED\r?$') {
                throw "WhatIf mutated host operations:`n$output"
            }
        } elseif ($caseValue -eq 'export-failure') {
            if ($exitCode -ne 0 -or $output -notmatch 'RETURNED:False' -or $output -notmatch 'BACKUPS_REMAINING:0') {
                throw "Export failure handling failed:`n$output"
            }
        } elseif ($caseValue -like 'driver-*') {
            $failedCount = if ($caseValue -eq 'driver-service-failure') { 0 } elseif ($caseValue -in @('driver-no-targets','driver-mixed-targets')) { 2 } else { 1 }
            $succeededCount = 2 - $failedCount
            $imports = switch ($caseValue) {
                'driver-failure' { 2 } 'driver-import-failure' { 3 }
                'driver-query-exception' { 2 } 'driver-pair-exception' { 2 }
                'driver-hive-check-exception' { 3 } 'driver-mount-exception' { 3 }
                'driver-import-unload-exception' { 3 } 'driver-boundary-exception' { 2 }
                'driver-no-targets' { 0 } 'driver-mixed-targets' { 2 } default { 4 }
            }
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
            if ($caseValue -like '*exception' -and $output -notmatch 'Injected first-') {
                throw "Unexpected error context was lost:`n$output"
            }
            if ($caseValue -eq 'driver-import-unload-exception' -and
                ($output -notmatch 'Injected uncertain native import' -or $output -notmatch 'Injected first-user hive-unload')) {
                throw "Cleanup failure masked original import error:`n$output"
            }
            if ($caseValue -eq 'driver-unload-exit' -and $output -notmatch 'reg unload failed.*exit 5') {
                throw "Native hive-unload failure was not reported:`n$output"
            }
        } elseif ($caseValue -in @('import-failure','import-exception')) {
            if ($exitCode -ne 0 -or $output -notmatch 'RETURNED:False' -or
                $output -notmatch 'INSTALLS:1' -or $output -notmatch 'IMPORT_FAILED.*' -or
                $output -notmatch 'IMPORTED') { throw "Later users were not completed/reported:`n$output" }
        } else {
            if ($exitCode -ne 0 -or $output -match 'IMPORTED' -or
                $output -match 'RETURNED:True' -or
                $output -notmatch 'RETURNED:False' -or
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

# Exercise real profile parsing/mount and registry error handling with host I/O mocked.
& {
    function Invoke-ConversionNative {
        param($Command, $Arguments)
        if ($script:registryFailure) {
            return [pscustomobject]@{ ExitCode = 1; Output = @('ERROR: Access is denied.') }
        }
        return [pscustomobject]@{ ExitCode = 0; Output = @("ProfileImagePath    REG_EXPAND_SZ    $script:profileProbe") }
    }
    foreach ($path in @('C:relative', '\relative', 'C:\Users\..\other', '\\server\share\..\other', '%UNRESOLVED_UPCONVERT_VAR%\user')) {
        $script:profileProbe = $path
        $rejected = $false
        try { Get-ProfileImagePath -UserSID 'S-1-5-21-1-2-3-1001' }
        catch { $rejected = $_.Exception.Message -match 'fully qualified' }
        if (-not $rejected) { throw "Ambiguous profile path accepted: $path" }
    }
    foreach ($path in @('C:\Users\test', '\\server\share\test', '%SystemDrive%\Users\test')) {
        $script:profileProbe = $path
        if ((Get-ProfileImagePath -UserSID 'S-1-5-21-1-2-3-1001') -cne
            [Environment]::ExpandEnvironmentVariables($path)) { throw "Profile path changed unexpectedly: $path" }
    }
    $script:registryFailure = $true
    foreach ($helper in @('Get-AllRealUserSIDs','Get-AllPerSystemShareIds','Get-ProfileImagePath')) {
        $rejected = $false
        try { & $helper }
        catch { $rejected = $_.Exception.Message -match 'query failed|enumeration failed' -and $_.Exception.Message -match 'Access is denied' }
        if (-not $rejected) { throw "Registry query failure hidden by $helper" }
    }
    function Get-Item {
        [CmdletBinding()]
        param($LiteralPath)
        if ($script:missingHive) { throw [Management.Automation.ItemNotFoundException]::new('missing hive') }
        if ($script:deniedHive) { throw [UnauthorizedAccessException]::new('denied hive') }
        return [pscustomobject]@{}
    }
    if (-not (Test-HiveLoaded -UserSID 'test')) { throw 'Existing hive rejected' }
    $script:missingHive = $true
    if (Test-HiveLoaded -UserSID 'test') { throw 'Missing hive accepted' }
    $script:missingHive = $false
    $script:deniedHive = $true
    $rejected = $false
    try { Test-HiveLoaded -UserSID 'test' }
    catch { $rejected = $_.Exception.Message -match 'denied hive' }
    if (-not $rejected) { throw 'Inaccessible hive treated as unloaded' }
}
$checks += 14
& {
    Remove-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    $null = Invoke-ConversionNative -Command $env:ComSpec -Arguments @('/d','/c','exit /b 0')
    if (Get-Variable LASTEXITCODE -Scope Global -ErrorAction Ignore) { throw 'Native wrapper created a caller LASTEXITCODE' }
    $global:LASTEXITCODE = 321
    function NoExitCode {}
    $rejected = $false
    try { Invoke-ConversionNative -Command 'NoExitCode' }
    catch { $rejected = $_.Exception.Message -match 'did not return an exit code' }
    if (-not $rejected -or $global:LASTEXITCODE -ne 321) { throw 'Native wrapper failure did not preserve caller exit code' }
    function ThrowingNative { throw 'Injected invocation exception' }
    $rejected = $false
    try { Invoke-ConversionNative -Command 'ThrowingNative' }
    catch { $rejected = $_.Exception.Message -match 'Injected invocation exception' }
    if (-not $rejected -or $global:LASTEXITCODE -ne 321) { throw 'Native invocation exception lost caller exit code' }
}
$checks += 3

# ACL policy cases use synthetic Windows ACLs and metadata; no host ACL is changed.
$script:testAcl = [Security.AccessControl.DirectorySecurity]::new()
$script:testAcl.SetSecurityDescriptorSddlForm('O:SYG:SYD:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)')
$script:ancestorAcl = [Security.AccessControl.DirectorySecurity]::new()
# Typical root/Windows patterns: read/traverse, create sibling directories, and
# inherit-only CREATOR OWNER grants do not permit replacing the existing child.
$script:ancestorAcl.SetSecurityDescriptorSddlForm(
    'O:SYG:SYD:PAI(A;;FA;;;SY)(A;;FA;;;BA)(A;;FRFX;;;BU)(A;;0x4;;;BU)(A;OICIIO;GA;;;CO)')
function Get-Acl {
    param([string]$LiteralPath)
    if ($LiteralPath -eq $systemTemp) { return $script:testAcl }
    return $script:ancestorAcl
}
function Get-Item {
    return [pscustomobject]@{ PSIsContainer = $true; Attributes = [IO.FileAttributes]::Directory }
}
$systemTemp = [IO.Path]::Combine(
    [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows), 'SystemTemp')
Assert-SystemTempParent -Path $systemTemp
$checks++
foreach ($rights in @('0x2','0x10','0x100','0x40','0x10000','0x40000','0x80000','GA','GW')) {
    $script:ancestorAcl.SetSecurityDescriptorSddlForm("O:SYG:SYD:PAI(A;;$rights;;;BU)")
    $rejected = $false
    try { Assert-SystemTempParent -Path $systemTemp }
    catch { $rejected = $true }
    if (-not $rejected) { throw "Dangerous ancestor allow accepted: $rights" }
    $checks++
}
foreach ($sddl in @(
    'O:SYG:SYD:PAI(D;;FA;;;BU)(A;;GA;;;BU)',
    'O:SYG:SYD:PAI(A;;GA;;;BU)(D;;FA;;;BU)',
    'O:BUG:SYD:PAI(A;;FA;;;SY)',
    'O:SYG:SYD:NO_ACCESS_CONTROL'
)) {
    $script:ancestorAcl.SetSecurityDescriptorSddlForm($sddl)
    $rejected = $false
    try { Assert-SystemTempParent -Path $systemTemp }
    catch { $rejected = $true }
    if (-not $rejected) { throw "Unsafe ancestor security accepted: $sddl" }
    $checks++
}
$script:ancestorAcl.SetSecurityDescriptorSddlForm('O:SYG:SYD:PAI(A;;FA;;;SY)(A;OICIIO;GA;;;BU)')
$script:visited = @()
function Get-Item {
    param([string]$LiteralPath)
    $script:visited += $LiteralPath
    return [pscustomobject]@{ PSIsContainer = $true; Attributes = [IO.FileAttributes]::Directory }
}
Assert-SystemTempParent -Path $systemTemp
$expected = @()
$directory = [IO.DirectoryInfo]::new($systemTemp)
while ($directory) { $expected = @($directory.FullName) + $expected; $directory = $directory.Parent }
if (($script:visited -join '|') -ne ($expected -join '|')) { throw 'Ancestor traversal was not top-down' }
$checks++
$script:ancestorAcl.SetSecurityDescriptorSddlForm('O:SYG:SYD:PAI(A;;0x40;;;BU)')
$script:visited = @()
$rejected = $false
try { Assert-SystemTempParent -Path $systemTemp }
catch { $rejected = $true }
if (-not $rejected -or $script:visited.Count -ne 1) { throw 'Inspected child beneath an unsafe parent' }
$checks++
$script:ancestorAcl.SetSecurityDescriptorSddlForm('O:SYG:SYD:PAI(A;;FA;;;SY)')
foreach ($sddl in @(
    'O:SYG:SYD:PAI(A;;GA;;;BU)',
    'O:SYG:SYD:PAI(A;;FRFX;;;BU)',
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
foreach ($sddl in @(
    'O:SYG:SYD:PAI(A;;FA;;;SY)(A;;FA;;;BA)(A;OICIIO;GA;;;CO)',
    'O:SYG:SYD:PAI(A;;FA;;;SY)(A;OICIIO;GA;;;BU)'
)) {
    $script:testAcl.SetSecurityDescriptorSddlForm($sddl)
    Assert-SystemTempParent -Path $systemTemp
    $checks++
}
# Observed Entra-device descriptor: applicable primary-user FullControl is a
# deliberate policy rejection, not automatically trusted through group lookup.
$script:testAcl.SetSecurityDescriptorSddlForm(
    'O:SYD:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;FA;;;S-1-12-1-111-222-333-444)')
$rejected = $false
try { Assert-SystemTempParent -Path $systemTemp }
catch {
    $rejected = $_.Exception.Message -match 'Ask your administrator.*no ACL was changed'
}
if (-not $rejected) { throw 'Observed Entra ACL did not produce actionable policy rejection' }
$checks++
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

# Exercise the real managed directory factory on an isolated parent. Substitute
# only its parent and owner (the available token is not SYSTEM), not ACL creation.
$factory = $ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'New-PrivateStagingDirectory'
}, $false).Extent.Text
$factoryFixture = Join-Path ([IO.Path]::GetTempPath()) "UPConvert-factory-$([Guid]::NewGuid().ToString('N'))"
$null = [IO.Directory]::CreateDirectory($factoryFixture)
$factoryMarker = Join-Path $factoryFixture '.upconvert-test'
[IO.File]::WriteAllText($factoryMarker, 'UPConvert factory fixture')
function Assert-SystemTempParent {
    param([string]$Path)
    if ($Path -ne $factoryFixture) { throw 'Factory escaped isolated parent' }
}
try {
    $testFactory = $factory.Replace(
        '$parent = [IO.Path]::Combine($windows, ''SystemTemp'')', '$parent = $factoryFixture').Replace(
        '$owner = [Security.Principal.SecurityIdentifier]::new(''S-1-5-18'')',
        '$owner = [Security.Principal.WindowsIdentity]::GetCurrent().User')
    . ([scriptblock]::Create($testFactory))
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        $whatIfPath = New-PrivateStagingDirectory -WhatIfMode
        $whatIfAcl = Microsoft.PowerShell.Security\Get-Acl -LiteralPath $whatIfPath
        if ($whatIfAcl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $identity.User.Value) {
            throw 'WhatIf factory did not use the elevated caller owner'
        }
    } else {
        $rejected = $false
        try { New-PrivateStagingDirectory -WhatIfMode }
        catch { $rejected = $_.Exception.Message -match 'elevated administrator' }
        if (-not $rejected) { throw 'WhatIf factory accepted a nonelevated caller' }
    }
    $checks++
    $created = @(New-PrivateStagingDirectory; New-PrivateStagingDirectory)
    if ($created.Count -ne 2 -or $created[0] -eq $created[1]) { throw 'Factory reused a directory' }
    foreach ($path in $created) {
        $acl = Microsoft.PowerShell.Security\Get-Acl -LiteralPath $path -ErrorAction Stop
        $rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
        if (-not $acl.AreAccessRulesProtected -or $rules.Count -ne 2 -or
            $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne
                [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {
            throw 'Real directory ACL protection/owner differs from requested descriptor'
        }
        foreach ($rule in $rules) {
            if ($rule.IsInherited -or $rule.IdentityReference.Value -notin @('S-1-5-18','S-1-5-32-544') -or
                $rule.AccessControlType -ne 'Allow' -or $rule.FileSystemRights -ne 'FullControl' -or
                $rule.InheritanceFlags -ne 'ContainerInherit, ObjectInherit') {
                throw 'Real directory grants differ from SYSTEM/Admin-only inheritable ACL'
            }
        }
        $checks++
    }
    $collisionFactory = $testFactory.Replace(
        '$path = [IO.Path]::Combine($parent, "UPConvert-$([Guid]::NewGuid().ToString(''N''))")',
        '$path = $created[0]')
    . ([scriptblock]::Create($collisionFactory))
    $rejected = $false
    try { New-PrivateStagingDirectory }
    catch { $rejected = $_.Exception.Message -match 'collision' }
    if (-not $rejected) { throw 'Factory accepted an existing directory' }
    $checks++
    # Simulate another creator after Exists, before managed CreateDirectory.
    # An unexpected existing child must not be used, repaired, or removed.
    $lateCollision = Join-Path $factoryFixture 'late-collision'
    $lateFactory = $testFactory.Replace(
        '$path = [IO.Path]::Combine($parent, "UPConvert-$([Guid]::NewGuid().ToString(''N''))")',
        '$path = $lateCollision').Replace(
        '$security = [Security.AccessControl.DirectorySecurity]::new()',
        '$null = [IO.Directory]::CreateDirectory($path); [IO.File]::WriteAllText([IO.Path]::Combine($path, ''KEEP''), ''unchanged''); $security = [Security.AccessControl.DirectorySecurity]::new()')
    . ([scriptblock]::Create($lateFactory))
    $rejected = $false
    try { New-PrivateStagingDirectory }
    catch { $rejected = $_.Exception.Message -match 'owner or protected DACL differs' }
    if (-not $rejected -or [IO.File]::ReadAllText((Join-Path $lateCollision 'KEEP')) -ne 'unchanged') {
        throw 'Late directory collision was consumed or modified'
    }
    [IO.File]::Delete((Join-Path $lateCollision 'KEEP'))
    $checks++
    foreach ($sddl in @('O:BUG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)',
        'O:SYG:SYD:AI(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)',
        'O:SYG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;;FR;;;BU)')) {
        $injectedAcl = [Security.AccessControl.DirectorySecurity]::new()
        $injectedAcl.SetSecurityDescriptorSddlForm($sddl)
        $postconditionFactory = $testFactory.Replace(
            '$actual = Microsoft.PowerShell.Security\Get-Acl -LiteralPath $path -ErrorAction Stop',
            '$actual = $injectedAcl')
        . ([scriptblock]::Create($postconditionFactory))
        $rejected = $false
        try { New-PrivateStagingDirectory }
        catch { $rejected = $_.Exception.Message -match 'owner or protected DACL differs' }
        if (-not $rejected) { throw "Unexpected postcreation security accepted: $sddl" }
        $checks++
    }
} finally {
    if ([IO.File]::Exists($factoryMarker) -and
        [IO.File]::ReadAllText($factoryMarker) -eq 'UPConvert factory fixture') {
        foreach ($child in [IO.Directory]::GetDirectories($factoryFixture)) {
            try {
                # Only this marked fixture's ACL is changed for owner cleanup;
                # production/SystemTemp ACLs are never modified.
                $info = [IO.DirectoryInfo]::new($child)
                if ($PSVersionTable.PSEdition -eq 'Desktop') {
                    $cleanupAcl = $info.GetAccessControl([Security.AccessControl.AccessControlSections]::Access)
                } else {
                    $cleanupAcl = [IO.FileSystemAclExtensions]::GetAccessControl(
                        $info, [Security.AccessControl.AccessControlSections]::Access)
                }
                $cleanupAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
                    [Security.Principal.WindowsIdentity]::GetCurrent().User, 'FullControl', 'Allow'))
                if ($PSVersionTable.PSEdition -eq 'Desktop') {
                    $info.SetAccessControl($cleanupAcl)
                } else { [IO.FileSystemAclExtensions]::SetAccessControl($info, $cleanupAcl) }
                [IO.Directory]::Delete($child, $false)
            } catch { Write-Warning "Factory fixture cleanup failed for '$child': $_" -WarningAction Continue }
        }
        if ([IO.Directory]::GetDirectories($factoryFixture).Count -eq 0) {
            [IO.File]::Delete($factoryMarker)
            [IO.Directory]::Delete($factoryFixture, $false)
        }
    } else { Write-Warning "Refusing factory fixture cleanup: $factoryFixture" }
}
Write-Host "Passed $checks focused staging checks on PowerShell $($PSVersionTable.PSVersion)."
