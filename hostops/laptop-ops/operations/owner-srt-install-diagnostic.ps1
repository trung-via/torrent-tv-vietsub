# Read-only reconcile exact prior installer attempt; no restart or retry.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$req=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$private=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\LaptopHostOps'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$state=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$reason='LOG_NOT_FOUND'; $phase='UNKNOWN'
$matchesFound=@(Get-ChildItem -LiteralPath $private -Directory -Filter 'run-*' | Where-Object {
    $f=Join-Path $_.FullName 'operation.ps1'
    (Test-Path -LiteralPath $f -PathType Leaf) -and (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLowerInvariant() -ceq 'fab026cbc01d8fa46314f27b930f38606179491f3ed7a0d946baf397f43483dd'
} | Sort-Object LastWriteTime -Descending)
if ($matchesFound.Count -eq 1) {
    $log=Join-Path $matchesFound[0].FullName 'full-owner-output.log'
    if (Test-Path -LiteralPath $log -PathType Leaf) {
        $lines=@(Get-Content -LiteralPath $log -Tail 160)
        $reason='UNCLASSIFIED'
        foreach ($line in $lines) {
            if ($line -cmatch '^OWNER_BRAIN_R3=HOLD_([A-Z0-9_]{3,80})$') { $reason=$Matches[1] }
        }
        $phase=if ($lines -contains 'OWNER_BRAIN_R3_RECOVERY=ORIGINAL_OWNER_RESTORED') {'ROLLED_BACK'} elseif ($lines -contains 'OWNER_BRAIN_R3_RECOVERY=ATTEMPTING_PRIVATE_ROLLBACK') {'RECOVERY_ATTEMPTED'} elseif ($lines -contains 'OWNER_BRAIN_R3_BACKUP=2_ORIGINALS_RECORDED') {'BACKUP_CREATED'} elseif ($lines -contains 'OWNER_BRAIN_R3_PREFLIGHT=PASS_OWNER_IDLE_STAGED_IMPORT') {'PREFLIGHT_PASSED'} else {'BEFORE_BACKUP'}
    }
} elseif ($matchesFound.Count -gt 1) {$reason='MULTIPLE_PRIOR_RUNS'}
function Classify([string]$path,[string]$old,[string]$new) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {return 'MISSING'}
    $h=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($h -ceq $old) {return 'OLD'}
    if ($h -ceq $new) {return 'NEW'}
    return 'OTHER'
}
$parser=Classify (Join-Path $root 'app\poc\p2-aisub\cue_pipeline.py') '96a569bcc5630f86db7e84a4c9df98442f946d7d3265d8ec2bab7d692365176a' 'caa28afbdfacf9acf2b6298fe295fc2802999a736cfceb856814e3c4b01c726f'
$brain=Classify (Join-Path $root 'app\poc\p2-sub-discovery\brain_english_inbox.py') 'dab7cfe87bb134c6ee939b62e0ee2f14ca7cee1c3744317c52c12eef3dc1cf07' 'dfa3f8cb7229885def3d88ab453dc4a7e1e90a474ff9b6c6f37b4ca5eb650ade'
$task=[string](Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent').State
$health='NOT_VERIFIED'
try {
    $h=Get-Content -LiteralPath (Join-Path $root 'agent-health.json') -Raw | ConvertFrom-Json
    $age=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-[long]$h.observed_utc_epoch
    $p=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$h.pid)
    if ($h.state -ceq 'READY' -and $age -ge 0 -and $age -le 30 -and $p -and $p.CommandLine -match 'owner_p3_p4_entrypoint\.py') {$health='READY_FRESH'}
} catch {}
$pending=@(Get-ChildItem -LiteralPath (Join-Path $root 'inbox') -File -Filter 'event-*.json').Count
$inflight=0; $locks=0
if (Test-Path -LiteralPath $state -PathType Container) {
    $inflight=@(Get-ChildItem -LiteralPath $state -Recurse -File -Filter '*.inflight').Count
    $locks=@(Get-ChildItem -LiteralPath $state -Recurse -File -Filter 'active.lock').Count
}
$r=@{schema='TTV-SRT-INSTALL-DIAG-V1';nonce=$req.nonce;reason=$reason;phase=$phase;parser=$parser;brain=$brain;task=$task;health=$health;pending=$pending;inflight=$inflight;locks=$locks}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\srt-install-diag-'+$req.nonce+'.json')),($r|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
