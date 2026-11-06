#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param([string]$OmaDmAccountId)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$script:UPRegistryPath = 'HKCU:\Software\Microsoft\PrinterProvisioning\UPPrinterInstalls'
$script:UPCmdlet = $PSCmdlet
$script:UPClock = [Diagnostics.Stopwatch]::StartNew()

function Get-UPRemainingSeconds { 1440 - $script:UPClock.Elapsed.TotalSeconds }

function Invoke-UPRead {
    param([scriptblock]$Body, [object[]]$Arguments = @(), [int]$TimeoutMs = 15000)
    $remainingMs = [int]([math]::Max(0, ((Get-UPRemainingSeconds) - 5) * 1000))
    $waitMs = [math]::Min($TimeoutMs, $remainingMs)
    if ($waitMs -le 0) { throw 'UP_BUDGET' }
    $encodedBody = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Body.ToString()))
    $encodedArgs = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(
        [Management.Automation.PSSerializer]::Serialize($Arguments, 4)))
    $command = @'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    $body = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('__BODY__'))
    $arguments = [Management.Automation.PSSerializer]::Deserialize(
        [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('__ARGS__')))
    $items = @(& ([scriptblock]::Create($body)) @arguments)
    $reply = [pscustomobject]@{ Ok=$true; Items=$items; Reason='' }
}
catch {
    $reason = 'UP_READ_OR_RUNTIME_ERROR'
    if ($_.Exception.Message -ceq 'UP_REGISTRY_MISSING') { $reason=$_.Exception.Message }
    $reply = [pscustomobject]@{ Ok=$false; Items=@(); Reason=$reason }
}
[Console]::Out.Write([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(
    [Management.Automation.PSSerializer]::Serialize($reply, 8))))
exit 0
'@
    $command = $command.Replace('__BODY__', $encodedBody).Replace('__ARGS__', $encodedArgs)
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $start.Arguments = "-NoProfile -NonInteractive -OutputFormat Text -EncodedCommand $encodedCommand"
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $reader = New-Object Diagnostics.Process
    $reader.StartInfo = $start
    try {
        if (-not $reader.Start()) { throw 'UP_READ_START_FAILED' }
        $stdout = $reader.StandardOutput.ReadToEndAsync()
        $stderr = $reader.StandardError.ReadToEndAsync()
        if (-not $reader.WaitForExit($waitMs)) {
            # Only this owned, read-only PowerShell child is stopped, never a repair
            # process. In-process runspaces can hold Windows PowerShell open on exit.
            if (-not $reader.HasExited) {
                Stop-Process -Id $reader.Id -Force -ErrorAction Stop -WhatIf:$false
            }
            $null = $reader.WaitForExit(2000)
            throw 'UP_READ_TIMEOUT'
        }
        if (-not $stdout.Wait(2000) -or -not $stderr.Wait(2000) -or $reader.ExitCode -ne 0) {
            throw 'UP_READ_OR_RUNTIME_ERROR'
        }
        if ($stdout.Result.Length -gt 1048576) { throw 'UP_READ_RESULT_TOO_LARGE' }
        $reply = [Management.Automation.PSSerializer]::Deserialize(
            [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($stdout.Result)))
        if (-not $reply.Ok) {
            if ($reply.Reason -ceq 'UP_REGISTRY_MISSING') { throw $reply.Reason }
            throw 'UP_READ_OR_RUNTIME_ERROR'
        }
        foreach ($item in @($reply.Items)) { $item }
    }
    finally { $reader.Dispose() }
}

function Get-UPToken { [Security.Principal.WindowsIdentity]::GetCurrent() }

function Get-UPContext {
    $identity = Get-UPToken
    try {
        $sid = $identity.User.Value
        if (-not $identity.IsAuthenticated -or $identity.IsSystem -or
            $sid -notmatch '^(S-1-5-21-\d+-\d+-\d+-\d+|S-1-12-1-\d+-\d+-\d+-\d+)$') {
            throw 'UP_WRONG_CONTEXT'
        }
        if (-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) {
            throw 'UP_REQUIRE_64BIT'
        }
        [pscustomobject]@{ Sid = $sid }
    }
    finally { $identity.Dispose() }
}

function Get-UPRecords {
    Invoke-UPRead -Arguments @($script:UPRegistryPath) -Body {
        param($RegistryPath)
        if (-not (Test-Path -LiteralPath $RegistryPath -ErrorAction Stop)) {
            throw 'UP_REGISTRY_MISSING'
        }
        foreach ($key in @(Get-ChildItem -LiteralPath $RegistryPath -ErrorAction Stop)) {
            $p = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
            [pscustomobject]@{
                Id = $key.PSChildName
                Name = $(if ($p.PSObject.Properties['PrinterSharedName']) { $p.PrinterSharedName } else { $null })
                Status = $(if ($p.PSObject.Properties['Status']) { $p.Status } else { $null })
                ErrorCode = $(if ($p.PSObject.Properties['ErrorCode']) { $p.ErrorCode } else { $null })
            }
        }
    }
}

function Get-UPQueueNames {
    param([string]$Sid)
    foreach ($printer in @(Invoke-UPRead -Body { Get-Printer -ErrorAction Stop | Select-Object -Property Name })) {
        $name = $printer.Name
        if ($name -isnot [string] -or [string]::IsNullOrWhiteSpace($name)) { throw 'UP_QUEUE_INVALID' }
        if ($name -match '^(S-\d+(?:-\d+)+):') {
            if ($Matches[1] -ne $Sid) { throw 'UP_QUEUE_FOREIGN_PREFIX' }
            $name = $name.Substring($Matches[0].Length)
        }
        if ([string]::IsNullOrWhiteSpace($name)) { throw 'UP_QUEUE_INVALID' }
        $name
    }
}

