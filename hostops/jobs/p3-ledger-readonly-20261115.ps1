# One-shot read-only P3 ledger receipt audit. No media, secrets or LAN data printed.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:GITHUB_ACTIONS -cne 'true' -or
    [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne 'S-1-5-20') {
    throw 'TTV_P3_LEDGER_UNTRUSTED_RUNNER'
}
Write-Host 'TTV_P3_LEDGER_MODE=READ_ONLY'
$task = @(Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -ErrorAction Stop)
if ($task.Count -ne 1 -or $task[0].TaskPath -cne '\') {
    Write-Host 'TTV_P3_LEDGER=HOLD_TASK_IDENTITY'
    exit 0
}
Write-Host ('TTV_P3_LEDGER_TASK_STATE=' + [string]$task[0].State)
if ([string]$task[0].State -cne 'Running') {
    Write-Host 'TTV_P3_LEDGER=HOLD_TASK_NOT_RUNNING'
    exit 0
}
try {
    $userId = [string]$task[0].Principal.UserId
    if ($userId.StartsWith('S-1-5-', [StringComparison]::Ordinal)) {
        $ownerSid = New-Object Security.Principal.SecurityIdentifier($userId)
    } else {
        $ownerSid = (New-Object Security.Principal.NTAccount($userId)).Translate(
            [Security.Principal.SecurityIdentifier])
    }
    if ($ownerSid.Value -eq 'S-1-5-20' -or $ownerSid.Value -eq 'S-1-5-18') {
        throw 'TTV_P3_LEDGER_WRONG_OWNER_PRINCIPAL'
    }
    $key = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\' + $ownerSid.Value
    $profilePath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables(
        [string](Get-ItemProperty -LiteralPath $key -ErrorAction Stop).ProfileImagePath))
    $ledger = [IO.Path]::GetFullPath((Join-Path $profilePath 'AppData\Local\TorrentTVVietsub\OwnerBridge\p3-replay\ledger.sqlite3'))
    if (-not $ledger.StartsWith($profilePath.TrimEnd('\') + '\',
        [StringComparison]::OrdinalIgnoreCase)) {
        throw 'TTV_P3_LEDGER_PATH_GUARD'
    }
} catch {
    Write-Host 'TTV_P3_LEDGER=HOLD_PROFILE_RESOLUTION'
    exit 0
}
if (-not (Test-Path -LiteralPath $ledger -PathType Leaf)) {
    Write-Host 'TTV_P3_LEDGER=HOLD_NOT_FOUND_OR_ACCESS_DENIED'
    exit 0
}
try {
    foreach ($part in @((Split-Path -Parent $ledger), $ledger)) {
        if ((Get-Item -LiteralPath $part -ErrorAction Stop).Attributes -band
            [IO.FileAttributes]::ReparsePoint) {
            throw 'TTV_P3_LEDGER_UNSAFE_REPARSE'
        }
    }
} catch {
    Write-Host 'TTV_P3_LEDGER=HOLD_ACCESS_OR_REPARSE'
    exit 0
}
$pythonCandidates = @()
$localPythonRoot = Join-Path $profilePath 'AppData\Local\Programs\Python'
if (Test-Path -LiteralPath $localPythonRoot -PathType Container) {
    $pythonCandidates += @(Get-ChildItem -LiteralPath $localPythonRoot -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'python.exe' })
}
$pythonCandidates += @(Get-Command python.exe -All -ErrorAction SilentlyContinue |
    Where-Object { $_.Source -and $_.Source -notmatch '\\WindowsApps\\' } |
    ForEach-Object { $_.Source })
$python = @($pythonCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1)
if ($python.Count -ne 1) {
    Write-Host 'TTV_P3_LEDGER=HOLD_PYTHON_UNAVAILABLE'
    exit 0
}
# The Python standard library opens SQLite in URI mode=ro + PRAGMA query_only.
# Accepted replay receipts do not store event kind; never manufacture it.
$reader = @'
import datetime, pathlib, sqlite3, sys, time
p = pathlib.Path(sys.argv[1])
try:
    con = sqlite3.connect(p.as_uri() + "?mode=ro", uri=True, timeout=2.0)
    con.execute("PRAGMA query_only=ON")
    state = con.execute("SELECT received_ms FROM state_head WHERE singleton=1").fetchone()
    selection = con.execute("SELECT MAX(received_ms) FROM recent_nonce WHERE stream='selection'").fetchone()
    sent = con.execute("SELECT sent_ms FROM selection_head WHERE singleton=1").fetchone()
    con.close()
except (OSError, sqlite3.Error, ValueError):
    print("TTV_P3_LEDGER=HOLD_READ_UNAVAILABLE")
    sys.exit(0)
now = int(time.time() * 1000)
def report(name, stamp):
    if stamp is None:
        print(name + "=NONE")
        return
    age = (now - int(stamp)) // 1000
    if age < -5:
        print(name + "=CLOCK_SKEW")
        return
    print(name + "_AGE_SECONDS=" + str(max(0, age)))
    utc = datetime.datetime.fromtimestamp(int(stamp) / 1000, datetime.timezone.utc)
    print(name + "_UTC_MINUTE=" + utc.strftime("%Y-%m-%dT%H:%MZ"))
report("TTV_P3_STATE_RECEIPT", state[0] if state else None)
report("TTV_P3_SELECTION_RECEIPT", selection[0] if selection and selection[0] is not None else None)
print("TTV_P3_SELECTION_HEAD_EXISTS=" + str(bool(sent)).upper())
print("TTV_P3_EVENT_KIND=NOT_STORED_IN_REPLAY_LEDGER")
print("TTV_P3_LEDGER=READ_ONLY_COMPLETE")
'@
try {
    & $python[0] -c $reader $ledger
    if ($LASTEXITCODE -ne 0) { Write-Host 'TTV_P3_LEDGER=HOLD_READER_FAILED' }
} catch {
    Write-Host 'TTV_P3_LEDGER=HOLD_READER_UNAVAILABLE'
}
