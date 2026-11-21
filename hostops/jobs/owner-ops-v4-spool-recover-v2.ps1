# Reconcile a single timed-out Owner V4 request. No Owner code, TV or P2 writes.
# Archive ambiguous old request + unrelated previous receipt, never delete.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo='trung-via/torrent-tv-vietsub'
if ($PSVersionTable.PSVersion.Major -lt 7 -or
    $env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REPOSITORY -cne $repo -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne 'S-1-5-20') {
    throw 'OWNER_OPS_RECOVER_WRONG_RUNNER'
}
$oldCommit='1559ef1587debeb19879b4aca885096c14e7ae48'
$taskName='TorrentTV-Vietsub-Laptop-HostOps'
$ownerName='TorrentTV-Vietsub-OwnerAgent'
$capName='TorrentTV-Vietsub-Owner-Diagnostic-Capture'
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$req=Join-Path $spool 'Requests\request.json'
$rec=Join-Path $spool 'Receipts\receipt.json'
$snapshot=Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\Diagnostics\owner-snapshot.json'
function AssertFile([string]$p,[int]$max) {
    $i=Get-Item -LiteralPath $p -Force -ErrorAction Stop
    if ($i.PSIsContainer -or $i.Length -le 0 -or $i.Length -gt $max -or
        ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'OWNER_OPS_RECOVER_UNTRUSTED_FILE'
    }
}
function AssertDir([string]$p) {
    $i=Get-Item -LiteralPath $p -Force -ErrorAction Stop
    if (-not $i.PSIsContainer -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'OWNER_OPS_RECOVER_UNTRUSTED_DIRECTORY'
    }
}
$owner=Get-ScheduledTask -TaskName $ownerName -TaskPath '\' -ErrorAction Stop
$ops=Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
$cap=Get-ScheduledTask -TaskName $capName -TaskPath '\' -ErrorAction Stop
if ([string]$owner.State -cne 'Running' -or
    [string]$ops.State -cne 'Ready' -or [string]$cap.State -cne 'Ready' -or
    [string]$ops.Description -cne 'TTV_LAPTOP_HOSTOPS_OWNER_INTERACTIVE_ROUTINE_V1' -or
    [string]$cap.Description -cne 'TTV_OWNER_HOSTOPS_P3_P2_CAPTURE_READONLY_V1') {
    throw 'OWNER_OPS_RECOVER_TASK_DRIFT'
}
$info=Get-ScheduledTaskInfo -TaskName $taskName -TaskPath '\' -ErrorAction Stop
$code=[uint32]([long]$info.LastTaskResult -band 4294967295)
if ([long]$code -ne 3221225786 -or $info.LastRunTime -gt (Get-Date).AddMinutes(-5)) {
    throw 'OWNER_OPS_RECOVER_LAST_RUN_NOT_EXPIRED'
}
foreach($d in @($spool,(Join-Path $spool 'Requests'),(Join-Path $spool 'Receipts'))) {
    AssertDir $d
}
AssertFile $req 1024
AssertFile $rec 512
$a=Get-Content -LiteralPath $req -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
$b=Get-Content -LiteralPath $rec -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
if ($a.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    $a.source_commit -cne $oldCommit -or
    [string]$a.nonce -cnotmatch '^[0-9a-f]{32}$' -or
    $b.schema -cne 'TTV-LAPTOP-HOSTOPS-RECEIPT-V1' -or
    [string]$b.nonce -cnotmatch '^[0-9a-f]{32}$' -or
    [string]$b.result -cnotin @('SUCCESS','FAILED_NO_RETRY') -or
    ($a.nonce -ceq $b.nonce -and $a.source_commit -ceq $b.source_commit)) {
    throw 'OWNER_OPS_RECOVER_NOT_AMBIGUOUS_EXPECTED_REQUEST'
}
$now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
if (($now-[long]$a.requested_utc_epoch) -lt 300 -or
    ($now-[long]$a.requested_utc_epoch) -gt 86400) {
    throw 'OWNER_OPS_RECOVER_REQUEST_AGE_INVALID'
}
# Fresh diagnostic via the pre-enrolled, read-only task, not a recycled snapshot.
$since=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Start-ScheduledTask -TaskName $capName -TaskPath '\' -ErrorAction Stop
$verified=$false
for($i=0;$i -lt 45;$i++) {
    Start-Sleep -Seconds 1
    if ([string](Get-ScheduledTask -TaskName $capName -TaskPath '\').State -cne 'Ready') {continue}
    try {
        AssertFile $snapshot 4096
        $s=Get-Content -LiteralPath $snapshot -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        $age=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-[long]$s.snapshot_utc_epoch
        if ($s.schema -cne 'TTV-HOSTOPS-OWNER-SNAPSHOT-V3' -or
            $s.mode -cne 'INTEGRATED_P3_P4' -or
            $s.status -cne 'READY_FRESH' -or
            [long]$s.snapshot_utc_epoch -lt ($since-2) -or $age -lt 0 -or $age -gt 20 -or
            $s.p3_state -cnotin @('STALE','FRESH_OFF') -or
            [string]$s.p2.status -cne 'CLEAR' -or
            [long]$s.p2.pending_events -ne 0 -or [long]$s.p2.inflight_count -ne 0) {
            continue
        }
        $verified=$true;break
    } catch {continue}
}
if (-not $verified) {throw 'OWNER_OPS_RECOVER_FRESH_V3_IDLE_NOT_PROVEN'}
# Recheck neither task nor active request changed after capture.
if ([string](Get-ScheduledTask -TaskName $taskName -TaskPath '\').State -cne 'Ready' -or
    [string](Get-ScheduledTask -TaskName $ownerName -TaskPath '\').State -cne 'Running') {
    throw 'OWNER_OPS_RECOVER_TASK_CHANGED'
}
AssertFile $req 1024
AssertFile $rec 512
$a2=Get-Content -LiteralPath $req -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
$b2=Get-Content -LiteralPath $rec -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
if ($a2.nonce -cne $a.nonce -or $a2.source_commit -cne $a.source_commit -or
    $b2.nonce -cne $b.nonce -or $b2.source_commit -cne $b.source_commit) {
    throw 'OWNER_OPS_RECOVER_SPOOL_CHANGED'
}
$history=Join-Path $spool 'History'
if (-not (Test-Path -LiteralPath $history)) {
    New-Item -ItemType Directory -Path $history -ErrorAction Stop | Out-Null
}
AssertDir $history
$target=Join-Path $history ('unresolved-v4-'+$a.nonce)
if (Test-Path -LiteralPath $target) {throw 'OWNER_OPS_RECOVER_ARCHIVE_ALREADY_EXISTS'}
New-Item -ItemType Directory -Path $target -ErrorAction Stop | Out-Null
Move-Item -LiteralPath $req -Destination (Join-Path $target 'request.json') -ErrorAction Stop
Move-Item -LiteralPath $rec -Destination (Join-Path $target 'unmatched-previous-receipt.json') -ErrorAction Stop
Write-Output 'OWNER_OPS_RECOVER=OLD_AMBIGUOUS_REQUEST_ARCHIVED_NO_REPLAY'
Write-Output 'OWNER_OPS_RECOVER_OWNER=V3_RUNNING_P2_CLEAR'
Write-Output 'OWNER_OPS_RECOVER_PREVIOUS_EFFECT=UNVERIFIED'
Write-Output 'OWNER_OPS_RECOVER_TV_PROVIDER=NOT_RUN'
