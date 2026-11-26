# Bounded read-only observation of the Owner-written ProgramData snapshot.
# Reader tolerates additive known-schema fields; never emits raw media/IDs.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $sid -cne 'S-1-5-20') {
    throw 'OWNER_AUDIT_TRUSTED_RUNNER_REQUIRED'
}
$task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\' -ErrorAction SilentlyContinue
Write-Output ('OWNER_AUDIT_TASK=' + $(if ($null -ne $task -and
    [string]$task.State -ceq 'Running') { 'RUNNING' } else { 'NOT_RUNNING_OR_UNAVAILABLE' }))
$taskState = if ($null -eq $task) { 'MISSING' } elseif (
    [string]$task.State -in @('Running','Ready','Disabled')) {
    [string]$task.State
} else { 'OTHER' }
Write-Output ('OWNER_AUDIT_TASK_STATE=' + $taskState.ToUpperInvariant())
$ownerWorkers = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
    $_.Name -in @('python.exe','pythonw.exe','py.exe') -and
    [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
})
Write-Output ('OWNER_AUDIT_OWNER_PROCESS_COUNT=' + $ownerWorkers.Count)
$file = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\Diagnostics\owner-snapshot.json'
if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
    Write-Output 'OWNER_AUDIT_SNAPSHOT=MISSING'
    return
}
$item = Get-Item -LiteralPath $file -Force
if ($item.Length -lt 1 -or $item.Length -gt 4096 -or
    ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'OWNER_AUDIT_SNAPSHOT_FILE_UNTRUSTED'
}
$doc = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$doc.schema -cnotmatch '^TTV-HOSTOPS-OWNER-SNAPSHOT-V[1-4]$') {
    Write-Output 'OWNER_AUDIT_SCHEMA=UNSUPPORTED'
    return
}
Write-Output ('OWNER_AUDIT_SCHEMA=' + [string]$doc.schema)
Write-Output ('OWNER_AUDIT_TOP_LEVEL_FIELDS=' + @($doc.PSObject.Properties).Count)
function SafeEnum([object]$value) {
    $s = [string]$value
    if ($s -cmatch '^[A-Z][A-Z0-9_]{0,80}$') { return $s }
    return 'NOT_OBSERVED'
}
function SafeNum([object]$value) {
    if ($null -eq $value -or $value -isnot [ValueType]) { return -1L }
    try { $num = [long]$value } catch { return -1L }
    if ($num -lt -1 -or $num -gt 4102444800) { return -1L }
    return $num
}
function SafeGet([object]$obj, [string]$name) {
    if ($null -eq $obj) { return $null }
    $p = $obj.PSObject.Properties[$name]
    if ($null -eq $p) { return $null }
    return $p.Value
}
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$stamp = SafeNum (SafeGet $doc 'snapshot_utc_epoch')
Write-Output ('OWNER_AUDIT_SNAPSHOT_AGE_SECONDS=' + $(if ($stamp -gt 0) { $now - $stamp } else { -1 }))
foreach ($name in @('status','heartbeat','p3_state','torrserver','mode','version')) {
    if ($name -ceq 'version') { continue } # dynamic version is not a status enum
    Write-Output ('OWNER_AUDIT_' + $name.ToUpperInvariant() + '=' + (SafeEnum (SafeGet $doc $name)))
}
$ingress = SafeGet $doc 'ingress'
if ($null -ne $ingress) {
    Write-Output ('OWNER_AUDIT_INGRESS_FIELDS=' + @($ingress.PSObject.Properties).Count)
    foreach ($name in @('state_accepted','state_rejected','selection_dispatched',
        'selection_skipped','selection_rejected',
        'selection_rejected_bad_wire','selection_rejected_media_mismatch',
        'selection_rejected_current_tv_or_torrserver_unavailable',
        'selection_rejected_owner_policy','selection_rejected_enqueue',
        'selection_rejected_http_format','selection_rejected_unknown')) {
        Write-Output ('OWNER_AUDIT_' + $name.ToUpperInvariant() + '=' + (SafeNum (SafeGet $ingress $name)))
    }
}
$p2 = SafeGet $doc 'p2'
if ($null -ne $p2) {
    foreach ($name in @('status','outcome','batch','final_present','checkpoint_present')) {
        # Batch can contain a nonpublic identifier: export only status fields.
        if ($name -ceq 'batch') { continue }
        Write-Output ('OWNER_AUDIT_P2_' + $name.ToUpperInvariant() + '=' +
            (SafeEnum (SafeGet $p2 $name)))
    }
    foreach ($name in @('pending_events','inflight_count','blocked_events',
        'review_events','deferred_events','committed_prefix','inflight_age_seconds')) {
        Write-Output ('OWNER_AUDIT_P2_' + $name.ToUpperInvariant() + '=' +
            (SafeNum (SafeGet $p2 $name)))
    }
}
$p4 = SafeGet $doc 'p4'
if ($null -ne $p4) {
    foreach ($name in @('status','last_delivery','rolling_status')) {
        Write-Output ('OWNER_AUDIT_P4_' + $name.ToUpperInvariant() + '=' +
            (SafeEnum (SafeGet $p4 $name)))
    }
    foreach ($name in @('dispatches','activate_ok','activate_rejected',
        'revision_ready','revision_empty','revision_hold','source_not_accepted')) {
        Write-Output ('OWNER_AUDIT_P4_' + $name.ToUpperInvariant() + '=' +
            (SafeNum (SafeGet $p4 $name)))
    }
}
Write-Output 'OWNER_AUDIT=READ_ONLY_NO_RESTART_NO_PROVIDER_NO_MEDIA_EXPORT'

