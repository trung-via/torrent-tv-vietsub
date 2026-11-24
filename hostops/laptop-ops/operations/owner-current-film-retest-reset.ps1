# Reset only the latest verified film's translated checkpoint, retaining English and other films.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$base = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$owner = Join-Path $base 'OwnerBridge'
$cache = Join-Path $base 'subtitle-trials'
$p2 = Join-Path $base 'P2\auto-lean120-state'
$inbox = Join-Path $owner 'inbox'
$healthFile = Join-Path $owner 'agent-health.json'
$archives = Join-Path $base 'CacheArchives'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
function Hold([string]$code) {
    try {
        $spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
        $req=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
        if ($code -cmatch '^[A-Z0-9_]{3,100}$' -and $req.nonce -cmatch '^[0-9a-f]{32}$') {
            $rec=@{schema='TTV-RETEST-HOLD-V1';nonce=$req.nonce;reason=$code}
            [IO.File]::WriteAllText((Join-Path $spool ('Receipts\retest-hold-'+$req.nonce+'.json')),($rec|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
        }
    } catch {}
    throw ('OWNER_CACHE_PURGE_HOLD_' + $code)
}
function AssertDir([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { Hold 'ROOT_MISSING' }
    if ((Get-Item -LiteralPath $path -Force).Attributes -band
        [IO.FileAttributes]::ReparsePoint) { Hold 'ROOT_REPARSE' }
}
function OwnerTask {
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    $taskSid = [string]$task.Principal.UserId
    if ($taskSid -cnotmatch '^S-\d+(?:-\d+){2,}$') {
        $taskSid = ([Security.Principal.NTAccount]::new($taskSid).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    }
    if ($taskSid -cne $sid -or [string]$task.Principal.LogonType -ine 'Interactive' -or
        @($task.Actions).Count -ne 1 -or
        [string]$task.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
        Hold 'OWNER_TASK_IDENTITY_DRIFT'
    }
    return $task
}
function OwnerWorkers {
    @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function AssertIdle {
    if (@(Get-ChildItem -LiteralPath $inbox -File -Force -Filter 'event-*.json').Count -ne 0) {
        Hold 'PENDING_OWNER_EVENT'
    }
    $locks = @(Get-ChildItem -LiteralPath $p2 -File -Force -Recurse |
        Where-Object { $_.Name -ceq 'active.lock' -or
                       $_.Name -cmatch '^batch-[0-9]{4}\.inflight$' })
    if ($locks.Count -ne 0) { Hold 'P2_ACTIVE_OR_UNKNOWN_EFFECT' }
}
function StopVerifiedWorkers {
    for ($i=0; $i -lt 8; $i++) {
        if (@(OwnerWorkers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    $workers = @(OwnerWorkers)
    if ($workers.Count -gt 4) { Hold 'UNEXPECTED_WORKERS' }
    $app = Join-Path $owner 'app\poc\p2-sub-discovery'
    $allowed = @((Join-Path $app 'owner_p3_p4_entrypoint.py'),
                 (Join-Path $app 'owner_session_bridge.py'))
    foreach ($worker in $workers) {
        $matches = @($allowed | Where-Object {
            [string]$worker.CommandLine -and
            $worker.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        $who = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid -ErrorAction Stop
        if ($matches.Count -ne 1 -or $who.ReturnValue -ne 0 -or $who.Sid -cne $sid) {
            Hold 'WORKER_IDENTITY_UNVERIFIED'
        }
    }
    foreach ($worker in $workers) {
        AssertIdle
        Stop-Process -Id ([int]$worker.ProcessId) -Force -ErrorAction Stop
    }
    if (@(OwnerWorkers).Count -ne 0) { Hold 'WORKERS_STILL_RUNNING' }
}
function StartOwner([long]$oldPid) {
    $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($i=0; $i -lt 45; $i++) {
        Start-Sleep -Seconds 1
        if ([string](OwnerTask).State -cne 'Running') { continue }
        try {
            $h = Get-Content -LiteralPath $healthFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($h.state -cne 'READY' -or [long]$h.pid -le 0 -or
                [long]$h.pid -eq $oldPid -or [long]$h.observed_utc_epoch -lt $since - 2) {
                continue
            }
            $worker = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [long]$h.pid)
            if ($null -eq $worker -or [string]$worker.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') {
                continue
            }
            $who = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
            if ($who.ReturnValue -eq 0 -and $who.Sid -ceq $sid) { return }
        } catch { continue }
    }
    Hold 'FRESH_OWNER_NOT_VERIFIED'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $sid -in @('S-1-5-18','S-1-5-19','S-1-5-20')) { Hold 'INTERACTIVE_OWNER_REQUIRED' }
foreach ($dir in @($base,$owner,$cache,$p2,$inbox)) { AssertDir $dir }
$state = [string](OwnerTask).State
if ($state -cnotin @('Running','Ready','Disabled')) { Hold 'OWNER_TASK_NOT_RUNNABLE' }
AssertIdle
if (Test-Path -LiteralPath $archives) { AssertDir $archives }
else { [IO.Directory]::CreateDirectory($archives) | Out-Null }
$oldPid = 0L
if (Test-Path -LiteralPath $healthFile -PathType Leaf) {
    try { $oldPid = [long](Get-Content -LiteralPath $healthFile -Raw -Encoding UTF8 | ConvertFrom-Json).pid }
    catch { Hold 'PREVIOUS_HEALTH_INVALID' }
}
# Same verified event is selected before and after shutdown; no old event is replayed.
$pyCode = @'
import hashlib, json, pathlib, re, sys, time, uuid
owner, cache, state, archive_root = map(pathlib.Path, sys.argv[1:5])
mode = sys.argv[5]
sys.path[:0] = [str(owner / "app/poc/p2-sub-discovery"), str(owner / "app/poc/p2-aisub"), str(owner / "app/poc/p3-vietsub-trigger")]
from matcher import Media
from brain_english_inbox import acquire_brain_english
from assumed_source_handoff import AssumedEnglishSubtitle
from automatic_lean120_worker import _job_fingerprint
from lean120_api import ModelProfile
def require(v, reason):
    if not v: raise ValueError(reason)
def read(p):
    require(p.is_file() and not p.is_symlink() and p.stat().st_size <= 16384, "RECEIPT_INVALID")
    return json.loads(p.read_text("utf-8"))
def main():
    # Latest actual successful P2 completion, not an arbitrary recent film.
    import ast
    log=owner/"diagnostics/owner-full.log"
    require(log.is_file() and not log.is_symlink(),"OWNER_LOG_MISSING")
    with log.open("rb") as stream:
        stream.seek(max(0,log.stat().st_size-1048576))
        tail=stream.read().decode("utf-8","replace")
    completed=[]
    for line in tail.splitlines():
        marker="OWNER_FULL_TRACE 'P2_EVENT_FINISHED' "
        if marker not in line: continue
        try: record=ast.literal_eval(line.split(marker,1)[1])
        except (ValueError,SyntaxError): continue
        if record.get("result")=="VIETSUB_READY" and re.fullmatch(r"[a-f0-9]{32}",str(record.get("event_id"))):
            completed.append(record["event_id"])
    require(completed,"NO_COMPLETED_VI_EVENT_IN_LOG")
    event=completed[-1] if mode=="plan" else sys.argv[6]
    require(event==completed[-1],"EVENT_CHANGED")
    p=owner/"inbox"/("event-"+event+".done")
    row=read(p); fp=row.get("source_fingerprint")
    require(row.get("event_id")==event and isinstance(fp,str) and re.fullmatch(r"[a-f0-9]{64}",fp),"EVENT_ID_INVALID")
    staged=cache/".brain-en-inbox"/fp
    receipt=read(staged/"receipt.json")
    require(receipt.get("source_fingerprint")==fp and receipt.get("video_name")==row.get("selected_video_filename") and receipt.get("language")=="en","EN_RECEIPT_EVENT_MISMATCH")
    from cached_en_direct_handoff import CachedEnReceipt, prepare_local_translation_source
    source=prepare_local_translation_source(CachedEnReceipt(staged/"english.srt",receipt["sha256"],receipt["cues"]),private_root=cache)
    from types import SimpleNamespace
    en=SimpleNamespace(sha256=source.source_sha256,cues=source.cue_count,contents=source.source_bytes)
    # No other staged film may share this source-derived worker namespace.
    for other in (cache/".brain-en-inbox").glob("*/receipt.json"):
        if other.parent.name!=fp:
            require(read(other).get("sha256")!=en.sha256,"SHARED_EN_JOB_OTHER_FILM")
    for other in cache.glob(".dual-source-*-ai_en.json"):
        if other.name!=".dual-source-"+fp+"-ai_en.json":
            require(read(other).get("sha256")!=en.sha256,"SHARED_EN_JOB_OTHER_FILM")
    for other in cache.glob(".auto-source-*.json"):
        if other.name!=".auto-source-"+fp+".json":
            require(read(other).get("sha256")!=en.sha256,"SHARED_EN_JOB_OTHER_FILM")
    key="media."+hashlib.sha256(b"TTV-P2-LOCAL-TRANSLATION-ONLY-V1\x00"+en.sha256.encode("ascii")).hexdigest()
    handoff=AssumedEnglishSubtitle.from_supplied(media_key=key,fmt="srt",source_bytes=en.contents)
    require(handoff.cue_count==en.cues,"EN_CUE_MISMATCH")
    jobs=[]
    for level in ("high","medium","low"):
        profile=ModelProfile("antigravity","gemini-4-hydrogen-"+level,level)
        job=state/_job_fingerprint(handoff,profile,{})
        if not job.exists(): continue
        require(job.is_dir() and not job.is_symlink(),"JOB_INVALID")
        require(not list(job.glob("*.inflight")) and not (job/"active.lock").exists(),"UNKNOWN_PROVIDER_EFFECT")
        require(not list(job.glob("*.abandoned.json")),"ABANDONED_JOB_HOLD")
        jobs.append(job)
    if not jobs:
        require(mode=='plan' or mode=='apply', 'MODE_INVALID')
    if mode=="plan":
        print(row["event_id"])
        return
    archive=archive_root/("single-film-retest-"+uuid.uuid4().hex)
    archive.mkdir()
    moved=[]
    try:
        for job in jobs:
            dst=archive/job.name
            job.rename(dst); moved.append((job,dst))
        require(all(not src.exists() and dst.is_dir() for src,dst in moved),"ARCHIVE_VERIFY_FAILED")
        require(hashlib.sha256((staged/'english.srt').read_bytes()).hexdigest()==en.sha256,"EN_CHANGED")
    except Exception:
        for src,dst in reversed(moved):
            if not src.exists() and dst.exists(): dst.rename(src)
        raise
    print("RETEST_RESET_PASS")
try: main()
except Exception as e:
    # Never print film metadata or filesystem path.
    v=str(e)
    print(v if re.fullmatch(r"[A-Z0-9_]{3,100}",v) else "RETEST_LOCAL_ERROR")
    sys.exit(1)
'@
$plan = @(& py -3 -I -B -c $pyCode $owner $cache $p2 $archives plan 2>$null)
if ($LASTEXITCODE -ne 0 -or $plan.Count -ne 1 -or [string]$plan[0] -cnotmatch '^[0-9a-f]{32}$') {
    if ($plan.Count -eq 1 -and [string]$plan[0] -cmatch '^[A-Z0-9_]{3,100}$') { Hold ([string]$plan[0]) }
    Hold 'CURRENT_FILM_PLAN_UNVERIFIED'
}
$eventId = [string]$plan[0]
$disabled=$false
try {
    AssertIdle
    Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    $disabled=$true
    if ($state -ceq 'Running') { Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop }
    StopVerifiedWorkers
    AssertIdle
    $done=@(& py -3 -I -B -c $pyCode $owner $cache $p2 $archives apply $eventId 2>$null)
    if ($LASTEXITCODE -ne 0 -or $done.Count -ne 1 -or [string]$done[0] -cne 'RETEST_RESET_PASS') {
        if ($done.Count -eq 1 -and [string]$done[0] -cmatch '^[A-Z0-9_]{3,100}$') { Hold ([string]$done[0]) }
        Hold 'TARGET_RESET_FAILED'
    }
    Write-Output 'OWNER_RETEST_RESET=EXACT_FILM_VI_CHECKPOINT_QUARANTINED_EN_PRESERVED'
    StartOwner $oldPid
    $disabled=$false
    Write-Output 'OWNER_RETEST_RESET=FRESH_OWNER_READY_NO_PROVIDER_CALL'
} catch {
    if ($disabled -and @(OwnerWorkers).Count -eq 0) {
        try { AssertIdle; StartOwner $oldPid } catch {}
    }
    throw
}
