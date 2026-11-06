#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$script:UPRegistryPath = 'HKCU:\Software\Microsoft\PrinterProvisioning\UPPrinterInstalls'
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

function Invoke-UPMain {
    $counts = @{ total=0; healthy=0; missing=0; unknown=0; deferred=0; failed=0; cspErrors=0 }
    $reasons = @()
    $code = 2
    try {
        $context = Get-UPContext
        $snapshot = Get-UPSnapshot -Sid $context.Sid
        $counts.total = $snapshot.Total
        $counts.healthy = $snapshot.Healthy.Count
        $counts.missing = $snapshot.Missing.Count
        $counts.unknown = $snapshot.Unknown
        $counts.cspErrors = $snapshot.CspErrors
        if ($snapshot.Total -eq 0) { $reasons += 'UP_NO_AUTHORITATIVE_ASSIGNMENTS'; $counts.unknown = 1 }
        elseif ($snapshot.Healthy.Count + $snapshot.Missing.Count -eq 0) {
            # Every record is one this package cannot evaluate, so nothing is known about the device.
            $reasons += 'UP_NO_AUTHORITATIVE_ASSIGNMENTS'
            $reasons += 'UP_RECORD_SKIPPED'
        }
        else {
            # A record with no name, a status other than 1 or 4, or an ambiguous name is skipped and
            # reported as unknown. It never blocks the evaluable records.
            if ($snapshot.Unknown -gt 0) { $reasons += 'UP_RECORD_SKIPPED' }
            if ($snapshot.Missing.Count -eq 0) { $code = 0; $reasons += 'UP_KNOWN_RECORDS_HEALTHY' }
            else { $code = 1; $reasons += 'UP_MISSING_CANDIDATES' }
        }
    }
    catch {
        $counts.failed++
        $reasons += Get-UPReason $_
    }
    Write-UPSummary -Phase detect -Code $code -Counts $counts -Reasons $reasons
    return $code
}

# Entrypoint: keep the emitted summary separate from the process exit code.
$result = @(Invoke-UPMain)
$result | Select-Object -SkipLast 1 | Write-Output
exit ([int]$result[-1])