# Read only logcat markers from the authorized Redmi; no raw log lines, identifiers or dialogue.
$adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
if (!(Test-Path -LiteralPath $adb) -or @(Get-Process -Name adb -ErrorAction SilentlyContinue).Count -eq 0) { Write-Output 'BENCH_TV=ADB_UNAVAILABLE';return }
$devices=@(& $adb devices 2>$null)
$online=@($devices|Where-Object {$_ -match '^[^\s]+\s+device(\s|$)'})
if($LASTEXITCODE -ne 0 -or $online.Count -ne 1 -or @($devices|Where-Object {$_ -match '^[^\s]+\s+(offline|unauthorized)(\s|$)'}).Count -ne 0){Write-Output 'BENCH_TV=DEVICE_UNAVAILABLE';return}
$serial=($online[0].Trim() -split '\s+')[0]
$model=(@(& $adb -s $serial shell getprop ro.product.model 2>$null) -join '').Trim()
if($model -cne 'MiTV-ASTR0'){Write-Output 'BENCH_TV=MODEL_MISMATCH';return}
$pidText=(@(& $adb -s $serial shell pidof com.spacesarmat.omp.test 2>$null) -join '').Trim()
if($pidText -cnotmatch '^[0-9]{1,10}$'){Write-Output 'BENCH_TV=OMP_PID_UNAVAILABLE';return}
$deviceEpoch=(@(& $adb -s $serial shell date +%s 2>$null) -join '').Trim()
$now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Write-Output ('BENCH_TV_CLOCK_OFFSET_SECONDS='+$(if($deviceEpoch -match '^[0-9]{10}$'){[long]$deviceEpoch-$now}else{-99999}))
$log=@(& $adb -s $serial logcat -d -t 2000 -v epoch --pid=$pidText -s TorrentTV-Vietsub:I 2>$null)
if($LASTEXITCODE -ne 0){Write-Output 'BENCH_TV=LOGCAT_UNAVAILABLE';return}
$events=@(foreach($line in $log){
 if($line -match '^\s*(\d{10}(?:\.\d+)?)\s+.*?\b(P4_TV_ACTIVATE_NOT_READY|P4_TV_SESSION_ACCEPTED|P4_TV_OFFER_RECEIVED_UNVERIFIED|P4_TV_OVERLAY_INSTALLED|P4_TV_SAVED_OVERLAY_RESTORED)\s*$'){
  $t=[double]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture)
  if($t -ge 1795735806){[pscustomobject]@{T=$t;Code=$Matches[2]}}
 }
})
# Include first/last and count only; no content or log payload.
foreach($code in @('P4_TV_ACTIVATE_NOT_READY','P4_TV_SESSION_ACCEPTED','P4_TV_OFFER_RECEIVED_UNVERIFIED','P4_TV_OVERLAY_INSTALLED','P4_TV_SAVED_OVERLAY_RESTORED')){
 $hits=@($events|Where-Object {$_.Code -ceq $code}|Sort-Object T)
 if($hits.Count -gt 0){Write-Output ('BENCH_TV_MARKER='+$code+' COUNT='+$hits.Count+' FIRST='+[long][math]::Floor($hits[0].T)+' LAST='+[long][math]::Floor($hits[-1].T))}
 else{Write-Output ('BENCH_TV_MARKER='+$code+' COUNT=0')}
}
Write-Output 'BENCH_TV=READ_ONLY_LOGCAT_NOT_VISIBLE_CUE_PROOF'