function ConvertTo-UPGuid {
    param($Value)
    $guid = [guid]::Empty
    if ($Value -isnot [string] -or
        $Value -notmatch '^(\{[0-9a-fA-F-]{36}\}|[0-9a-fA-F-]{36})$' -or
        -not [guid]::TryParse($Value, [ref]$guid) -or $guid -eq [guid]::Empty) {
        throw 'UP_GUID_INVALID'
    }
    $guid.ToString('D')
}

function Get-UPSnapshot {
    param([string]$Sid)
    $records = @(Get-UPRecords)
    $queues = @(Get-UPQueueNames -Sid $Sid)
    $nameCounts = @{}
    $idCounts = @{}
    $queueCounts = @{}
    foreach ($name in $queues) {
        if ($queueCounts.ContainsKey($name)) { $queueCounts[$name]++ } else { $queueCounts[$name] = 1 }
    }
    $normalized = @(
        foreach ($r in $records) {
            $valid = $true
            $id = ''
            $rawId = ''
            try { $id = ConvertTo-UPGuid $r.Id; $rawId = $r.Id } catch { $valid = $false }
            $name = $r.Name
            if ($name -isnot [string] -or [string]::IsNullOrWhiteSpace($name) -or $name -ne $name.Trim()) {
                $valid = $false
                $name = ''
            }
            if ($name) {
                if ($nameCounts.ContainsKey($name)) { $nameCounts[$name]++ } else { $nameCounts[$name] = 1 }
            }
            if ($id) {
                if ($idCounts.ContainsKey($id)) { $idCounts[$id]++ } else { $idCounts[$id] = 1 }
            }
            if (($r.Status -isnot [int] -and $r.Status -isnot [long]) -or $r.Status -notin 1, 4) {
                $valid = $false
            }
            [pscustomobject]@{ Id = $id; RawId = $rawId; Name = $name; Status = $r.Status; ErrorCode = $r.ErrorCode; Valid = $valid }
        }
    )
    $healthy = @()
    $missing = @()
    $unknown = 0
    $cspErrors = 0
    foreach ($r in $normalized) {
        if ($null -ne $r.ErrorCode -and $r.ErrorCode -ne 0) { $cspErrors++ }
        if (-not $r.Valid -or $nameCounts[$r.Name] -ne 1 -or $idCounts[$r.Id] -ne 1) {
            $unknown++
            continue
        }
        $queueCount = 0
        if ($queueCounts.ContainsKey($r.Name)) { $queueCount = $queueCounts[$r.Name] }
        if ($queueCount -eq 0) { $missing += $r }
        elseif ($queueCount -eq 1 -and $r.Status -eq 1) { $healthy += $r }
        else { $unknown++ }
    }
    [pscustomobject]@{
        Total = $records.Count; Healthy = $healthy; Missing = $missing
        Unknown = $unknown; CspErrors = $cspErrors
    }
}

function Get-UPWorkRoot {
    $root = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($root)) { throw 'UP_STATE_LOCATION' }
    $root
}

function Get-UPReason {
    param($Record)
    $message = $Record.Exception.Message
    $known = @(
        'UP_BUDGET','UP_READ_START_FAILED','UP_READ_TIMEOUT','UP_READ_RESULT_TOO_LARGE',
        'UP_WRONG_CONTEXT','UP_REQUIRE_64BIT','UP_REGISTRY_MISSING','UP_QUEUE_INVALID',
        'UP_QUEUE_FOREIGN_PREFIX','UP_GUID_INVALID','UP_STATE_LOCATION',
        'UP_OVERLAP_LOCK','UP_TOOLS_MISSING','UP_SERVICE_STOP_PENDING','UP_ENROLLMENT_AMBIGUOUS',
        'UP_PAIR_TIMEOUT','UP_ASSOCIATIONS_ENUM_FAILED',
        'UP_ASSOCIATIONS_INVALID','UP_NO_AUTHORITATIVE_ASSIGNMENTS','UP_RECORD_OR_NAME_AMBIGUOUS',
        'UP_TARGET_CHANGED','UP_OVERLAP_INSTALLER','UP_DISASSOCIATE_FAILED'
    )
    if ($message -cin $known) { return $message }
    'UP_READ_OR_RUNTIME_ERROR'
}

function Write-UPSummary {
    param([string]$Phase, [int]$Code, [hashtable]$Counts, [string[]]$Reasons)
    $fields = @("UPRepair v1 phase=$Phase code=$Code")
    foreach ($key in @('total','healthy','missing','repaired','deferred','failed','unknown','attempted','associationRemoved','cspErrors','mdmAlerts')) {
        $value = 0
        if ($Counts.ContainsKey($key)) { $value = $Counts[$key] }
        $fields += "$key=$value"
    }
    $codes = @($Reasons | Where-Object { $_ } | Sort-Object -Unique)
    $line = ($fields -join ' ') + ' reasons=' + ($codes -join ',')
    if ($line.Length -gt 2000) { $line = $line.Substring(0, 2000) }
    Write-Output $line
}

function Write-UPProgress {
    param([string]$Message)
    # For a person watching a manual run. When output is redirected, as under Intune, only the summary is emitted.
    if (-not [Console]::IsOutputRedirected) { Write-Host $Message }
}

function New-UPMutex {
    param([string]$Name)
    New-Object Threading.Mutex($false, $Name)
}

function Enter-UPLock {
    param([string]$Sid)
    $mutex = New-UPMutex -Name "Global\UPPrinterRemediation-$Sid"
    $acquired = $false
    try {
        try { $acquired = $mutex.WaitOne(0) }
        catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { throw 'UP_OVERLAP_LOCK' }
        return $mutex
    }
    catch { $mutex.Dispose(); throw }
}

function Exit-UPLock {
    param($Lock)
    try { $Lock.ReleaseMutex() } finally { $Lock.Dispose() }
}

function Test-UPInstallerRunning {
    @(Invoke-UPRead -Body {
        Get-CimInstance -ClassName Win32_Process -Filter "Name = 'UPPrinterInstaller.exe'" -ErrorAction Stop
    }).Count -gt 0
}