# SIG # Begin signature block
# MIInNwYJKoZIhvcNAQcCoIInKDCCJyQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBUPw8GyxufiBwj
# 3r2T0+LSPIqUiElvf4LNjKpfjjQnXKCCDMkwggYEMIID7KADAgECAhMzAAACHPrN
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
# Ql0v4q8J/AUmQN5W4n101cY2L4A7GTQG1h32HHAvfQESWP0xghnEMIIZwAIBATBu
# MFcxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# KDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIc
# +s3Fm+gvfsQAAAAAAhwwDQYJYIZIAWUDBAIBBQCggZAwGQYJKoZIhvcNAQkDMQwG
# CisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIEIGdeHcadN/+oacSNlbUdcfJ8tQZx
# rwoyGoCcTO0wEH8qMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBv
# AGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAE
# ggEATn01aIPwc1lm1xEi3EV+5q9tOZYHKJpNeyxm1FK+hsX7yZ0VzoAMZnFqUwyU
# FyWrooYzSsDC/oTwjVop+kJO3Q/jSQyoJxlJU5ZHsilxP184coF1gfQsPf7cNG9B
# 4y5Qhh3PwVf4gJ6lXGip6XC9WdhQD8L5ZxItTb9wYw5P6ztthBp08BTutBcOTM7+
# OdIJR8roKM/4Ohbhsv01VG25gAmiXYr1625dSkMGX69oOOfOuofe19N7s4QcDTFQ
# AZGSZ52zdOIYWZLSN/gddEsyyO+iL69zafX6VIeh+zHbzG+vNqcvJWAi8AL/W9n9
# l5pnwvUIW80ZrBiomi2/3I2pyqGCF5QwgheQBgorBgEEAYI3AwMBMYIXgDCCF3wG
# CSqGSIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG
# 9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQC
# AQUABCDsyYVVOKZ8VsG7pon7Pm+3lmZ0iUqi/wNyzVrQa2MHvgIGatlNAWvRGBMy
# MDI2MTEwNjAzMjgxNy40MjhaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmlj
# YSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046ODYwMy0wNUUw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHq
# MIIHIDCCBQigAwIBAgITMwAAAiWAxzfGzap3SQABAAACJTANBgkqhkiG9w0BAQsF
# ADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
# Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNjAyMTkxOTQwMDFa
# Fw0yNzA1MTcxOTQwMDFaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScw
# JQYDVQQLEx5uU2hpZWxkIFRTUyBFU046ODYwMy0wNUUwLUQ5NDcxJTAjBgNVBAMT
# HE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQCm8RIP0eLA46VcCPovvmqsIlN6qkmz5IsHWmUU0neUqp8u
# Gxadeo+SwWBCwQ5alZI/DNdpXfyiZLZR6XYgpRPFzepIl7OCDb4NtEskJCIZDkQM
# NwrH9YwUyu71GGigsLIxeleHtA3utoVTeHjS1b8UnwORRtknKkyrUArT6ZpB2rod
# IcmcLcv3x3wwgYlOs0FEg5EsVrZb7LNc/nd0bXDp+HTOWWui8eoTVwJeLxcVP869
# oF8li5SU81aa2tGJ6/Jsejiz9JMW8SJXKBT2DCXMOUkCsGjonPZRqfvoMSIQZgta
# OTyAJlrvsy0TZ78XrGqoygtQimQnbOAL4KNLSCuW5TZEQGTHLOQJGgggb3j5gKC7
# 78+RIPJA+n/hmHJ/x4qT/HTTPoVeMCcuBKWrQXR1+/pYau3Fwe0tWIyG+LWzkRr/
# ZNPPupcA2Yci3qn8HR9RwvQopqSNJwn2Ri6am8AQyfVVy/BBw0t6jpoRPjwKvuUj
# fCzpae6duOxQtQ1XDN9PA2yl9sDko/+AXV/SOe8ea8QoQcv3s3ErkG+Lp6hnvw6O
# MPian4ggNkRtgtB7ro1OiopOUXJn9Y5EO3JUAXNcuM9m+5My1VEuvGytgAH3uxms
# lTnW3YbrfazaySCSSnWkhaOZ33hgbuUQfH7n2NFEAUc/cFzfmCQUikWisnJYywID
# AQABo4IBSTCCAUUwHQYDVR0OBBYEFLE40qoXTuMHX3AfZUu1n8nx2h93MB8GA1Ud
# IwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRp
# bWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYI
# KwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMv
# TWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1Ud
# EwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeA
# MA0GCSqGSIb3DQEBCwUAA4ICAQAHnfc2yUyoHZbvvyVKFuXh5HxxHIvIaR9JWpIf
# ITJlc/Ki03juR+vckzq3tp5fFH5LL7eIFXRIuoewMsvWeFrWufrrW4HhmhCwkqAr
# fA1C0xk+HaYs2O48YSxMX9lgS1kTTIb3YsfoFdFpKurPf2nc2Yd4wLg+Fgwmkxke
# yE3MUKVna8SZeVpEjnS5ucFck4srPwK2ORAf70I23GGyPhqgIKZphNXhSscTAQsy
# IqB5GwDMdRV5LK37NfU4YmxvCYh3TFYE/Gh01Q6yJvf9HxiEZpwW+oUk0gruHobg
# 3sgIR5rfgUo8l30vUnaDYMcPAClaFMC/QbHZSaUhWXZG1OOcMp0g9vYQNLDEqFX2
# jlquvzVSSwtHtm1KTldCjRED+kdCybcPxbPalwJigXc1BsI9CitnTf0ljwb9NkZ/
# JVI8/D62rXXzhz4F3u0iVGzwncGaxRxHG/Xv4nTrpkOeepoYbNBbMWS2G1qP3Xj7
# pVf0+4qRyAqJ0stjQjoVOJImVPWRjz5PR3Dn6adQVMBJDM6gDrj1rZTFVgCtTijq
# GZSGzvXpGkF3vYsyE6ZDma/kGdiUe5saeI6lH66PiWWXgqxt7sy2Ezv0yIjSVv+e
# MOT2QMUiZ6WCc7gVtAmXpfeIus+NmgFvM+Ic1X58e4I9EL4ZSAidSpWW0GZTLNC0
# 2mryLjCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcN
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
# OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNNMIIC
# NQIBATCB+aGB0aSBzjCByzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEnMCUG
# A1UECxMeblNoaWVsZCBUU1MgRVNOOjg2MDMtMDVFMC1EOTQ3MSUwIwYDVQQDExxN
# aWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQBTb+bK
# OPAjCBflhzw5EXBuSWxeDqCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7peQeDAiGA8yMDI2MTEwNTIzMzIwOFoY
# DzIwMjYxMTA2MjMzMjA4WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDul5B4AgEA
# MAcCAQACAio1MAcCAQACAhMwMAoCBQDumOH4AgEAMDYGCisGAQQBhFkKBAIxKDAm
# MAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcN
# AQELBQADggEBAMiob/v5+CV0RHFkAj4O/RMgtSeBDx3BI2x2k5g+Rn4SB2Z+rkp+
# 0rA5Wpg5ozRjE27nzbLIqsoYEA1MfguOn7so4AVeqJMdK7O9g1UyRIDYbqWAOOWy
# UFEgQ1uWSovztrLPZbDTTNMfHj8jsUYf9o+h8iORI/Q5xbxSOjYkJp0v2JU1/i71
# /gcPktdWCc/PupKrhZtTdRo9JhusDtsPKEOO80s9FrTzIOyDpZxJw0aHyCzn22yl
# A9nfOqlB+Y9XMAIcVBMzhpYidgST4b6mzpfz4msS6UBzx4AB1w8iLiP+SQGQB5Eq
# CaQAkSnBSbwknm+X9vnppV/DdFUjsX4WsWAxggQNMIIECQIBATCBkzB8MQswCQYD
# VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3Nv
# ZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAiWAxzfGzap3SQABAAACJTANBglg
# hkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqG
# SIb3DQEJBDEiBCAZoqnsUc6+36NR51+I5tUgeKfZ/mLtT3fXb3VIN4v0KDCB+gYL
# KoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIFYN7oh6ON3y92CmAl/lF0CYwrjWWQP6
# dCUxajPSHKEQMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAC
# EzMAAAIlgMc3xs2qd0kAAQAAAiUwIgQgb8gJtDIyTIwcZ35qRaOo7jg5n6qemnr8
# 7iHxAMFXlW4wDQYJKoZIhvcNAQELBQAEggIAlnyUKNQsWb/VkdlcwfjjI2EH2qyL
# 54aPoq1aG8WhTQ4ZR0XVZYY9f3gATP1K2WOv/P+nLzi81PVeYacjsHtdcQWpOMmo
# J3jvryScI0SdVamrDBAMmdEVkbNsOTUQj5K0LssRo6FgYPD704x00Uea7Hm8bhdG
# boSEPvGBKdsr84iG3iyDkbWfEnreGd114ylSZwdR0d8ohXRuI+U2wEBAxP2eUJb3
# bEWv0kZaH5H/QbMr1Ig0wdvcu32N3ofiEIEP/jIG51/E49t1GF/OKxgSQ6lR9zYu
# LJF3TNJZRcJRZVO47OJNSeN8J6QOvQcsugml6dj0mRZc8bOTI+emxJAKY4TmfDVR
# MwDboR0ujMaE67bKzA0YK52AvnB1keG4uwBRy1HG7GugJ57llz7b3q6dsxtwYceK
# yK5rVirzq6kdX93saCmtmyub3vTvb5FcxgzbnZP7mRSn0lPGsTQ5Bvj7/8q08IvV
# 9mkvgcyRdDf//X6u/0RWOdcpuDFZcjZcsIV1E76v4wksanuADBo1DLEgbdLyKfg0
# GhvMS+eCJcaOV/OKsbzdxJjGonevtQ1kgG7o85CZ3Q3iVqPBa6sFhnKfSeKvqNRg
# 9o4R/uDl1kshzdwzhMiCjw2rMI4ueeEQeDw/X/HTO9pZP6yrzMH61iCWCE+/dIDn
# 9blQ4ZHO5JRTHjc=
# SIG # End signature block
