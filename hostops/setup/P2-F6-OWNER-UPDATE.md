# P2-F6 Owner bootstrap compatibility — 2026-11-18

**Scope:** Windows Owner Task exits `LastTaskResult=1`, its correlated health is
`BLOCKED`, and V3 says `INIT_FAILED`. The pinned R0 base bootstrap still demands
the billed Gemini Developer API credentials/profile, while F4/F5 already
installed the owner-local Antigravity CLI P2 modules. A mixed installation
cannot construct the automatic subtitle flow.

**Source:** Draft PR #173. F6 was introduced in commit `a8683caa112ec9c07bc8e5f1228d6a2aa6580ddd`;
the three replacement files are pinned to their unchanged bytes in
`e18660655d0df780dccc8982926ce1ceb45b165e`.

**F6.1 source-pin correction (2026-11-18):** The original F6 pinned
`start-owner-session-agent.ps1` to its **Windows checkout CRLF** SHA while the
installer's `Canonical-Bytes` hashes **LF-normalized** bytes. Thus a clean,
hash-verified archive still hit `P2_F6_SOURCE_PIN_MISMATCH` on the third file.
F6.1 pins the canonical LF hash and adds a CRLF-vs-LF regression test. The
replacement bootstrap files and installed Owner state are otherwise unchanged.

The standalone archive contains exactly three reviewed source files plus the
F6 installer. It does NOT download code during installation, modify secrets,
call OpenSubtitles/Antigravity, bind a listener, touch the TV or alter quarantine.

## Owner-local installation

Open PowerShell 7.7 **as the same signed-in Windows owner**. Extract the ZIP to a
new directory and `Set-Location` into its root. Copy this block as a whole:

```powershell
& {
    $ErrorActionPreference = 'Stop'
    $repair = Join-Path (Get-Location).Path 'hostops\setup\p2-f6-owner-bootstrap-compat-upgrade.ps1'
    & pwsh -NoProfile -File $repair
    if ($LASTEXITCODE -ne 0) { throw 'P2_F6_INSPECT_HOLD_NO_MUTATION' }

    Disable-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' | Out-Null
    & pwsh -NoProfile -File $repair -InstallOffline
    if ($LASTEXITCODE -ne 0) {
        throw 'P2_F6_INSTALL_HOLD_TASK_REMAINS_DISABLED_REVIEW_OUTPUT'
    }

    Enable-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' | Out-Null
    Start-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent'
    Start-Sleep -Seconds 6
    Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' |
        Select-Object TaskName,State
    Get-ScheduledTaskInfo -TaskName 'TorrentTV-Vietsub-OwnerAgent' |
        Select-Object LastTaskResult,LastRunTime
}
```

Success in the installer must read:

```
P2_F6_RESULT=BOOTSTRAP_COMPAT_INSTALLED_VERIFIED_TASK_DISABLED
P2_F6_QUARANTINED_BATCH=UNTOUCHED_NO_RETRY
```

Only the final Task state and new current Owner health/heartbeat can prove a
successful Windows runtime start. The Task may remain `Running`; a result of
`1`/`Ready` requires new diagnosis, **not** repeat installation blindly.

If any command raises `HOLD`, preserve backup in
`%LOCALAPPDATA%\TorrentTVVietsub\OwnerBridge\backups\p2-f6-bootstrap`
and stop. Do not remove the existing unknown-effect translation markers.
