# Exact-owner integration STARTUP gate on dedicated GitHub Windows runner.
# Test direct Python invocation WITHOUT PYTHONPATH and inspect the *registered*
# owner Task Scheduler object read-only. Never read private owner profile, SID,
# key, P4 pairing, films; never Start/Stop task, install service, bind LAN.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_ACTIONS -cne 'true') {
    throw 'P4_OWNER_STARTUP_UNTRUSTED_HOST'
}
$expected = @{
    'poc/p2-sub-discovery/owner_p3_p4_entrypoint.py' = '192bef161386beb47f38ca73cdd8dfde292afb0e'
    'poc/p2-sub-discovery/test_owner_p3_p4_private_bootstrap.py' = 'e106f832b6f68e11a261b10f56b349dea226a5c6'
}
foreach ($item in $expected.GetEnumerator()) {
    $got = (& git rev-parse ("HEAD:" + $item.Key) | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $got -cne $item.Value) {
        throw 'P4_OWNER_STARTUP_SOURCE_BLOB_DRIFT'
    }
}
$python = 'C:\Program Files\Python314\python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw 'P4_OWNER_STARTUP_PYTHON_MISSING'
}
$script = Join-Path $env:GITHUB_WORKSPACE 'poc\p2-sub-discovery\owner_p3_p4_entrypoint.py'
$oldPyPath = [Environment]::GetEnvironmentVariable('PYTHONPATH','Process')
try {
    [Environment]::SetEnvironmentVariable('PYTHONPATH',$null,'Process')
    # CI flag is intentionally true. Script must import all modules from its
    # installed sibling tree and refuse BEFORE any private root or LAN touch.
    $result = @(& $python -E $script --owner-root 'C:\p4-test-nonexistent-owner' --cache-root 'C:\p4-test-nonexistent-cache' --state-root 'C:\p4-test-nonexistent-state' --start-lan 2>$null)
    $exit = $LASTEXITCODE
    if ($exit -ne 1 -or
        @($result | Where-Object { $_ -ceq 'P3_P4_OWNER_INTERACTIVE_EXPLICIT_START_REQUIRED' }).Count -ne 1) {
        throw 'P4_OWNER_STARTUP_DIRECT_IMPORT_OR_CI_GUARD_FAIL'
    }
} finally {
    [Environment]::SetEnvironmentVariable('PYTHONPATH',$oldPyPath,'Process')
}
Write-Host 'P4_OWNER_STARTUP_DIRECT_ENTRYPOINT_IMPORT_AND_GUARD_PASS'
try {
    $task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -ErrorAction Stop
    Write-Host 'P4_OWNER_SCHEDULED_TASK=VISIBLE'
    Write-Host ('P4_OWNER_TASK_INTERACTIVE_LOGON=' + (
        [string]$task.Principal.LogonType -eq 'Interactive').ToString().ToUpperInvariant())
    Write-Host ('P4_OWNER_TASK_STATE_RUNNING=' + (
        [string]$task.State -eq 'Running').ToString().ToUpperInvariant())
} catch {
    Write-Host 'P4_OWNER_SCHEDULED_TASK=NOT_ACCESSIBLE_OR_NOT_REGISTERED'
}
Write-Host 'P4_OWNER_STARTUP_OWNER_PROFILE_READ=NO'
Write-Host 'P4_OWNER_STARTUP_OWNER_TASK_START_STOP=NO'
Write-Host 'P4_OWNER_STARTUP_LAN_OR_PROVIDER=NO'
