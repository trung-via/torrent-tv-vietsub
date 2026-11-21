# READ ONLY: parse the Owner-interactive maintenance helper on trusted runner.
# Never invoke the helper, change Owner Scheduled Tasks or touch the TV.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $sid -cne 'S-1-5-20') {
    throw 'OWNER_P4_V4_PARSE_TRUSTED_RUNNER_REQUIRED'
}
$script = Join-Path $env:GITHUB_WORKSPACE 'hostops\setup\owner-p4-v4-maintenance-once.ps1'
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
    throw 'OWNER_P4_V4_PARSE_SCRIPT_MISSING'
}
$errors = $null
$tokens = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $script,[ref]$tokens,[ref]$errors)
if (@($errors).Count -ne 0) { throw 'OWNER_P4_V4_PARSE_FAILED' }
$body = [IO.File]::ReadAllText($script)
foreach ($anchor in @(
    'a3da96d0730cd2ff7fcf7345c0f7c900d568a975',
    '75fdb89a54cbccbb783c75022c99aa2fee91db57432e8ed27e48eb6dea6a75ef',
    'SnapshotGate', 'NoOpenWork', 'StopOwner', 'StartAndVerify',
    'OWNER_P4_V4=APPLIED_23_NEW_OWNER_HEALTH_VERIFIED',
    'OWNER_P4_V4=ROLLBACK_VERIFIED_OWNER_STOPPED'
)) {
    if (-not $body.Contains($anchor)) { throw 'OWNER_P4_V4_PARSE_PIN_OR_GUARD_MISSING' }
}
Write-Output 'OWNER_P4_V4_MAINTENANCE_PARSE=PASS_NOT_EXECUTED'
Write-Output 'OWNER_P4_V4_MAINTENANCE_OWNER_TV_PROVIDER=UNCHANGED'
