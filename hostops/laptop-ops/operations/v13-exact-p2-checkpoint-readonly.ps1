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
    matches=[]
    for job in (cache/".native-v13").iterdir():
        if not re.fullmatch("[0-9a-f]{64}",job.name) or not (job/"verified.json").is_file() or not (job/"terminal.json").is_file():continue
        v=read(job/"verified.json",4096);t=read(job/"terminal.json",4096)
        if v.get("cues")==1578 and t.get("reason")=="AGY_EN_RELEASE_COMPARISON_MISSING" and t.get("status")=="SOURCE_REJECTED":matches.append(job)
    if len(matches)!=1:print("R_EN_UNBOUND");sys.exit(0)
    job=matches[0];media=Media(**read(job/"evidence.json")["media"])
    _,asset=_retained_verified(job,media)
    idx=read(cache/(".auto-source-"+job.name+".json"),4096)
    if idx.get("sha256")!=asset.sha256 or idx.get("cues")!=1578 or not re.fullmatch("[0-9a-f]{64}\\.srt",idx.get("file","")):raise ValueError()
    source=prepare_local_translation_source(CachedEnReceipt(cache/idx["file"],asset.sha256,1578),private_root=cache)
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
    final=folder/"vi-final.srt";complete=int(count==1578 and final.is_file() and session.revision is not None and hashlib.sha256(final.read_bytes()).hexdigest()==session.revision.sha256)
    # Same PID fresh P3 snapshot. This is readiness context, not an ACK.
    p3="U"
    for p in root.glob("*.json"):
        if p.stat().st_size>16384:continue
        if not ("diag" in p.name.lower() or "p3" in p.name.lower()):continue
        try:
            d=read(p,16384)
            if d.get("pid")==h["pid"] and 0<=time.time()-d.get("observed_utc_epoch",0)<=5:
                p3={"FRESH_REQUESTED":"R","FRESH_OTHER":"O","FRESH_OFF":"F","STALE":"S"}.get(d.get("p3"),p3)
        except Exception:pass
    print("R_P2_C"+str(count)+"_B"+str(prefix)+"T"+str(len(session.windows))+"_I"+str(inflight)+"_Q"+str(ready)+"_F"+str(complete)+"_X"+str(bad)+"_L"+str(last)+"_M"+mode.upper()+"_P"+p3)

except Exception:
    print("R_READ_UNAVAILABLE")
'@
$lines=@(& py -3 -I -B -c $py $owner 2>$null)
$code='R_READ_UNAVAILABLE'
if($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and [string]$lines[0] -cmatch '^R_(READ_UNAVAILABLE|[A-Z0-9_]{3,86})$'){$code=[string]$lines[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
