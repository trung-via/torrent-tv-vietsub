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
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$receiptPath = Join-Path $spool ('Receipts\retest-result-'+$rq.nonce+'.json')
$phase = 'PRECHECK'
$prior = 'NOT_FOUND'
$jobCount = -1
$registryState = 'NOT_CHECKED'
function Report([string]$status,[string]$reason) {
    $rec = [ordered]@{schema='TTV-RETEST-RESULT-V2';nonce=$rq.nonce;status=$status;phase=$script:phase;prior=$script:prior;jobs=$script:jobCount;registry=$script:registryState;reason=$reason}
    [IO.File]::WriteAllText($receiptPath,($rec|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
}
try {
    $history=Join-Path $spool 'History'
    foreach($f in @(Get-ChildItem -LiteralPath $history -Filter 'request-*.json' -File)) {
        $p=Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
        if ($p.source_commit -ceq '0f9f1a0e46951cbf70d067a30a76ac578034452d' -and $p.nonce -cmatch '^[a-f0-9]{32}$') {
            $log=Join-Path $base ('LaptopHostOps\run-'+$p.nonce+'\full-owner-output.log')
            if(Test-Path -LiteralPath $log -PathType Leaf) {
                $body=Get-Content -LiteralPath $log -Raw
                $prior=if($body -match 'Cannot find a process|No process with the specified|ProcessCommandException|NoProcessFoundForGivenId|No matching.*process') {'PROCESS_EXIT_RACE'} elseif($body -match 'Stop-ScheduledTask|0x8004130[Bb]|task is not running') {'TASK_STOP_ERROR'} elseif($body -match 'Cannot overwrite variable|read.only or constant') {'VARIABLE_COLLISION'} elseif($body -match 'Access is denied|AccessDenied|0x80070005') {'ACCESS_DENIED'} elseif($body -match 'EXACT_FILM_VI_CHECKPOINT_QUARANTINED') {'CACHE_MOVED'} elseif($body -match 'TARGET_RESET_FAILED') {'TARGET_RESET_FAILED'} elseif($body -match 'CURRENT_FILM_PLAN_UNVERIFIED') {'PLAN_FAILED'} elseif($body -match 'WORKERS_STILL_RUNNING') {'WORKERS_STILL_RUNNING'} elseif($body -match 'P2_ACTIVE_OR_UNKNOWN_EFFECT') {'P2_BUSY'} elseif($body -match 'FRESH_OWNER_NOT_VERIFIED') {'START_FAILED'} elseif($body -match 'Cannot convert|Cannot bind argument|Unexpected token|SyntaxError|ParserError|NameError|TypeError|AttributeError') {'SCRIPT_ERROR'} else {'PRIVATE_FAILURE_OTHER'}
            }
        }
    }
} catch { $prior='LOG_UNAVAILABLE' }
function Hold([string]$code) {
    try {
        $spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
        $req=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
        if ($code -cmatch '^[A-Z0-9_]{3,100}$' -and $req.nonce -cmatch '^[0-9a-f]{32}$') {
            $rec=@{schema='TTV-RETEST-HOLD-V1';nonce=$req.nonce;reason=$code}
            [IO.File]::WriteAllText((Join-Path $spool ('Receipts\retest-hold-'+$req.nonce+'.json')),($rec|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
        }
    } catch {}
    Report 'HOLD' $code
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
    $script:phase='DRAIN_WORKERS'
    for ($i=0; $i -lt 5; $i++) {
        if (@(OwnerWorkers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    $workers = @(OwnerWorkers)
    if ($workers.Count -gt 4) { Hold 'UNEXPECTED_WORKERS' }
    $app = Join-Path $owner 'app\poc\p2-sub-discovery'
    $allowed = @((Join-Path $app 'owner_p3_p4_entrypoint.py'),
                 (Join-Path $app 'owner_session_bridge.py'))
    $script:phase='STOP_VERIFIED_WORKERS'
    foreach ($worker in $workers) {
        AssertIdle
        if ([string](OwnerTask).State -cne 'Disabled') { Hold 'OWNER_TASK_REENABLED' }
        $live = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$worker.ProcessId)
        if ($null -eq $live) { continue }
        $pathHits = @($allowed | Where-Object {
            [string]$live.CommandLine -and
            $live.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        if ($pathHits.Count -ne 1 -or $live.CommandLine -cne $worker.CommandLine -or
            $live.CreationDate -ne $worker.CreationDate) { Hold 'WORKER_IDENTITY_CHANGED' }
        try {
            $who = Invoke-CimMethod -InputObject $live -MethodName GetOwnerSid -ErrorAction Stop
        } catch {
            if ($null -eq (Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$live.ProcessId))) { continue }
            throw
        }
        if ($who.ReturnValue -ne 0 -or $who.Sid -cne $sid) {
            if ($null -eq (Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$live.ProcessId))) { continue }
            Hold 'WORKER_IDENTITY_UNVERIFIED'
        }
        try { Stop-Process -Id ([int]$live.ProcessId) -Force -ErrorAction Stop }
        catch {
            if ($null -ne (Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$live.ProcessId))) { throw }
        }
    }
    $script:phase='VERIFY_STOPPED'
    for($i=0;$i -lt 10;$i++){
        if(@(OwnerWorkers).Count -eq 0){return}
        Start-Sleep -Seconds 1
    }
    Hold 'WORKERS_STILL_RUNNING'
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
    # Select most recent terminal event from authoritative persisted inbox,
    # not the rotating log. Require unique matching staged EN film.
    done=[]
    for p in (owner/"inbox").glob("event-*.done"):
        row=read(p)
        fp=row.get("source_fingerprint")
        event=row.get("event_id")
        if not isinstance(fp,str) or not re.fullmatch(r"[0-9a-f]{64}",fp): continue
        if not isinstance(event,str) or p.name!="event-"+event+".done": continue
        staged=cache/".brain-en-inbox"/fp
        if not (staged/"receipt.json").is_file(): continue
        receipt=read(staged/"receipt.json")
        if receipt.get("source_fingerprint")!=fp or receipt.get("video_name")!=row.get("selected_video_filename") or receipt.get("language")!="en": continue
        done.append((p.stat().st_mtime,event,fp,staged,receipt))
    require(done and len({x[2] for x in done})==1,"AMBIGUOUS_OR_MISSING_STAGED_EVENT")
    _,event,fp,staged,receipt=max(done,key=lambda x:x[0])
    if mode=="apply": require(event==sys.argv[6],"EVENT_CHANGED")
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
        print(event)
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
    print("RETEST_RESET_PASS:"+str(len(moved)))
try: main()
except Exception as e:
    # Never print film metadata or filesystem path.
    v=str(e)
    print(v if re.fullmatch(r"[A-Z0-9_]{3,100}",v) else "RETEST_LOCAL_ERROR")
    sys.exit(1)
'@
# Use a UTF-8 Python FILE, not multiline -c native argument.
$script:phase='PLAN'
$pyFile = Join-Path $env:TEMP ('ttv-retest-'+[Guid]::NewGuid().ToString('N')+'.py')
[IO.File]::WriteAllText($pyFile,$pyCode,[Text.UTF8Encoding]::new($false))
$registry=Join-Path $owner 'app\poc\p2-sub-discovery\p3_p4_ready_registry.py'
$targetHash='7a11638820772d31e0ada488dc8c0410f94c294f1af469d45fc2beb72571a1e6'
$oldHash='d06fb93bc186788c553253e7e1c47bdb5e11f4e091b9a945f36cc2638e444375'
$stage=Join-Path $env:TEMP ('ttv-registry-'+[Guid]::NewGuid().ToString('N')+'.py')
$disabled=$false
$backed=$false
$applied=$false
function Hash([string]$file) {(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()}
try {
    $plan=@(& py -3 -I -B $pyFile $owner $cache $p2 $archives plan 2>$null)
    if($LASTEXITCODE -ne 0 -or $plan.Count -ne 1 -or [string]$plan[0] -cnotmatch '^[a-f0-9]{32}$') {
        if($plan.Count -eq 1 -and [string]$plan[0] -cmatch '^[A-Z0-9_]{3,100}$'){Hold ([string]$plan[0])}
        Hold 'PLAN_FAILED'
    }
    $eventId=[string]$plan[0]
    $script:phase='STAGE_REGISTRY'
    $installedHash=Hash $registry
    if($installedHash -cnotin @($oldHash,$targetHash)) {
        # Permit only normalized LF equality for Windows checkout.
        $text=[IO.File]::ReadAllText($registry).Replace([string][char]13+[string][char]10,[string][char]10)
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes($text)
        $normalized=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        if($normalized -cnotin @($oldHash,$targetHash)){Hold 'REGISTRY_BASELINE_DRIFT'}
    }
    Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/a66d9464c4f73878e5292dd685002878ecc3720a/poc/p2-sub-discovery/p3_p4_ready_registry.py' -OutFile $stage -TimeoutSec 30
    if((Hash $stage) -cne $targetHash){Hold 'REGISTRY_STAGE_HASH'}
    $script:phase='DISABLE_OWNER'
    AssertIdle
    Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    $disabled=$true
    $script:phase='STOP_SCHEDULED_TASK'
    # A task may finish between preflight and Stop-ScheduledTask.
    if (@(OwnerWorkers).Count -gt 0) {
        try { Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop }
        catch {
            if ([string](OwnerTask).State -ne 'Disabled') { throw }
            # Disabled task + scoped worker termination below is authoritative.
        }
    }
    StopVerifiedWorkers
    AssertIdle
    $script:phase='RESET_CHECKPOINT'
    $done=@(& py -3 -I -B $pyFile $owner $cache $p2 $archives apply $eventId 2>$null)
    if($LASTEXITCODE -ne 0 -or $done.Count -ne 1 -or [string]$done[0] -cnotmatch '^RETEST_RESET_PASS:([0-3])$'){
        if($done.Count -eq 1 -and [string]$done[0] -cmatch '^[A-Z0-9_]{3,100}$'){Hold ([string]$done[0])}
        Hold 'RESET_FAILED'
    }
    $script:jobCount=[int]$Matches[1]
    $script:phase='APPLY_REGISTRY'
    if((Hash $registry) -cne $installedHash){Hold 'REGISTRY_CHANGED'}
    if($installedHash -cne $targetHash){
        $backup=Join-Path $archives ('registry-before-'+[Guid]::NewGuid().ToString('N')+'.py')
        [IO.File]::Copy($registry,$backup,$false)
        if((Hash $backup) -cne $installedHash){Hold 'REGISTRY_BACKUP_HASH'}
        $backed=$true
        [IO.File]::Copy($stage,$registry,$true)
        $applied=$true
    }
    if((Hash $registry) -cne $targetHash){Hold 'REGISTRY_INSTALL_HASH'}
    $script:registryState='EXACT_HASH'
    $script:phase='START_OWNER'
    StartOwner $oldPid
    $disabled=$false
    $script:phase='DONE'
    Report 'SUCCESS' 'NONE'
} catch {
    if($disabled -and @(OwnerWorkers).Count -eq 0){
        try {
            if($applied -and $backed){[IO.File]::Copy($backup,$registry,$true);$script:registryState='ROLLED_BACK'}
            AssertIdle
            StartOwner $oldPid
        } catch {}
    }
    if(-not (Test-Path -LiteralPath $receiptPath)){
        $err=[string]$_.FullyQualifiedErrorId
        $reason=if($err -match 'NoProcessFound|ProcessCommandException'){'PROCESS_EXIT_RACE'} elseif($err -match 'CimException|ScheduledTask'){'TASK_OR_CIM_ERROR'} elseif($err -match 'UnauthorizedAccess|AccessDenied'){'ACCESS_DENIED'} elseif($err -match 'VariableNotWritable'){'VARIABLE_COLLISION'} else {'UNEXPECTED_EXCEPTION'}
        Report 'HOLD' $reason
    }
    throw
} finally {
    Remove-Item -LiteralPath $pyFile,$stage -Force -ErrorAction SilentlyContinue
}
