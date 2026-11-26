# Owner read-only current request diagnostic; only bounded, fixed enum evidence leaves Owner.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$py=@'
import pathlib,sys,json,re,time
root=pathlib.Path(sys.argv[1])
def load(p):
    if p.is_symlink() or not p.is_file() or not 0<p.stat().st_size<=4096:raise ValueError()
    return json.loads(p.read_text(encoding="utf-8-sig"))
try:
    h=load(root/"agent-health.json")
    if h.get("state")!="READY" or not 0<=time.time()-h["observed_utc_epoch"]<=30:raise ValueError()
    import hashlib
    cache=root.parent/"subtitle-trials";state=root.parent/"P2/auto-lean120-state"
    sys.path[:0]=[str(root/"app/poc"/x) for x in ("p2-sub-discovery","p2-aisub","p3-vietsub-trigger")]
    from agy_v13_native_producer import _retained_verified
    from matcher import Media
    from cached_en_direct_handoff import CachedEnReceipt,prepare_local_translation_source
    from automatic_lean120_worker import AutomaticLean120Worker
    from lean120_api import ModelProfile
    def read(p,limit=16777216):
        if p.is_symlink() or not p.is_file() or not 0<p.stat().st_size<=limit:raise ValueError()
        return json.loads(p.read_text(encoding="utf-8-sig"))
    import ast
    inbox=root/"inbox"
    log=root/"diagnostics/owner-full.log"
    with log.open("rb") as f:
        size=f.seek(0,2);offset=max(0,size-8388608);f.seek(offset);raw=f.read(8388608)
    if offset:raw=raw.partition(b"\n")[2]
    lines=raw.decode("utf-8","replace").splitlines()
    starts=[i for i,l in enumerate(lines) if re.fullmatch(r"OWNER_FULL_DIAGNOSTICS_STARTED pid="+str(int(h["pid"]))+r" epoch=\d+",l)]
    if not starts:print("R_RE_LOG_UNBOUND");sys.exit(0)
    events=[]
    for l in lines[starts[-1]+1:]:
        m=re.match(r"OWNER_FULL_TRACE 'P2_(EVENT_CLAIMED|EVENT_FINISHED|EVENT_BLOCKED|PREPROVIDER_TRANSIENT)' (\{.*\})$",l)
        if not m:continue
        try:
            t=ast.literal_eval(m.group(2));eid=t.get("event_id")
            if not isinstance(eid,str) or not re.fullmatch(r"[a-f0-9]{32}",eid):continue
            files=[inbox/("event-"+eid+ext) for ext in (".json",".done",".blocked",".review")]
            files=[p for p in files if p.is_file() and not p.is_symlink()]
            if len(files)!=1:continue
            e=read(files[0],65536);name=re.sub(r"[^a-z0-9]+"," ",str(e.get("selected_video_filename","")).lower())
            fp=e.get("source_fingerprint")
            if e.get("event_id")!=eid or not re.search(r"\bresident evil\b",name) or not isinstance(fp,str) or not re.fullmatch(r"[a-f0-9]{64}",fp):continue
            events.append((m.group(1),fp,files[0],eid,e))
        except (ValueError,SyntaxError,OSError,AttributeError):pass
    if not events:print("R_RE_EVENT_UNBOUND");sys.exit(0)
    outcome,fp,event,eid,e=events[-1]
    job=cache/".native-v13"/fp
    if not (job/"verified.json").is_file():print("R_RE_EN_NOT_VERIFIED");sys.exit(0)
    media=Media(**read(job/"evidence.json")["media"])
    if media.filename!=e.get("selected_video_filename"):raise ValueError()
    _,asset=_retained_verified(job,media);total=asset.cues
    idx=read(cache/(".auto-source-"+fp+".json"),4096)
    if idx.get("sha256")!=asset.sha256 or idx.get("cues")!=total or not re.fullmatch("[0-9a-f]{64}\\.srt",idx.get("file","")):raise ValueError()
    source=prepare_local_translation_source(CachedEnReceipt(cache/idx["file"],asset.sha256,total),private_root=cache)
    found=[]
    for mode in ("high","low"):
        w=AutomaticLean120Worker(state_root=state,profile=ModelProfile("antigravity","gemini-4-hydrogen-"+mode,mode),glossary={},first_window_cues=50)
        digest=w.job_fingerprint(source);folder=state/digest
        if folder.is_dir() and not folder.is_symlink():found.append((w,digest,folder,mode))
    if len(found)!=1:print("R_P2_JOB_UNBOUND");sys.exit(0)
    w,digest,folder,mode=found[0];session=w.progressive_session(source)
    count=0;prefix=0;bad=0;last=0
    for window in session.windows:
        cp=folder/("batch-%04d.json"%window.number)
        if not cp.is_file():break
        try:
            d=read(cp,262144)
            if d.get("schema")!="TTV-P2-LEAN120-CHECKPOINT-V1" or d.get("job")!=digest or d.get("version")!=window.number or [x["id"] for x in d["translations"]]!=list(window.ids):raise ValueError()
            revision=session.commit(window,{x["id"]:x["vi"] for x in d["translations"]},expected_version=window.number-1,source_sha256=source.source_sha256,media_key=source.media_key)
            if revision.sha256!=d["payload_sha256"]:raise ValueError()
            count=revision.translated_count;prefix=window.number;last=revision.last_end_ms//1000
        except Exception:bad=1;break
    inflight=sum(1 for p in folder.glob("batch-*.inflight") if p.is_file())
    ready=sum(1 for p in folder.glob("result-*.json") if p.is_file())
    final=folder/"vi-final.srt";complete=int(count==total and final.is_file() and session.revision is not None and hashlib.sha256(final.read_bytes()).hexdigest()==session.revision.sha256)
    # Windows event file creation survives same-volume rename to .done;
    # use original content write mtime, not the directory or log mtime.
    t0=event.stat().st_mtime
    # Provider started is a measured epoch; subsequent stages are durable file write times.
    p=read(job/"provider.started.json",4096).get("started")
    if not isinstance(p,(float,int)):raise ValueError()
    def delta(t):
        return str(round(t-t0)) if t>=t0-1 and t-t0<86400 else "U"
    first=folder/"batch-0001.json"
    stages=[delta(p),delta((job/"download.bin").stat().st_mtime),delta((job/"verified.json").stat().st_mtime),delta(first.stat().st_mtime) if prefix>=1 else "U",delta(final.stat().st_mtime) if complete else "U"]
    print("R_RE_N"+str(total)+"C"+str(count)+"B"+str(prefix)+"T"+str(len(session.windows))+"F"+str(complete)+"X"+str(bad)+"_P"+stages[0]+"A"+stages[1]+"E"+stages[2]+"V"+stages[3]+"Z"+stages[4]+"_M"+mode.upper())

except Exception:
    print("R_READ_UNAVAILABLE")
'@
$lines=@(& py -3 -I -B -c $py $owner 2>$null)
$code='R_READ_UNAVAILABLE'
if($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and [string]$lines[0] -cmatch '^R_(READ_UNAVAILABLE|[A-Z0-9_]{3,86})$'){$code=[string]$lines[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
