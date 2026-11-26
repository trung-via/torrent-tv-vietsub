# Read-only exact failed-event/checkpoint audit. No provider, replay, cache edit or Owner restart.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$py=@'
import hashlib, json, pathlib, re, sys, time
root=pathlib.Path(sys.argv[1]); base=root.parent; inbox=root/"inbox"
sys.path[:0]=[str(root/"app/poc"/p) for p in ("p2-sub-discovery","p2-aisub","p3-vietsub-trigger")]
from owner_session_bridge import _parse_event
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
try:
    health=read(root/"agent-health.json",512)
    require(health["state"]=="READY" and 0<=time.time()-health["observed_utc_epoch"]<=30)
    target="347fc1e23e9b0b24fa8609caf6b3f91eca0f65cca78a432bbd3fc49dfd899f4f"
    events=[p for p in inbox.glob("event-*.blocked") if hashlib.sha256(p.stem.removeprefix("event-").encode()).hexdigest()==target]
    if len(events)!=1:
        print("LIMIT_AUDIT_TARGET_MISSING");sys.exit(0)
    event=_parse_event(events[0]); eid=event.event_id; fp=event.source_fingerprint
    require(event.authorized_selection is not None and fp is not None)
    require((inbox/("claim-"+eid)).read_bytes()==b"CLAIMED_DO_NOT_AUTO_REPLAY\n")
    log=root/"diagnostics/owner-full.log"
    with log.open("rb") as f:
        f.seek(max(0,log.stat().st_size-4*1024*1024)); tail=f.read().decode("utf-8","replace")
    marker="OWNER_FULL_TRACE 'P2_EVENT_BLOCKED'"
    blocks=[part for part in tail.split(marker)[1:] if eid in part.splitlines()[0]]
    require(len(blocks)==1 and "ValueError: TV_SUBTITLE_SIZE_LIMIT" in blocks[0])
    cache=base/"subtitle-trials"; state=base/"P2/auto-lean120-state"
    # Resolve exact cache index without calling any source acquirer.
    indexes=[cache/(".dual-source-native-v13-"+fp+"-ai_en.json"),cache/(".dual-source-"+fp+"-ai_en.json")]
    present=[p for p in indexes if p.is_file()]
    require(len(present)>=1)
    index=present[0]; row=read(index,512)
    receipt=DualSubtitleCatalog(cache)._file(row,"ai_en")
    source=prepare_local_translation_source(CachedEnReceipt(receipt.file,receipt.sha256,receipt.cues),private_root=cache)
    worker=AutomaticLean120Worker(state_root=state,profile=load_profile(root/"app/poc/p2-aisub/translator_profile.json"),glossary={},first_window_cues=50,preserve_hydrogen_jobs=True)
    job=worker.job_fingerprint(source); folder=state/job
    require(folder.is_dir() and not folder.is_symlink())
    session=worker.progressive_session(source)
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
    locks=sum(1 for p in state.glob("*/active.lock") if p.is_file())
    pending=sum(1 for p in inbox.glob("event-*.json") if p.is_file())
    print(f"LIMIT_AUDIT_C{source.cue_count}_B{prefix}_T{len(session.windows)}_R{ready}_U{ambiguous}_L{locks}_Q{pending}")
except Exception:
    print("LIMIT_AUDIT_HOLD_INVALID_OR_CHANGED")
'@
$lines=@(& py -3 -I -B -c $py $root 2>$null)
$code='LIMIT_AUDIT_READ_UNAVAILABLE'
if($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and [string]$lines[0] -cmatch '^LIMIT_AUDIT_[A-Z0-9_]{3,75}$'){$code=[string]$lines[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