function Get-UPTools {
    $installer = Join-Path $env:SystemRoot 'System32\upprinterinstaller.exe'
    $pair = Join-Path $env:SystemRoot 'System32\pairtool.exe'
    if (-not (Test-Path -LiteralPath $installer -ErrorAction Stop) -or
        -not (Test-Path -LiteralPath $pair -ErrorAction Stop)) { throw 'UP_TOOLS_MISSING' }
    $service = Invoke-UPRead -Body {
        $service = Get-Service -Name DeviceAssociationService -ErrorAction Stop
        [pscustomobject]@{ Status = [string]$service.Status }
    }
    if ($service.Status -eq 'StopPending') { throw 'UP_SERVICE_STOP_PENDING' }
    [pscustomobject]@{ Installer = $installer; Pair = $pair }
}

function Get-UPEnrollment {
    if ($OmaDmAccountId) { $null = ConvertTo-UPGuid $OmaDmAccountId; return $OmaDmAccountId }
    $rawIds = @(Invoke-UPRead -Body {
        foreach ($key in @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction Stop)) {
            $p = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
            if ($p.PSObject.Properties['ProviderID'] -and $p.ProviderID -eq 'MS DM Server') {
                $key.PSChildName
            }
        }
    })
    $ids = @(foreach ($id in $rawIds) { $null = ConvertTo-UPGuid $id; $id })
    if ($ids.Count -ne 1) { throw 'UP_ENROLLMENT_AMBIGUOUS' }
    $ids[0]
}

function Invoke-UPPairProcess {
    param([string]$Tool, [string]$Arguments)
    if ((Get-UPRemainingSeconds) -lt 75) { throw 'UP_BUDGET' }
    $root = Get-UPWorkRoot
    $stem = Join-Path $root ('UPPrinterRemediation-pair-' + [guid]::NewGuid().ToString('N'))
    $outFile = $stem + '.out'
    $errFile = $stem + '.err'
    $process = $null
    try {
        $process = Start-Process -FilePath $Tool -ArgumentList $Arguments -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile -ErrorAction Stop
        $null = $process.Handle
        if (-not $process.WaitForExit(60000)) {
            if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction Stop -WhatIf:$false }
            throw 'UP_PAIR_TIMEOUT'
        }
        [pscustomobject]@{ ExitCode = $process.ExitCode; Output = @(Get-Content -LiteralPath $outFile -ErrorAction Stop) }
    }
    finally {
        if ($null -ne $process) { $process.Dispose() }
        foreach ($file in @($outFile, $errFile)) {
            if ([IO.File]::Exists($file)) {
                Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue -WhatIf:$false
            }
        }
    }
}

function Get-UPAssociations {
    param([string]$Tool)
    $listing = Invoke-UPPairProcess -Tool $Tool -Arguments '/enum-endpoints /protocol MCP /persisted /sync /format csv'
    if ($listing.ExitCode -ne 0) { throw 'UP_ASSOCIATIONS_ENUM_FAILED' }
    if ($listing.Output.Count -eq 0) { throw 'UP_ASSOCIATIONS_INVALID' }
    $columns = $listing.Output[0] -split "`t"
    foreach ($required in @('EndpointId','Associated','Associated_PerUser')) {
        if (@($columns | Where-Object { $_ -ceq $required }).Count -ne 1) { throw 'UP_ASSOCIATIONS_INVALID' }
    }
    $idColumn = [array]::IndexOf($columns, 'EndpointId')
    $systemColumn = [array]::IndexOf($columns, 'Associated')
    $userColumn = [array]::IndexOf($columns, 'Associated_PerUser')
    $map = @{}
    foreach ($line in @($listing.Output | Select-Object -Skip 1)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $cells = $line -split "`t"
        # Read the three columns by index, as the header names them; extra cells after them are not an error.
        if ($cells.Count -le [Math]::Max([Math]::Max($idColumn, $systemColumn), $userColumn) -or $cells[$idColumn] -notlike 'MCP#*' -or
            $cells[$systemColumn] -notin 'true','false' -or $cells[$userColumn] -notin 'true','false') {
            throw 'UP_ASSOCIATIONS_INVALID'
        }
        $id = ConvertTo-UPGuid $cells[$idColumn].Substring(4).Trim()
        if ($map.ContainsKey($id)) { throw 'UP_ASSOCIATIONS_INVALID' }
        $map[$id] = [pscustomobject]@{ System = ($cells[$systemColumn] -eq 'true'); PerUser = ($cells[$userColumn] -eq 'true') }
    }
    $map
}

function Invoke-UPInstallerProcess {
    param([string]$Tool, [string]$Arguments)
    if ((Get-UPRemainingSeconds) -lt 330) { throw 'UP_BUDGET' }
    $process = $null
    $stem = Join-Path (Get-UPWorkRoot) ('UPPrinterRemediation-installer-' + [guid]::NewGuid().ToString('N'))
    $outFile = $stem + '.out'
    $errFile = $stem + '.err'
    try {
        $process = Start-Process -FilePath $Tool -ArgumentList $Arguments -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile -ErrorAction Stop
        $null = $process.Handle
        $exited = $false
        # Wait in 30 second slices, 5 minutes in total, so a person watching sees that it is still running.
        for ($slice = 1; $slice -le 10 -and -not $exited; $slice++) {
            $exited = $process.WaitForExit(30000)
            if (-not $exited -and $slice -lt 10) {
                Write-UPProgress "UPRepair: the installer is still running ($($slice * 30) seconds so far). A failing install can take up to 5 minutes."
            }
        }
        $exitCode = $null
        if ($exited) { $exitCode = $process.ExitCode }
        [pscustomobject]@{ Exited = $exited; ExitCode = $exitCode }
    }
    finally {
        if ($null -ne $process) { $process.Dispose() }
        foreach ($file in @($outFile, $errFile)) {
            if ([IO.File]::Exists($file)) {
                Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue -WhatIf:$false
            }
        }
    }
}

