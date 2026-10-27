# Convert per-system Universal Print printers to per-user installs

`Convert-UpPrinterToPerUser.ps1` migrates legacy per-system Universal Print DAF
entries to per-user entries. Run conversion as **NT AUTHORITY\SYSTEM** using
Windows PowerShell 5.1 or PowerShell 7 on Windows. Detection does not require
elevation:

```powershell
.\Convert-UpPrinterToPerUser.ps1 -Detect

.\Convert-UpPrinterToPerUser.ps1 -ShareId '<share-guid>' -TenantId '<tenant-guid>'
.\Convert-UpPrinterToPerUser.ps1 -AllUPPrinters -TenantId '<tenant-guid>'
```

`-UserSIDs`, `-SkipDisassociate`, `-SkipRestart`, and `-WhatIfMode` remain
available. WhatIf still exports and prepares files, but does not disassociate,
import, or restart services; it needs access to the protected staging location.
It is not a read-only inspection mode.

## Protected staging and backups

**The `-BackupDir` parameter has been removed intentionally.** Do not pass it in
deployment commands. There is no custom staging/output directory and no TEMP
fallback. Each printer gets a fresh `UPConvert-<random-guid>` directory beneath
the existing Windows `SystemTemp` directory (normally `C:\Windows\SystemTemp`).
The Windows directory comes from the managed Windows special-folder API, not an
assumed drive or an environment-variable override. The script does not use
`TEMP`, `TMP`, `SystemTemp` environment variables, `GetTempPath`, or `GetTempPath2`.
The script prints the exact private run path before exporting.

The directory is created with inheritance disabled and a SYSTEM-owned DACL
granting full control only to SYSTEM and built-in Administrators. The DACL is
supplied **during creation**, using managed Windows APIs available in each
PowerShell edition; no `Add-Type` compilation or compiler TEMP files are needed.

**Supported-environment prerequisite:** the Windows directory and its volume
ancestors must already be protected by the operating system from low-privileged
replacement or reparse redirection. This script does **not** inspect or repair
that ancestry. This explicit prerequisite replaces the previous generic
ancestor-validation framework; it is not a claim that the folder name proves
the entire path safe. Administrators must establish this prerequisite before
deployment. Administrators, SYSTEM, and TrustedInstaller are outside the threat
model.

The script validates **SystemTemp itself** before creating a child: it must
exist, be an ordinary non-reparse directory, have a SYSTEM/Administrators/
TrustedInstaller owner and a canonical, non-null DACL. Only ordinary,
non-callback ACEs are supported; every allow ACE must name one of those three
trusted principals. Other grants are rejected even if read-only, inherit-only,
or masked by denies. This strict policy does not attempt effective-access
evaluation or determine whether a named account is currently an administrator.
An extra user-specific FullControl grant is therefore a policy rejection,
not by itself evidence of a low-privileged exploit.

Missing, inaccessible, or policy-rejected SystemTemp causes a clear failure
before disassociation. The script neither provisions/repairs the parent nor
falls back elsewhere. Windows' [GetTempPath2 documentation](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-gettemppath2w)
describes protected SystemTemp defaults, but also warns that the API does not
validate existence/access and preserves symbolic links. Defaults alone are
not relied upon here.

Under the ancestry prerequisite and checked-parent policy, a low-privileged
process cannot redirect the private paths or replace files between closing the
writer and `reg.exe` reopening them. Directory name collisions are rejected
before creation in the checked parent; individual files use exclusive
`CreateNew` reservation. `reg export /y` replaces only the reserved private
backup file. Both the export reread and every subsequent import use only the
private directory.

The baseline migration order is preserved: export/read the backup, disassociate
via pairtool, then check/load each user's hive and build, securely write, and
import that user's payload. The existing parser and payload builder are unchanged;
payload generation is not moved ahead of disassociation or hive availability.
Each writer is disposed before its file is imported. Preparation failures are
reported explicitly and stop the script with exit code 1 before importing the
failed payload or restarting services, including with caller error preferences
`Continue`, `Stop`, or `SilentlyContinue`. Disassociation and earlier successful
user imports may already have occurred. Stop is scoped to file preparation, not
applied globally to legacy native stderr or hive operations.

Complete per-system exports and generated per-user files remain in the private
directory, including useful completed files when a later preparation fails.
Incomplete files created by the script are removed; an incomplete export's
directory is removed only if empty. Cleanup failures produce warnings without
replacing the original failure. Per-user filenames use random identifiers;
the conversion output associates each imported file with its SID and instance
GUID. Backups can contain sensitive printer configuration: retain their private
ACLs, apply your organization's retention policy, and remove only the specific
run directories when no longer needed. These are retained **temporary**
backups, not durable archival storage: OS cleanup, maintenance tools, or an
administrator may remove them. Arrange trusted archival storage separately if
required; the script adds no output-copy step. Do not automatically import copied or
user-editable backup files as SYSTEM.

This is not transactional migration or complete recovery tooling. An exported
DAF registry entry alone is not a promise that pairtool disassociation can be
undone, and failures after disassociation (including payload creation failures)
may still require administrator repair. Preparing payloads earlier would be a
separate reliability change, not part of this staging fix.
Printer selection, DAF parsing/property generation, registry destinations,
pairtool behavior, hive handling, and service behavior otherwise remain unchanged.

## Signing

Editing the signed script invalidates its existing Authenticode signature block.
The historical block is not a valid signature for this revision. Obtain a fresh
signature from your authorized code-signing process before deployment under a
signed-script policy, and verify it with `Get-AuthenticodeSignature`. Do not
disable production execution policy as a substitute for re-signing.

## Focused regression checks

From the repository root:

```powershell
powershell.exe -NoProfile -File .\Scripts\Tests\Convert-UpPrinterToPerUser.Staging.Tests.ps1
pwsh.exe -NoProfile -File .\Scripts\Tests\Convert-UpPrinterToPerUser.Staging.Tests.ps1
```

The dependency-free checks extract production functions and the conversion loop.
They mock registry commands, hive operations, the production staging-directory
factory, pairtool discovery, and the pairtool command. File reservation, writes, reads, serialization,
collision handling, and cleanup use isolated, marked filesystem fixtures.
Error cases run in separate processes with all three caller preferences, without
an enclosing catch that could change production error semantics. Synthetic ACL
cases exercise the fixed-parent policy. Ordering checks verify disassociation
precedes hive checks and payload generation, unavailable hives skip generation,
and loaded hives are unloaded even on payload failure. Imported text is compared
with the unchanged builder's output. No printer, registry/hive, or service
mutation or elevation is performed.

These checks do **not** establish a successful SYSTEM conversion, test
cross-token attacks on an actual production run directory, or exercise the
production SYSTEM-owned directory creation in Windows SystemTemp. The ancestry
prerequisite is a deployment responsibility, not covered by these checks.
Those require a separately authorized disposable Windows environment; results
from other branches are not evidence for this revision.
