# Approved G1 full-film size hotfix. Exact 12 Python modules, backups and one proven event requeue.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$app=Join-Path $owner 'app'
$taskName='TorrentTV-Vietsub-OwnerAgent'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$source='b0ee241f0f3873d017642ca952830941ef20148b'
$stage=Join-Path $owner ('staged-releases\flat-limit-'+$rq.nonce)
function Hash([string]$p){$i=Get-Item -LiteralPath $p -Force;if($i.PSIsContainer -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'FILE_INVALID'};(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
function Task{
 $t=Get-ScheduledTask -TaskName $taskName -TaskPath '\'
 $s=[string]$t.Principal.UserId
 if($s -notmatch '^S-\d'){$s=([Security.Principal.NTAccount]::new($s).Translate([Security.Principal.SecurityIdentifier])).Value}
 if($s -cne $sid -or [string]$t.Principal.LogonType -ine 'Interactive' -or @($t.Actions).Count -ne 1 -or [string]$t.Actions[0].Arguments -notmatch 'start-owner-session-agent\.ps1'){throw 'TASK_IDENTITY'}
 $t
}
function Workers{
 $paths=@((Join-Path $app 'poc\p2-sub-discovery\owner_p3_p4_entrypoint.py'),(Join-Path $app 'poc\p2-sub-discovery\owner_session_bridge.py'))
 foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe' OR Name='py.exe'")){
   if([string]$p.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'){continue}
   $matches=@($paths|Where-Object{([string]$p.CommandLine).IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0})
   $who=Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid
   if($matches.Count -ne 1 -or $who.ReturnValue -ne 0 -or $who.Sid -cne $sid -or -not $p.CreationDate){throw 'WORKER_IDENTITY'}
   $p
 }
}
function Ready([long]$old,[long]$since){
 try{
   $h=Get-Content -LiteralPath (Join-Path $owner 'agent-health.json') -Raw|ConvertFrom-Json
   $age=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-[long]$h.observed_utc_epoch
   if($h.schema -cne 'TTV-OWNER-AGENT-HEALTH-V1' -or $h.state -cne 'READY' -or $age -lt 0 -or $age -gt 30 -or [long]$h.pid -eq $old -or [long]$h.observed_utc_epoch -lt $since){return 0}
   if(@(Workers|Where-Object{[long]$_.ProcessId -eq [long]$h.pid}).Count -ne 1){return 0}
   return [long]$h.pid
 }catch{return 0}
}

$files=@(
 @{rel='poc/p2-aisub/cue_pipeline.py';old='cf6e55625dc1dc7757f5971f6dfb2dd283175da9';new='1198cbbdba73f31c6f7fd1ad1f8dd03edb72baea'},
 @{rel='poc/p2-aisub/progressive_handoff.py';old='fa160224953486e8edf9c662546ed6debb814c95';new='b95940d6b6b09427bb0e28e785b44f63bc700814'},
 @{rel='poc/p2-aisub/assumed_source_handoff.py';old='386645aabba038139c0304aa46cd9e538eecdaf9';new='f85eca58fff61831125aec553451815c546ac052'},
 @{rel='poc/p2-sub-discovery/opensubtitles.py';old='b6e4919170c09e306db65f631c1e65949768b297';new='bc21e5dc8e9802e73cf6208e81871065ba9effc8'},
 @{rel='poc/p2-sub-discovery/automatic_vietsub_flow.py';old='5ae5b48da30e19192972b263a0844873500e185d';new='9aec6273dd230dcf794d1e2c18fc727998f3d93d'},
 @{rel='poc/p2-sub-discovery/dual_subtitle_catalog.py';old='2e70090ff6bc2b252ebe8381acdf89a9edc31e0c';new='0445ed05998f2b0fdd04eea5817de9e4360c3919'},
 @{rel='poc/p2-sub-discovery/p3_p4_ready_registry.py';old='e4eca0af41264dec07173018e3605c321a745f2b';new='ce4861270985b472b99f68b1708a5a3a0d7062fb'},
 @{rel='poc/p2-aisub/verified_vietsub_ready.py';old='0e9fe95b64f14465d48b627e7b936fcba04bc793';new='31bd2b6744f7201e3cf5cbcde53a4dffe7967771'},
 @{rel='poc/p2-aisub/revision_delivery.py';old='039805c06b6f38910ef650de49b345f39739539c';new='e92432bf86cb4c53a296ff54149be5f5f091b858'},
 @{rel='poc/p2-aisub/lan_revision_feed.py';old='a7a81bcb18ede01d51fd6b0694d1073b9d9956a4';new='59f8868890fdc830bcb80661a9ef597b1eae5569'},
 @{rel='poc/p2-sub-discovery/owner_session_bridge.py';old='a3305ff2ef6a926a49d6f42eac6ba461b0775aa6';new='6c0d14c66e401f5cdb9ac0ccd2974208355b167f'},
 @{rel='poc/p2-sub-discovery/agy_v13_browser_evidence.py';old='1479fb0c1d26d624ba210cfe1492aaedc0b8add8';new='d9a16af5f508ec07020ae8d9a493339b64120f9e'}
)
$pre=@'
import hashlib, json, pathlib, re, sys, time
root=pathlib.Path(sys.argv[1]); base=root.parent; inbox=root/"inbox"
sys.path[:0]=[str(root/"app/poc"/p) for p in ("p2-sub-discovery","p2-aisub","p3-vietsub-trigger")]
from owner_session_bridge import _authorized_selection, _BACKGROUND_SCHEMA, _SESSION_SCHEMA
from cached_en_direct_handoff import CachedEnReceipt,prepare_local_translation_source
from automatic_lean120_worker import AutomaticLean120Worker,_json_bytes
from lean120_api import load_profile
from progressive_handoff import ProgressiveSubtitleSession
from dual_subtitle_catalog import DualSubtitleCatalog
from cue_pipeline import apply_translations
def read(p,cap=2*1024*1024):
    if p.is_symlink() or not p.is_file() or not 0<p.stat().st_size<=cap:raise ValueError()
    return json.loads(p.read_bytes())
def require(ok):
    if not ok:raise ValueError()
stage='HEALTH'
try:
    health=read(root/"agent-health.json",512)
    require(health["state"]=="READY" and 0<=time.time()-health["observed_utc_epoch"]<=30)
    target="347fc1e23e9b0b24fa8609caf6b3f91eca0f65cca78a432bbd3fc49dfd899f4f"
    stage='EVENT'
    events=[p for p in inbox.glob("event-*.blocked") if hashlib.sha256(p.stem.removeprefix("event-").encode()).hexdigest()==target]
    if len(events)!=1:
        print("LIMIT_AUDIT_TARGET_MISSING");sys.exit(0)
    ev=read(events[0],4096);eid=ev["event_id"];fp=ev["source_fingerprint"]
    require(events[0].name=="event-"+eid+".blocked" and hashlib.sha256(eid.encode()).hexdigest()==target)
    require(ev["schema"] in (_BACKGROUND_SCHEMA,_SESSION_SCHEMA) and re.fullmatch(r"[a-f0-9]{64}",fp) is not None)
    if ev["schema"]==_BACKGROUND_SCHEMA:
        _authorized_selection(ev["authorized_selection"],fp,ev["tv_session_id"])
    stage='CLAIM'
    require((inbox/("claim-"+eid)).read_bytes()==b"CLAIMED_DO_NOT_AUTO_REPLAY\n")
    # Local console capture may differ from the user-supplied traceback.
    # Establish the failed boundary directly by replaying only retained bytes.
    stage='SOURCE'
    cache=base/"subtitle-trials"; state=base/"P2/auto-lean120-state"
    # Resolve exact cache index without calling any source acquirer.
    indexes=[cache/(".dual-source-native-v13-"+fp+"-ai_en.json"),cache/(".dual-source-"+fp+"-ai_en.json")]
    present=[p for p in indexes if p.is_file()]
    require(len(present)>=1)
    index=present[0]; row=read(index,512)
    receipt=DualSubtitleCatalog(cache)._file(row,"ai_en")
    source=prepare_local_translation_source(CachedEnReceipt(receipt.file,receipt.sha256,receipt.cues),private_root=cache)
    stage='JOB'
    worker=AutomaticLean120Worker(state_root=state,profile=load_profile(root/"app/poc/p2-aisub/translator_profile.json"),glossary={},first_window_cues=50,preserve_hydrogen_jobs=True)
    job=worker.job_fingerprint(source); folder=state/job
    require(folder.is_dir() and not folder.is_symlink())
    session=worker.progressive_session(source)
    stage='CHECKPOINT'
    prefix=0; rev=None
    for w in session.windows:
        cp=folder/f"batch-{w.number:04d}.json"
        if not cp.is_file():break
        d=read(cp)
        require(d["schema"]=="TTV-P2-LEAN120-CHECKPOINT-V1" and d["job"]==job and d["version"]==w.number and [v["id"] for v in d["translations"]]==list(w.ids))
        values={v["id"]:v["vi"] for v in d["translations"]}
        rev=session.commit(w,values,expected_version=w.number-1,source_sha256=source.source_sha256,media_key=source.media_key)
        require(rev.sha256==d["payload_sha256"]);prefix=w.number
    require(prefix>0 and len(list(folder.glob("batch-*.json")))==prefix and prefix<len(session.windows))
    stage='RESULT'
    ready=0; ambiguous=0
    for m in folder.glob("batch-*.inflight"):
        match=re.fullmatch(r"batch-(\d{4})\.inflight",m.name);require(match is not None)
        n=int(match[1]);require(prefix<n<=len(session.windows))
        md=read(m,4096); require(md=={"schema":"TTV-P2-INFLIGHT-V1","job":job,"version":n})
        w=session.windows[n-1]; p=folder/f"result-{n:04d}.json"
        if not p.is_file():ambiguous+=1;continue
        d=read(p); require(d["schema"]=="TTV-P2-LEAN120-RESULT-V1" and d["job"]==job and d["version"]==n and [v["id"] for v in d["translations"]]==list(w.ids))
        require(hashlib.sha256(_json_bytes(d["translations"])).hexdigest()==d["sha256"])
        apply_translations(w.target,{str(v["id"]):v["vi"] for v in d["translations"]});ready+=1
    stage='REPLAY'
    if ready>0:
        import progressive_handoff as ph
        w=session.next_window()
        d=read(folder/f"result-{w.number:04d}.json")
        values={v["id"]:v["vi"] for v in d["translations"]}
        old_limit=ph.MAX_TV_BYTES
        try:
            session.commit(w,values,expected_version=prefix,source_sha256=source.source_sha256,media_key=source.media_key)
        except ValueError as exc:
            require(str(exc)=="TV_SUBTITLE_SIZE_LIMIT")
        else:
            raise ValueError("OLD_LIMIT_NOT_REPRODUCED")
        ph.MAX_TV_BYTES=4*1024*1024
        try:
            new=session.commit(w,values,expected_version=prefix,source_sha256=source.source_sha256,media_key=source.media_key)
            require(new.version==prefix+1 and len(new.payload)>old_limit)
            verified_bytes=len(new.payload)
        finally:
            ph.MAX_TV_BYTES=old_limit
    else:
        verified_bytes=0
    stage='PINS'
    pins={"poc/p2-aisub/cue_pipeline.py":"cf6e55625dc1dc7757f5971f6dfb2dd283175da9","poc/p2-aisub/progressive_handoff.py":"fa160224953486e8edf9c662546ed6debb814c95","poc/p2-aisub/assumed_source_handoff.py":"386645aabba038139c0304aa46cd9e538eecdaf9","poc/p2-sub-discovery/opensubtitles.py":"b6e4919170c09e306db65f631c1e65949768b297","poc/p2-sub-discovery/automatic_vietsub_flow.py":"5ae5b48da30e19192972b263a0844873500e185d","poc/p2-sub-discovery/dual_subtitle_catalog.py":"2e70090ff6bc2b252ebe8381acdf89a9edc31e0c","poc/p2-sub-discovery/p3_p4_ready_registry.py":"e4eca0af41264dec07173018e3605c321a745f2b","poc/p2-aisub/verified_vietsub_ready.py":"0e9fe95b64f14465d48b627e7b936fcba04bc793","poc/p2-aisub/revision_delivery.py":"039805c06b6f38910ef650de49b345f39739539c","poc/p2-aisub/lan_revision_feed.py":"a7a81bcb18ede01d51fd6b0694d1073b9d9956a4","poc/p2-sub-discovery/owner_session_bridge.py":"a3305ff2ef6a926a49d6f42eac6ba461b0775aa6","poc/p2-sub-discovery/agy_v13_browser_evidence.py":"1479fb0c1d26d624ba210cfe1492aaedc0b8add8"}
    match_count=0
    for rel,digest in pins.items():
        b=(root/'app'/rel).read_bytes().replace(b'\r\n',b'\n')
        if hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()==digest:match_count+=1
    locks=sum(1 for p in state.glob("*/active.lock") if p.is_file())
    pending=sum(1 for p in inbox.glob("event-*.json") if p.is_file())
    print(f"LIMIT_AUDIT_C{source.cue_count}_B{prefix}_T{len(session.windows)}_R{ready}_U{ambiguous}_L{locks}_Q{pending}_M{match_count}_S{verified_bytes}")
except Exception:
    print("LIMIT_AUDIT_HOLD_"+stage)
'@
$post=@'
import hashlib, json, pathlib, re, sys, time
root=pathlib.Path(sys.argv[1]); base=root.parent; inbox=root/"inbox"
sys.path[:0]=[str(root/"app/poc"/p) for p in ("p2-sub-discovery","p2-aisub","p3-vietsub-trigger")]
from owner_session_bridge import _authorized_selection, _BACKGROUND_SCHEMA, _SESSION_SCHEMA
from cached_en_direct_handoff import CachedEnReceipt,prepare_local_translation_source
from automatic_lean120_worker import AutomaticLean120Worker,_json_bytes
from lean120_api import load_profile
from progressive_handoff import ProgressiveSubtitleSession
from dual_subtitle_catalog import DualSubtitleCatalog
from cue_pipeline import apply_translations
def read(p,cap=2*1024*1024):
    if p.is_symlink() or not p.is_file() or not 0<p.stat().st_size<=cap:raise ValueError()
    return json.loads(p.read_bytes())
def require(ok):
    if not ok:raise ValueError()
stage='HEALTH'
try:
    health=read(root/"agent-health.json",512)
    require(health["state"]=="READY" and 0<=time.time()-health["observed_utc_epoch"]<=30)
    target="347fc1e23e9b0b24fa8609caf6b3f91eca0f65cca78a432bbd3fc49dfd899f4f"
    stage='EVENT'
    events=[p for p in inbox.glob("event-*.blocked") if hashlib.sha256(p.stem.removeprefix("event-").encode()).hexdigest()==target]
    if len(events)!=1:
        print("LIMIT_AUDIT_TARGET_MISSING");sys.exit(0)
    ev=read(events[0],4096);eid=ev["event_id"];fp=ev["source_fingerprint"]
    require(events[0].name=="event-"+eid+".blocked" and hashlib.sha256(eid.encode()).hexdigest()==target)
    require(ev["schema"] in (_BACKGROUND_SCHEMA,_SESSION_SCHEMA) and re.fullmatch(r"[a-f0-9]{64}",fp) is not None)
    if ev["schema"]==_BACKGROUND_SCHEMA:
        _authorized_selection(ev["authorized_selection"],fp,ev["tv_session_id"])
    stage='CLAIM'
    require((inbox/("claim-"+eid)).read_bytes()==b"CLAIMED_DO_NOT_AUTO_REPLAY\n")
    # Local console capture may differ from the user-supplied traceback.
    # Establish the failed boundary directly by replaying only retained bytes.
    stage='SOURCE'
    cache=base/"subtitle-trials"; state=base/"P2/auto-lean120-state"
    # Resolve exact cache index without calling any source acquirer.
    indexes=[cache/(".dual-source-native-v13-"+fp+"-ai_en.json"),cache/(".dual-source-"+fp+"-ai_en.json")]
    present=[p for p in indexes if p.is_file()]
    require(len(present)>=1)
    index=present[0]; row=read(index,512)
    receipt=DualSubtitleCatalog(cache)._file(row,"ai_en")
    source=prepare_local_translation_source(CachedEnReceipt(receipt.file,receipt.sha256,receipt.cues),private_root=cache)
    stage='JOB'
    worker=AutomaticLean120Worker(state_root=state,profile=load_profile(root/"app/poc/p2-aisub/translator_profile.json"),glossary={},first_window_cues=50,preserve_hydrogen_jobs=True)
    job=worker.job_fingerprint(source); folder=state/job
    require(folder.is_dir() and not folder.is_symlink())
    session=worker.progressive_session(source)
    stage='CHECKPOINT'
    prefix=0; rev=None
    for w in session.windows:
        cp=folder/f"batch-{w.number:04d}.json"
        if not cp.is_file():break
        d=read(cp)
        require(d["schema"]=="TTV-P2-LEAN120-CHECKPOINT-V1" and d["job"]==job and d["version"]==w.number and [v["id"] for v in d["translations"]]==list(w.ids))
        values={v["id"]:v["vi"] for v in d["translations"]}
        rev=session.commit(w,values,expected_version=w.number-1,source_sha256=source.source_sha256,media_key=source.media_key)
        require(rev.sha256==d["payload_sha256"]);prefix=w.number
    require(prefix>0 and len(list(folder.glob("batch-*.json")))==prefix and prefix<len(session.windows))
    stage='RESULT'
    ready=0; ambiguous=0
    for m in folder.glob("batch-*.inflight"):
        match=re.fullmatch(r"batch-(\d{4})\.inflight",m.name);require(match is not None)
        n=int(match[1]);require(prefix<n<=len(session.windows))
        md=read(m,4096); require(md=={"schema":"TTV-P2-INFLIGHT-V1","job":job,"version":n})
        w=session.windows[n-1]; p=folder/f"result-{n:04d}.json"
        if not p.is_file():ambiguous+=1;continue
        d=read(p); require(d["schema"]=="TTV-P2-LEAN120-RESULT-V1" and d["job"]==job and d["version"]==n and [v["id"] for v in d["translations"]]==list(w.ids))
        require(hashlib.sha256(_json_bytes(d["translations"])).hexdigest()==d["sha256"])
        apply_translations(w.target,{str(v["id"]):v["vi"] for v in d["translations"]});ready+=1
    stage='REPLAY'
    require(prefix==27 and len(session.windows)==29 and ready==1 and ambiguous==0 and source.cue_count==3381)
    import progressive_handoff as ph
    from cue_pipeline import MAX_BYTES,MAX_CUES
    from lan_revision_feed import MAX_WIRE_BYTES
    require(ph.MAX_TV_BYTES==MAX_BYTES==4*1024*1024 and MAX_CUES==20000 and MAX_WIRE_BYTES==6*1024*1024)
    w=session.next_window()
    d=read(folder/f"result-{w.number:04d}.json")
    values={v["id"]:v["vi"] for v in d["translations"]}
    new=session.commit(w,values,expected_version=prefix,source_sha256=source.source_sha256,media_key=source.media_key)
    require(new.version==28 and len(new.payload)==270206)
    verified_bytes=len(new.payload)
    stage='PINS'
    pins={"poc/p2-aisub/cue_pipeline.py":"1198cbbdba73f31c6f7fd1ad1f8dd03edb72baea","poc/p2-aisub/progressive_handoff.py":"b95940d6b6b09427bb0e28e785b44f63bc700814","poc/p2-aisub/assumed_source_handoff.py":"f85eca58fff61831125aec553451815c546ac052","poc/p2-sub-discovery/opensubtitles.py":"bc21e5dc8e9802e73cf6208e81871065ba9effc8","poc/p2-sub-discovery/automatic_vietsub_flow.py":"9aec6273dd230dcf794d1e2c18fc727998f3d93d","poc/p2-sub-discovery/dual_subtitle_catalog.py":"0445ed05998f2b0fdd04eea5817de9e4360c3919","poc/p2-sub-discovery/p3_p4_ready_registry.py":"ce4861270985b472b99f68b1708a5a3a0d7062fb","poc/p2-aisub/verified_vietsub_ready.py":"31bd2b6744f7201e3cf5cbcde53a4dffe7967771","poc/p2-aisub/revision_delivery.py":"e92432bf86cb4c53a296ff54149be5f5f091b858","poc/p2-aisub/lan_revision_feed.py":"59f8868890fdc830bcb80661a9ef597b1eae5569","poc/p2-sub-discovery/owner_session_bridge.py":"6c0d14c66e401f5cdb9ac0ccd2974208355b167f","poc/p2-sub-discovery/agy_v13_browser_evidence.py":"d9a16af5f508ec07020ae8d9a493339b64120f9e"}
    match_count=0
    for rel,digest in pins.items():
        b=(root/'app'/rel).read_bytes().replace(b'\r\n',b'\n')
        if hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()==digest:match_count+=1
    locks=sum(1 for p in state.glob("*/active.lock") if p.is_file())
    pending=sum(1 for p in inbox.glob("event-*.json") if p.is_file())
    require(match_count==len(pins) and locks==0 and pending==0)
    stage='NATIVE_EN'
    # Background authorization must survive TV exit. Never replay a legacy stale session.
    require(ev["schema"]==_BACKGROUND_SCHEMA)
    coords=_authorized_selection(ev["authorized_selection"],fp,ev["tv_session_id"])
    from matcher import Media
    media=Media(coords["server_id"],coords["torrent_hash"],coords["file_index"],ev["selected_video_filename"])
    native=DualSubtitleCatalog(cache,native=True).read(media,fp,"ai_en")
    require(native is not None and native.release_matched and native.sha256==source.source_sha256 and native.cues==source.cue_count)
    stage='REQUEUE'
    import os
    stage_dir=pathlib.Path(sys.argv[2])
    blocked=events[0]; claim=inbox/("claim-"+eid); queued=inbox/("event-"+eid+".json")
    require(not queued.exists() and not queued.is_symlink() and not claim.is_symlink())
    require(not any(inbox.glob("event-*.json")) and not any(state.glob("*/active.lock")))
    require(claim.read_bytes()==b"CLAIMED_DO_NOT_AUTO_REPLAY\n")
    backup=stage_dir/"blocked-event.backup"; archived=stage_dir/"blocked-claim.backup"
    with backup.open("xb") as f:
        f.write(blocked.read_bytes());f.flush();os.fsync(f.fileno())
    require(not archived.exists())
    os.replace(claim,archived)
    try:
        os.replace(blocked,queued)
    except OSError:
        os.replace(archived,claim)
        raise
    print("LIMIT_REQUEUE_B28_RETAINED_B29_PENDING")
except Exception:
    print("LIMIT_REQUEUE_HOLD_"+stage)
'@
$verify='import sys,pathlib,hashlib; b=pathlib.Path(sys.argv[1]).read_bytes().replace(b"\r\n",b"\n"); assert hashlib.sha1(b"blob "+str(len(b)).encode()+b"\0"+b).hexdigest()==sys.argv[2]; compile(b,"candidate","exec"); print("VERIFIED")'
function Verify([string]$path,[string]$expected){
 $o=@(& py -3 -I -B -c $verify $path $expected 2>&1)
 if($LASTEXITCODE -ne 0 -or $o.Count -ne 1 -or [string]$o[0] -cne 'VERIFIED'){throw 'BLOB_VERIFY'}
}
function Confirm-Audit{
 $o=@(& py -3 -I -B -c $pre $owner 2>$null)
 if($LASTEXITCODE -ne 0 -or $o.Count -ne 1 -or [string]$o[0] -cne 'LIMIT_AUDIT_C3381_B27_T29_R1_U0_L0_Q0_M12_S270206'){throw 'AUDIT_CHANGED'}
}
$replaced=@();$disabled=$false;$startAttempted=$false;$phase='PREFLIGHT';$code='LIMIT_INSTALL_HOLD_PREFLIGHT'
try {
 if([string](Task).State -cne 'Running'){throw 'TASK_NOT_RUNNING'}
 $oldPid=Ready 0 0
 if($oldPid -le 0){throw 'HEARTBEAT'}
 Confirm-Audit
 $phase='STAGE'
 New-Item -ItemType Directory -Path $stage -ErrorAction Stop|Out-Null
 foreach($f in $files){
   $name=[IO.Path]::GetFileName($f.rel)
   $f.dst=Join-Path $app $f.rel
   $f.candidate=Join-Path $stage $name
   $f.backup=Join-Path $stage ('prior-'+$name)
   Verify $f.dst $f.old
   $f.prior=Hash $f.dst
   Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/'+$source+'/'+$f.rel) -OutFile $f.candidate -TimeoutSec 30
   Verify $f.candidate $f.new
   $f.target=Hash $f.candidate
   [IO.File]::Copy($f.dst,$f.backup,$false)
   if((Hash $f.backup) -cne $f.prior){throw 'BACKUP'}
 }
 $phase='QUIESCENCE'
 Confirm-Audit
 if((Ready 0 0) -ne $oldPid -or [string](Task).State -cne 'Running'){throw 'OWNER_CHANGED'}
 Disable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
 $disabled=$true
 # Recheck after disabling future scheduled starts; do not stop new work.
 Confirm-Audit
 $phase='STOP'
 try{Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop}catch{}
 for($i=0;$i -lt 3 -and @(Workers).Count -gt 0;$i++){Start-Sleep -Milliseconds 300}
 foreach($w in @(Workers)){
   if([string](Task).State -cne 'Disabled'){throw 'STOP_IDENTITY'}
   $live=@(Workers|Where-Object{[int]$_.ProcessId -eq [int]$w.ProcessId})
   if($live.Count -eq 0){continue}
   if($live.Count -ne 1 -or $live[0].CreationDate -ne $w.CreationDate -or $live[0].CommandLine -cne $w.CommandLine){throw 'WORKER_CHANGED'}
   Stop-Process -Id ([int]$w.ProcessId) -Force -ErrorAction Stop
 }
 if(@(Workers).Count -gt 0 -or [string](Task).State -cne 'Disabled'){throw 'STOP_UNVERIFIED'}
 $state=Join-Path (Split-Path $owner -Parent) 'P2\auto-lean120-state'
 $inbox=Join-Path $owner 'inbox'
 if(@(Get-ChildItem -LiteralPath $state -Recurse -File -Filter 'active.lock').Count -ne 0 -or @(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json').Count -ne 0){throw 'NEW_WORK_OBSERVED'}
 $phase='REPLACE'
 foreach($f in $files){
   if((Hash $f.dst) -cne $f.prior){throw 'BASE_DRIFT'}
   $tmp=$f.dst+'.hotfix-'+$rq.nonce
   [IO.File]::Copy($f.candidate,$tmp,$false)
   if((Hash $tmp) -cne $f.target){throw 'TEMP_HASH'}
   [IO.File]::Replace($tmp,$f.dst,(Join-Path $stage ('displaced-'+[IO.Path]::GetFileName($f.rel))))
   $replaced+=@($f)
   if((Hash $f.dst) -cne $f.target){throw 'POST_HASH'}
 }
 $phase='IMPORT'
 $import='import sys,pathlib;root=pathlib.Path(sys.argv[1]);sys.path[:0]=[str(root/"poc"/p) for p in ("p2-sub-discovery","p2-aisub","p3-vietsub-trigger")];from cue_pipeline import MAX_BYTES,MAX_CUES;from progressive_handoff import MAX_TV_BYTES;from lan_revision_feed import MAX_WIRE_BYTES;from opensubtitles import MAX_SUBTITLE_BYTES;import owner_session_bridge,owner_r2_progressive_registry,agy_v13_browser_evidence;assert MAX_BYTES==MAX_TV_BYTES==MAX_SUBTITLE_BYTES==4194304 and MAX_CUES==20000 and MAX_WIRE_BYTES==6291456;print("IMPORTED")'
 $o=@(& py -3 -I -B -c $import $app 2>&1)
 if($LASTEXITCODE -ne 0 -or $o.Count -ne 1 -or [string]$o[0] -cne 'IMPORTED'){throw 'IMPORT'}
 $phase='START';$since=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-1
 Enable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
 $disabled=$false;$startAttempted=$true
 Start-ScheduledTask -TaskName $taskName -TaskPath '\'
 $newPid=0
 for($i=0;$i -lt 30;$i++){Start-Sleep -Seconds 1;if([string](Task).State -ceq 'Running'){$newPid=Ready $oldPid $since;if($newPid -gt 0){break}}}
 if($newPid -le 0){throw 'FRESH_OWNER'}
 foreach($f in $files){if((Hash $f.dst) -cne $f.target){throw 'POST_HASH'}}
 $phase='RECOVERY'
 $o=@(& py -3 -I -B -c $post $owner $stage 2>$null)
 $code='LIMIT_INSTALL_PASS_RECOVERY_READ_UNAVAILABLE'
 if($LASTEXITCODE -eq 0 -and $o.Count -eq 1 -and [string]$o[0] -cmatch '^LIMIT_REQUEUE_[A-Z0-9_]{3,60}$'){
   $code='LIMIT_INSTALL_PASS_'+([string]$o[0]).Substring(6)
 }
}catch{
 $code='LIMIT_INSTALL_HOLD_'+$phase
 if(-not $startAttempted -and $disabled){
   try{
     if(@(Workers).Count -gt 0){
       if($replaced.Count -ne 0){throw 'ROLLBACK_UNSAFE'}
       Enable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
     }else{
       foreach($f in $replaced){
         if((Hash $f.backup) -cne $f.prior){throw 'ROLLBACK_HASH'}
         $tmp=$f.dst+'.rollback-'+$rq.nonce
         [IO.File]::Copy($f.backup,$tmp,$false)
         [IO.File]::Replace($tmp,$f.dst,(Join-Path $stage ('failed-'+[IO.Path]::GetFileName($f.rel))))
         if((Hash $f.dst) -cne $f.prior){throw 'ROLLBACK_HASH'}
       }
       Enable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
       Start-ScheduledTask -TaskName $taskName -TaskPath '\'
     }
     $code+='_OWNER_REENABLED'
   }catch{$code='LIMIT_INSTALL_ROLLBACK_HOLD'}
 }
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