function Assert-UPSnapshotKnown {
    param($Snapshot)
    # A record this package cannot evaluate is skipped and reported as unknown; it is never repaired
    # and does not block the others. With no evaluable record there is nothing authoritative to act on.
    if ($Snapshot.Healthy.Count + $Snapshot.Missing.Count -eq 0) { throw 'UP_NO_AUTHORITATIVE_ASSIGNMENTS' }
}

function Get-UPFreshTarget {
    param([string]$Sid, $Target)
    $snapshot = Get-UPSnapshot -Sid $Sid
    Assert-UPSnapshotKnown $snapshot
    $healthy = @($snapshot.Healthy | Where-Object { $_.Id -eq $Target.Id -and $_.Name -ceq $Target.Name })
    if ($healthy.Count -eq 1) { return 'Healthy' }
    $missing = @($snapshot.Missing | Where-Object { $_.Id -eq $Target.Id -and $_.Name -ceq $Target.Name })
    if ($missing.Count -eq 1) { return 'Missing' }
    throw 'UP_TARGET_CHANGED'
}

function Invoke-UPMain {
    $counts = @{ total=0; healthy=0; missing=0; repaired=0; deferred=0; failed=0; unknown=0; attempted=0; associationRemoved=0; cspErrors=0; mdmAlerts=0 }
    $reasons = @()
    $outcomes = @{}
    $lock = $null
    $initial = $null
    $code = 2
    try {
        $context = Get-UPContext
        $initial = Get-UPSnapshot -Sid $context.Sid
        $counts.total = $initial.Total
        $counts.unknown = $initial.Unknown
        $counts.cspErrors = $initial.CspErrors
        $counts.missing = $initial.Missing.Count
        $counts.healthy = $initial.Healthy.Count
        Assert-UPSnapshotKnown $initial
        if ($initial.Unknown -gt 0) { $reasons += 'UP_RECORD_SKIPPED' }
        foreach ($target in $initial.Healthy) { $outcomes[$target.Id] = 'Healthy' }
        foreach ($target in $initial.Missing) { $outcomes[$target.Id] = 'Pending' }
        if ($initial.Missing.Count -eq 0) {
            $code = 0
            $reasons += 'UP_KNOWN_RECORDS_HEALTHY'
        }
        else {
            $lock = Enter-UPLock -Sid $context.Sid
            $underLock = Get-UPSnapshot -Sid $context.Sid
            Assert-UPSnapshotKnown $underLock
            foreach ($target in $initial.Missing) {
                if (@($underLock.Healthy | Where-Object { $_.Id -eq $target.Id -and $_.Name -ceq $target.Name }).Count -eq 1) {
                    $outcomes[$target.Id] = 'Healthy'
                }
                elseif (@($underLock.Missing | Where-Object { $_.Id -eq $target.Id -and $_.Name -ceq $target.Name }).Count -ne 1) {
                    throw 'UP_TARGET_CHANGED'
                }
            }
            if (@($outcomes.Values | Where-Object { $_ -eq 'Pending' }).Count -gt 0) {
                if (Test-UPInstallerRunning) { throw 'UP_OVERLAP_INSTALLER' }
                $tools = Get-UPTools
                $enrollment = Get-UPEnrollment
                $null = ConvertTo-UPGuid $enrollment
                foreach ($target in $initial.Missing) {
                    if ($outcomes[$target.Id] -ne 'Pending') { continue }
                    if ((Get-UPRemainingSeconds) -lt 720) { $reasons += 'UP_BUDGET'; break }
                    try {
                        if ((Get-UPFreshTarget -Sid $context.Sid -Target $target) -eq 'Healthy') {
                            $outcomes[$target.Id] = 'Healthy'
                            continue
                        }
                        if (Test-UPInstallerRunning) { $reasons += 'UP_OVERLAP_INSTALLER'; break }
                        if (-not $script:UPCmdlet.ShouldProcess('current-user recorded target',
                            'Remove only its stale per-user association if present, and install')) {
                            $outcomes[$target.Id] = 'Deferred'
                            $reasons += 'UP_PREVIEW_OR_DECLINED'
                            continue
                        }
                        $associations = Get-UPAssociations -Tool $tools.Pair
                        if ($associations.ContainsKey($target.Id) -and $associations[$target.Id].System) {
                            $outcomes[$target.Id] = 'Deferred'
                            $reasons += 'UP_SYSTEM_ASSOCIATION'
                            continue
                        }
                        $stale = $associations.ContainsKey($target.Id) -and $associations[$target.Id].PerUser
                        # Confirmation may take time; recheck after approval and immediately before mutation.
                        if ((Get-UPFreshTarget -Sid $context.Sid -Target $target) -eq 'Healthy') {
                            $outcomes[$target.Id] = 'Healthy'
                            continue
                        }
                        if ((Get-UPRemainingSeconds) -lt 630) { $reasons += 'UP_BUDGET'; break }
                        if (Test-UPInstallerRunning) { $reasons += 'UP_OVERLAP_INSTALLER'; break }
                        $nativeId = $target.RawId
                        $id = ConvertTo-UPGuid $nativeId
                        $counts.attempted++
                        if ($stale) {
                            $disassociate = Invoke-UPPairProcess -Tool $tools.Pair -Arguments "/disassociate MCP#$nativeId"
                            if ($disassociate.ExitCode -ne 0) { throw 'UP_DISASSOCIATE_FAILED' }
                            $counts.associationRemoved++
                        }
                        if ((Get-UPFreshTarget -Sid $context.Sid -Target $target) -eq 'Healthy') {
                            $outcomes[$id] = 'Healthy'
                            continue
                        }
                        if (Test-UPInstallerRunning) {
                            $outcomes[$id] = 'Deferred'; $reasons += 'UP_OVERLAP_INSTALLER'; break
                        }
                        $arguments = "-install -printersharedid $nativeId -usersid $($context.Sid) -omadmaccountid $enrollment -correlationid $([guid]::NewGuid().ToString('B'))"
                        $install = Invoke-UPInstallerProcess -Tool $tools.Installer -Arguments $arguments
                        if (-not $install.Exited) {
                            $outcomes[$id] = 'Running'
                            $reasons += 'UP_INSTALLER_TIMEOUT_RUNNING'
                            break
                        }
                        if ($install.ExitCode -ne 0) { $counts.mdmAlerts++ }
                        if ((Get-UPFreshTarget -Sid $context.Sid -Target $target) -eq 'Healthy') {
                            $outcomes[$id] = 'Repaired'
                        }
                        else { $outcomes[$id] = 'Failed'; $reasons += 'UP_VERIFY_FAILED' }
                    }
                    catch {
                        $outcomes[$target.Id] = 'Failed'
                        $reasons += Get-UPReason $_
                        # Unexpected command/state failures stop this run rather than broadening its mutations.
                        break
                    }
                }
            }
            foreach ($id in @($outcomes.Keys)) {
                if ($outcomes[$id] -eq 'Pending') { $outcomes[$id] = 'Deferred' }
            }
            $final = Get-UPSnapshot -Sid $context.Sid
            $counts.cspErrors = $final.CspErrors
            $counts.unknown = $final.Unknown
            Assert-UPSnapshotKnown $final
            foreach ($target in @($initial.Healthy) + @($initial.Missing)) {
                $verified = @($final.Healthy | Where-Object { $_.Id -eq $target.Id -and $_.Name -ceq $target.Name })
                if ($verified.Count -ne 1 -and $outcomes[$target.Id] -in 'Healthy','Repaired') {
                    $outcomes[$target.Id] = 'Failed'
                    $reasons += 'UP_FINAL_VERIFY_FAILED'
                }
                elseif ($verified.Count -eq 1 -and $outcomes[$target.Id] -eq 'Deferred') {
                    $outcomes[$target.Id] = 'Healthy'
                }
            }
            $unresolved = @($outcomes.Values | Where-Object { $_ -notin 'Healthy','Repaired' })
            if ($unresolved.Count -eq 0 -and $final.Missing.Count -eq 0 -and $final.Total -eq $initial.Total) { $code = 0 }
            elseif (@($outcomes.Values | Where-Object { $_ -eq 'Failed' }).Count -gt 0) { $code = 2 }
            else { $code = 3 }
            if ($final.Total -ne $initial.Total -or $final.Missing.Count -gt $unresolved.Count) {
                $code = 2; $reasons += 'UP_ASSIGNMENTS_CHANGED'
            }
        }
    }
    catch {
        $reason = Get-UPReason $_
        if ($reason -in 'UP_OVERLAP_LOCK','UP_OVERLAP_INSTALLER') { $code = 3 }
        else { $code = 2; $counts.failed++ }
        $reasons += $reason
        foreach ($id in @($outcomes.Keys)) {
            if ($outcomes[$id] -eq 'Pending') { $outcomes[$id] = 'Deferred' }
        }
    }
    finally {
        if ($null -ne $lock) {
            try { Exit-UPLock $lock }
            catch { $code = 2; $counts.failed++; $reasons += 'UP_LOCK_RELEASE_FAILED' }
        }
    }
    if ($outcomes.Count -gt 0) {
        $counts.healthy = @($outcomes.Values | Where-Object { $_ -eq 'Healthy' }).Count
        $counts.repaired = @($outcomes.Values | Where-Object { $_ -eq 'Repaired' }).Count
        $counts.deferred = @($outcomes.Values | Where-Object { $_ -in 'Pending','Deferred','Running' }).Count
        $counts.failed += @($outcomes.Values | Where-Object { $_ -eq 'Failed' }).Count
    }
    Write-UPSummary -Phase remediate -Code $code -Counts $counts -Reasons $reasons
    return $code
}

# Entrypoint: keep the emitted summary separate from the process exit code.
$result = @(Invoke-UPMain)
$result | Select-Object -SkipLast 1 | Write-Output
exit ([int]$result[-1])

# SIG # Begin signature block
# MIInOgYJKoZIhvcNAQcCoIInKzCCJycCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC4KI6sBdnUheBU
# KHeKzrl62g2WWdZTIygpezDG6MM9iaCCDMkwggYEMIID7KADAgECAhMzAAACHPrN
# xZvoL37EAAAAAAIcMA0GCSqGSIb3DQEBCwUAMFcxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBD
# b2RlIFNpZ25pbmcgUENBIDIwMjQwHhcNMjYwNDE2MTg1OTQxWhcNMjcwNDE1MTg1
# OTQxWjB0MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYD
# VQQDExVNaWNyb3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IB
# DwAwggEKAoIBAQDVsZfgOKmM31HPfoWOoNEiw0SlCiIxUMC0I9NMWbucKOw/e9lP
# oAoehQVu6SG65V4EPzrYsnBnFPNoi4/HoOdjhz1qkrEt4I6tEcxXU6oOeY9zGveC
# /3iBeuhLYxM3M/PkcUoebF+Nednm8OkdSPoDu8imViHPQq/8CQUu0WRR4rE+dMRf
# rpVqfmNi2qWCX94T4MsepijGVkwE//tJg0ryAiYdHT34LSnlG/RSBZmQRGWZ5g8j
# qnKjRParSqMft1gvjuUTVgtWNZfgcLFSK5Wa0myrq8OPcgTGGsRgun+tnSS+IxDT
# xVsAPH1OzvPjwomguByhUe/OcvUN0D5Wmp7xAgMBAAGjggGqMIIBpjAOBgNVHQ8B
# Af8EBAMCB4AwHwYDVR0lBBgwFgYKKwYBBAGCN0wIAQYIKwYBBQUHAwMwHQYDVR0O
# BBYEFNoH7a2YDjOSwpkp6DHcmUS7J+0yMFQGA1UdEQRNMEukSTBHMS0wKwYDVQQL
# EyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxFjAUBgNVBAUT
# DTIzMDAxMis1MDc1NjkwHwYDVR0jBBgwFoAUf1k/VCHarU/vBeXmo9ctBpQSCDEw
# YAYDVR0fBFkwVzBVoFOgUYZPaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
# cy9jcmwvTWljcm9zb2Z0JTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDI0LmNy
# bDBtBggrBgEFBQcBAQRhMF8wXQYIKwYBBQUHMAKGUWh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwQ29kZSUyMFNpZ25pbmcl
# MjBQQ0ElMjAyMDI0LmNydDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEBCwUAA4IC
# AQAUnEqhaRXe0T3hIJjvdQErEkrA/7bByjn6t5IArODkkRjzkYwtKMc2yYj2quaN
# rLutWw2YZcngKPy1b71YyDJQTy4NDRwaSh9Tw5thrk3NmcPrAHia5vtcBJ1CgtKK
# 7mQbIcQ22d/N3813ayCDDFewu1+jsZmX+r/aTEqaOM4TVxVtRSkuCy8nAXKuChOK
# Li/zA4XuH8iEYqIsj2YoNaeSxVmeGiERXpKdo3dDmYi0kO5w2D8VS4c3+9h6gElY
# BaAAg/dYErBg27qT3vv0zRDJhJufvCNylA8S7/+8H5E/PV5cng6na9VV/w9OV3qu
# uND6zdGa2EX38Glp50F9AIQk3p2xXmcvorDeM4XJ7UlWYBi6g80J1SSOQnInCYFE
# msfUNn3+1AaTJKSJL83quKArTac2pKhu0Yzzzrzo6HrsRiQKzpnRBb1/dMa6P3hz
# 75XbMRBctNsFhZC07WCmjExdLg2eHW5uV0TY8D5+6wozJf7vF3+WHkYPO85Z+BC6
# U4FkNbYNycZ9cE4j1tXRdyDCfml6c0HWPHjNVDObrv9lKt3qUqFpX38VCqVCyNOO
# 1UcXfQiVjJw32U2WUKZjt/neJKHEBsm9kFsLuWzkQ53+qcaSaytmsCnk2gOglrlD
# 5d3kKyvvAw+rzm0lT8K38P6PLxfZQHhu4W8dV7Av8N2ZmDCCBr0wggSloAMCAQIC
# EzMAAAA5O7Y3Gb8GHWcAAAAAADkwDQYJKoZIhvcNAQEMBQAwgYgxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBS
# b290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDExMB4XDTI0MDgwODIwNTQxOFoX
# DTM2MDMyMjIyMTMwNFowVzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQ
# Q0EgMjAyNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANgBnB7jOMeq
# lRYHNa265v4IY9fH8TKhemHfPINe1gpLaV3dhg324WwH06LcHbpnsBukCDNitryo
# 0dtS/EW6I/yEL/bLSY8hKpbfQuWusBPr9qazYcDxCW/qnjb5JsI1s8bNOg3bVATv
# QVL4tcf03aTycsz8QeCdM0l/yHRObJ9QqazM1r6VPEOJ7LL+uEEb73w6QCuhs89a
# 1uv1zerOYMnsneRRwCbpyW11IcggU0cRKDDq1pjVJzIbIF6+oiXXbReOsgeI8zu1
# FyQfK0fVkaya8SmVHQ/tOf23mZ4W9k0Ri22QW9p3UgSC5OUDktKxxcCmGL6tXLfO
# GSWHIIV4YrTJTT6PNty5REojHJuZHArkF9VnHTERWoTjAzfI3kP+5b4alUdhgAZ7
# ttOu1bVnXfHaqPYl2rPs20ji03LOVWsh/radgE17es5hL+t6lV0eVHrVhsssROWJ
# uz2MXMCt7iw7lFPG9LXKGjsmonn2gotGdHIuEg5JnJMJVmixd5LRlkmgYRZKzhxS
# CwyoGIq0PhaA7Y+VPct5pCHkijcIIDm0nlkK+0KyepolcqGm0T/GYQRMhHJlGOOm
# VQop36wUVUYklUy++vDWeEgEo4s7hxN6mIbf2MSIQ/iIfMZgJxC69oukMUXCrOC3
# SkE/xIkgpfl22MM1itkZ35nNXkMolU1lAgMBAAGjggFOMIIBSjAOBgNVHQ8BAf8E
# BAMCAYYwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFH9ZP1Qh2q1P7wXl5qPX
# LQaUEggxMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMA8GA1UdEwEB/wQFMAMB
# Af8wHwYDVR0jBBgwFoAUci06AjGQQ7kUBU7h6qfHMdEjiTQwWgYDVR0fBFMwUTBP
# oE2gS4ZJaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMv
# TWljUm9vQ2VyQXV0MjAxMV8yMDExXzAzXzIyLmNybDBeBggrBgEFBQcBAQRSMFAw
# TgYIKwYBBQUHMAKGQmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMv
# TWljUm9vQ2VyQXV0MjAxMV8yMDExXzAzXzIyLmNydDANBgkqhkiG9w0BAQwFAAOC
# AgEAFJQfOChP7onn6fLIMKrSlN1WYKwDFgAddymOUO3FrM8d7B/W/iQ6DxXsDn7D
# 5W4wMwYeLystcEqfkjz4NURRgazyMu5yRzQh4LqjA4tStTcJh1opExo7nn5PuPBY
# nbu0+THSuVHTe0VTTPVhily/piFrDo3axQ9P4C+Ol5yet+2gTfekICS5xS+cYfSI
# vgn0JksVBVMYVI5QFu/qhnLhsEFEUzG8fvv0hjgkO+lkpV9ty6GkN4vdnd7ya6Q6
# aR9y34aiM1qmxaxBi6OUnyNl6fkuun/diTFnYDLTppOkr/mg5WSfCiDVMNCxtj4w
# PKC5OmHm1DQIt/MNokbbH3UGsFP1QbzsLocuSqLCvH09Io3fDPTmscR9Y75G4qX7
# RTX8AdBPo0I6OEojf39zuFZt0qOHm65YWQE69cZM2ueE1MB05dNNgHK9gTE7zKvK
# /fg8B2qjW88MT/WF5V5uvZGtqa9FSL2RazArA+rDPuf6JGYz4HpgMZHB4S6szWSK
# YBv0VisCzfxgeU+dquXW9bd0auYlOB58DPcOYKdc3Se94g+xL4pcEhbB54JOgAkw
# YTu/9dLeH2pDqeJZAABVDWRQCaXfO5LgyKwKCLYXpigrZYCjUSBcr+Ve8PFWMhVT
# Ql0v4q8J/AUmQN5W4n101cY2L4A7GTQG1h32HHAvfQESWP0xghnHMIIZwwIBATBu
# MFcxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# KDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIc
# +s3Fm+gvfsQAAAAAAhwwDQYJYIZIAWUDBAIBBQCggZAwGQYJKoZIhvcNAQkDMQwG
# CisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIEIAIO+DWXacJ4T+L24fVEFHtFipf0
# +baNK2Q4Pc0dbPZoMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBv
# AGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAE
# ggEAgtwvhot962YmakXrLht9jRpmG8Wx7GVgckqSdxAK2F12PM+sxlGnljCEwTLJ
# 5qrzmGp/WpN0/sh6YJonRH5AkOLL4lsZs34qrC0AG3gC8JYr73wgQt2EDnBEeSWE
# zkpimi+O6kA65v1eLLbOZrSiabnsvHGVy88M+VmXh69fHrMUbYJ/WT6tp22fm2tE
# qBrQcxduqTeW0oZvQCq+uDvhUUoPUi/BCkNZXfBTp6/mZuHjnUMsozW4TOO4VMKJ
# 7kXPXhOwU4FXcelcYbWE9KYH3bfLzSxyguEvbglkrtijAKBMXDCF6mZI7J/BcjLF
# IcgbDAjDNH1n5dISHShAxPbrxqGCF5cwgheTBgorBgEEAYI3AwMBMYIXgzCCF38G
# CSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG
# 9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQC
# AQUABCBPQwcmuW6lAdDT4eqI/W7J06MilMKdM9DRRggwOdgXKQIGaqpvlL5yGBMy
# MDI2MTEwNjAzMjgyNy4wNDdaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmlj
# YSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046OTYwMC0wNUUw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHt
# MIIHIDCCBQigAwIBAgITMwAAAiY1tD5nQ5P2HwABAAACJjANBgkqhkiG9w0BAQsF
# ADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
# Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNjAyMTkxOTQwMDJa
# Fw0yNzA1MTcxOTQwMDJaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScw
# JQYDVQQLEx5uU2hpZWxkIFRTUyBFU046OTYwMC0wNUUwLUQ5NDcxJTAjBgNVBAMT
# HE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQC//w+ZZIL5RFFpVI8D3ZyuNu8IzcAEOD30OLYjh337rXjc
# rIlOSzpJc4ZeUxEyli6x6F6zm4NR8dbPb9diDp/hOUzHWGxiA1Z3RXKBb/4F/ojy
# vN43SEGWqSfVc3I3BlsYT35ecVAJ9kVf90YOv29tFjJBBZkYvrT/DwwyRLscOyP4
# p+9/lyJjD+ULs3YXBhVrfZ+MbQB+BYKLqRvBKbj/wR9akNrMxQINoGaD5jZO/N/n
# SsmG2P1zv/cv4gSoMBnWeQIBkjd2I5w1DeXupp2vSiNmR5sA2ZkBK3yiQWaJvRxO
# DlkfiyHk9Mkk/TrYTjmjPCbhe+uqhHNRy8UlbOvWsCq0tRtUykHv39DgqAfJNrE8
# OSt835rBzDprrcAhwmgfhoVi4AKeqwikY0nUa48K0Qy80XT4fiEA3ExEZNaRFo9N
# q/GwbfgqKqGmc9xhKuRFcjtua4KHZvnAvpWgEFSOCkovXs/BcLnkEHM9xZ8iUag5
# CyhNqXYYE/z0pcXdYaNIkQ68EWmuvLm7g9oofV2vOm5GVNoghnkWG6nGPo/JwEgm
# A9oSS0EfvFRMWPA/gpSvF3shArKHnaEpVSSi3DNbyiuYiEs9Ko0IkZc8xKFeQRaq
# GRxrB+2r/7B3X81Tps99KhFwg+wD87od22F2MUg1x7twt3gaVnFk0IZIwUPCGwID
# AQABo4IBSTCCAUUwHQYDVR0OBBYEFF3hn9fYJN2Y/Z9LVbBPIxAzXHsQMB8GA1Ud
# IwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRp
# bWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYI
# KwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMv
# TWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1Ud
# EwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeA
# MA0GCSqGSIb3DQEBCwUAA4ICAQA2Ux0tr9sYCjsq0FRyiVpx15OurNXv6Qk7iX+A
# rVPlz3w4tqjcTNm1dt3tTua2wJMpJhPH8n7UXhmT98d5Du44Ll4adnse4SQfVg3Q
# L6aRkXHnJUn8y9iftB/Py22n9xnwPFfj3QlDOSgLuHleu97U0iH2ZaluYabWXJih
# diYpK8cPHFlqZOAiot0+GD8dP+RMuvpxt/F2LmYelpoZwriiFOUmlxEUV7xJHyZZ
# lDquskeyuq01DTv91N4qM8cfPPhl/2pc4HeMf/nd2HouifJbDQFNd4WPhLzn0Sy3
# u1Zh3+S3tjQdqN+dyw60RaV+RXCoOLgFZ3MAg/GoDl+fvb5hy/1a71ctX8wEad1P
# f6def2pqfl3wFc++hkF8DXXTZofJN4YVaN3InwbAGQDDkNK4lqecCixxmSKwidPy
# nGeE5OtvNoK1pkLsm/i8F1RjGczZ/kSF2VDkqG866iQ+jVbGOQ6Du3eyyFcFKZoD
# J4B5mEAS9aT2SKqllLeybOboH6r67siR5B/2Hnu7+KYuYZy0BEadtA6ngG4cnSR9
# JsrkhhsKmb11ujqwgJyNx92MsoGGwNgN1aI0QID8CsjCFwpfmMzlA44xHKYv3hmj
# xeqBS4uU5rQeiAnVgpJeaVGKm/lzPDtnppGV+7XhRp5b1ZxT/Z7Xxc+I7H7/jCtQ
# DZoaZTCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcN
# AQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAw
# BgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEw
# MB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk
# 4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9c
# T8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWG
# UNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6Gnsz
# rYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2
# LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLV
# wIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTd
# EonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0
# gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFph
# AXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJ
# YfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXb
# GjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJ
# KwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnP
# EP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMw
# UQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggr
# BgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYw
# DwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoY
# xDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtp
# L2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYB
# BQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20v
# cGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0B
# AQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U5
# 18JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgAD
# sAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo
# 32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZ
# iefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZK
# PmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RI
# LLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgk
# ujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9
# af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzba
# ukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/
# OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNQMIIC
# OAIBATCB+aGB0aSBzjCByzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEnMCUG
# A1UECxMeblNoaWVsZCBUU1MgRVNOOjk2MDAtMDVFMC1EOTQ3MSUwIwYDVQQDExxN
# aWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQCi/fMx
# Ftkqr7XMXdsRyWU0lSKHZ6CBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7pd4hjAiGA8yMDI2MTEwNTIxNDk1OFoY
# DzIwMjYxMTA2MjE0OTU4WjB3MD0GCisGAQQBhFkKBAExLzAtMAoCBQDul3iGAgEA
# MAoCAQACAg9BAgH/MAcCAQACAhKGMAoCBQDumMoGAgEAMDYGCisGAQQBhFkKBAIx
# KDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZI
# hvcNAQELBQADggEBAMW/0d+fg6DlxIlKzXgAMB7+y06aCtHWm6+YzPO8fvxH4MLu
# aLGw2pz/+mhZAbmTSJMnimx0Pb+MWEsiLXW3RJsydCZtlQtwS/CuGefkh3RxvVdi
# zxmOzGxzU40T1rq8ac9TvPF7ACCrurl6DAvSa7uIrLGiZGfp49+T6nL/JjXXgl6r
# H55Dcr9lyfga+i8C0iNVESEw1a4q+YxWzrnUBKMNqyyj/JsTt9T1nDjRV2hrRqLz
# xVyP/5k81F2A95Y9ZzlmNn6lhLqXGUPIHl66Hvj1x3kvHea+Ol/QPmffrB0ChGU9
# QHDsbprihl84OjpUiA9cbeVKCFoEkJS7vlkgpbsxggQNMIIECQIBATCBkzB8MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNy
# b3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAiY1tD5nQ5P2HwABAAACJjAN
# BglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8G
# CSqGSIb3DQEJBDEiBCBMwQRmcgCZEzgACsdi95cwRVlUfefGDwFk++veKyCchDCB
# +gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIMwyXGFnTNsZRBrs6GN/BbV0okaN
# P3VBYqLFjUsFnbgqMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIw
# MTACEzMAAAImNbQ+Z0OT9h8AAQAAAiYwIgQg5uCw81wtxxiMbY1GV49E6uCTmn6v
# Bu5gBlaLh+MeLDQwDQYJKoZIhvcNAQELBQAEggIAIxa/DCd5Yar9ZiGBjpr8z+wQ
# wKAdzDC/lC/q15wYsN3sCHFKavRbx2GpbadzHlt49LzCKES/1AHzwOls74Z8FLKr
# gsUEW3rGF6nX4KFs3I1vopLwf/Bao6FMagmtQ9Q3icn5GmCCnqJVcKiLVbLF69ym
# PBLafdUBQ41blDfvVE9z6RdOpRRRd/2nS45ZGtqBAtlVMAjcihq8oNKBbYx2rC1i
# ffClgnTwqHvowgNrZTrH8hmcxGliS6x1dRZD4MZ/7GrOC+P99sZUbfW2lcfzTWre
# 8+/8Lmcause54h0SyhdLKiDustzerHr5LZnb94PaYiYEkUAmgxMC9x3LyN3M+gk9
# 85Jb+cHyKlrY4DfKiUOeepwjxPxIKb8M2lkAS9ntNMLNTnRtuTkcK5bJj0ycNKh5
# ZkziCV/OCm/foTlFPs7hxxb59HUhZqNdIuqe+CUtPDy8t6a/UhHV0CY6v94QSkiZ
# ryb2/WK7h3NHAIgEQOiS/VylJk40NmdyTqxy3ZzCjQLCMAT1XuBDJr6kcyozmani
# ioiPwPyb+E+d+IXS4AODjgbS/o9gBPBXTirU3+x/gnaUASxCKHMCxe8YydlpBvI5
# c3/V9WMzmol4LaKSvVwYj4vxKYDIbWD4CTGCRhQ81oaXU0P5Kq7QfLF+5Fokd6yM
# OtLP4mENBIAdR1pd1SA=
# SIG # End signature block
