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
    p=root/"diagnostics"/"owner-full.log"
    if p.is_symlink():raise ValueError()
    with p.open("rb") as f:
        n=f.seek(0,2); off=max(0,n-1048576);f.seek(off);raw=f.read(1048576)
    if off:raw=raw.partition(b"\n")[2]
    lines=raw.decode("utf-8","replace").splitlines()
    starts=[i for i,l in enumerate(lines) if re.fullmatch(r"OWNER_FULL_DIAGNOSTICS_STARTED pid="+str(int(h["pid"]))+r" epoch=[0-9]+",l)]
    if not starts:raise ValueError()
    epoch=int(lines[starts[-1]].rsplit("=",1)[1])
    lines=lines[starts[-1]+1:]
    idx=[i for i,l in enumerate(lines) if "OWNER_FULL_TRACE 'P3_SELECTION_ACCEPTED'" in l and "'status': 'DISPATCH'" in l]
    # A recovered event can be claimed before the next TV selection.
    allowed={"V3_TV_READER_UNAVAILABLE","V3_CURRENT_MEDIA_UNAVAILABLE","V3_SERVER_READER_UNAVAILABLE","V3_TV_REFRESH_UNAVAILABLE","AGY_OWNER_PREFLIGHT_UNAVAILABLE"}
    reason="NONE"
    for l in lines:
        if l.startswith("OWNER_BRIDGE_PREPROVIDER_REASON="):
            v=l.split("=",1)[1];reason=v if v in allowed else "OTHER"
    outcome="NONE"
    for l in lines:
        for k,v in (("P2_EVENT_CLAIMED","CLAIMED"),("P2_PREPROVIDER_TRANSIENT","DEFERRED"),("P2_EVENT_BLOCKED","BLOCKED"),("P2_EVENT_FINISHED","FINISHED")):
            if "OWNER_FULL_TRACE '"+k+"'" in l:outcome=v
    import ast
    event_id=None
    for l in lines:
        m=re.match(r"OWNER_FULL_TRACE 'P2_(?:EVENT_CLAIMED|PREPROVIDER_TRANSIENT|EVENT_BLOCKED|EVENT_FINISHED)' (\{.*\})$",l)
        if m:
            try:
                d=ast.literal_eval(m.group(1)); x=d.get("event_id")
                if isinstance(x,str) and re.fullmatch(r"[a-f0-9]{32}",x):event_id=x
            except (ValueError,SyntaxError):pass
    if event_id is None:
        print("R_EVENT_UNBOUND");sys.exit(0)
    inbox=root/"inbox"
    evs=[inbox/("event-"+event_id+ext) for ext in (".json",".blocked",".done",".review")]
    evs=[p for p in evs if p.is_file() and not p.is_symlink()]
    if len(evs)!=1:
        print("R_EVENT_FILE_UNBOUND");sys.exit(0)
    ev=load(evs[0]);fp=ev.get("source_fingerprint")
    if ev.get("event_id")!=event_id or not isinstance(fp,str) or not re.fullmatch(r"[a-f0-9]{64}",fp):
        print("R_FINGERPRINT_UNBOUND");sys.exit(0)
    native=root.parent/"subtitle-trials"/".native-v13"
    import sqlite3,zipfile,io,hashlib
    job=native/fp
    terminal=load(job/"terminal.json")
    reason=terminal.get("reason")
    # Only fixed, source-defined enum strings; no file names or raw log data.
    allowed={"ARTIFACT_MISSING_OR_UNSAFE","ARTIFACT_AMBIGUOUS","ARTIFACT_INVALID","RELEASE_COMPARISON_MISSING","EXPLICIT_RUNTIME_CONFLICT","MEDIA_BINDING_MISMATCH","VIDEO_PROBE_REQUIRED","ARTIFACT_UNVERIFIED","ARTIFACT_HASH_MISMATCH","EVIDENCE_INVALID","RELEASE_UNOBSERVED","ARTIFACT_TIMELINE_INVALID","ARTIFACT_OVERRUN","NATIVE_DOWNLOAD_UNVERIFIED","NATIVE_MCP_TAB_UNBOUND","NATIVE_ACCESS_BLOCKED","NATIVE_CLI_RESULT_UNKNOWN","NATIVE_STREAM_INVALID","NATIVE_PROBE_BINDING_MISMATCH","NATIVE_ARTIFACT_READBACK_MISMATCH","NATIVE_RESULT_UNKNOWN","NATIVE_SOURCE_REJECTED","NATIVE_NO_SOURCE"}
    # Extend from the installed producer/gate's constant reason vocabulary.
    import ast
    for name in ("agy_v13_native_producer.py","agy_v13_browser_evidence.py","agy_opensubtitles_acquisition.py"):
        source=root/"app"/"poc"/"p2-sub-discovery"/name
        tree=ast.parse(source.read_text(encoding="utf-8-sig"))
        for node in ast.walk(tree):
            if isinstance(node,ast.Constant) and isinstance(node.value,str) and re.fullmatch(r"AGY_EN_[A-Z0-9_]{2,55}",node.value):
                allowed.add(node.value[7:])
    # filter_gate has short constant reason names; allow only literal tokens
    # from the installed filter_gate function, never arbitrary terminal text.
    source=root/"app/poc/p2-sub-discovery/agy_v13_browser_evidence.py"
    tree=ast.parse(source.read_text(encoding="utf-8-sig"))
    for node in tree.body:
        if isinstance(node,ast.FunctionDef) and node.name=="filter_gate":
            for v in ast.walk(node):
                if isinstance(v,ast.Constant) and isinstance(v.value,str) and re.fullmatch(r"[A-Z][A-Z0-9_]{2,50}",v.value):allowed.add(v.value)
    code=reason[7:] if isinstance(reason,str) and reason.startswith("AGY_EN_") and reason[7:] in allowed else "OTHER"
    status={"SOURCE_REJECTED":"S","RESULT_UNKNOWN_REVIEW_REQUIRED":"U","PRE_PROVIDER_BLOCKED":"P","NO_SOURCE":"N"}.get(terminal.get("status"),"X")
    raw=job/"download.bin";evidence=job/"evidence.json";verified=job/"verified.json"
    copied=int(raw.is_file());evd=int(evidence.is_file());ok=int(verified.is_file())
    stamp=load(job/"provider.started.json")["started"]
    profile=root.parent/"NativeBrowserTest/CDP9555Profile"
    hist=profile/"Default/History";rows=[]
    try:
        with sqlite3.connect(hist.resolve().as_uri()+"?mode=ro",uri=True,timeout=3) as con:
            rows=con.execute("select id,target_path,state,received_bytes from downloads where start_time>=? order by start_time desc limit 20",(int((stamp+11644473600)*1000000),)).fetchall()
    except (OSError,sqlite3.Error):pass
    downloads=[];bound=0
    from urllib.parse import urlsplit
    for rid,path,state,size in rows:
        f=pathlib.Path(path)
        if state!=1 or size<=0 or f.suffix.lower() not in (".zip",".srt") or not f.is_file() or f.is_symlink() or not 0<f.stat().st_size<=2000000:continue
        try:
            with sqlite3.connect(hist.resolve().as_uri()+"?mode=ro",uri=True,timeout=3) as con:
                urls=con.execute("select url from downloads_url_chains where id=?",(rid,)).fetchall()
            if not any(urlsplit(u[0]).scheme=="https" and urlsplit(u[0]).hostname in {"opensubtitles.org","www.opensubtitles.org","dl.opensubtitles.org"} for u in urls):continue
        except (OSError,sqlite3.Error,ValueError):continue
        downloads.append(f)
    zcount=0;valid=0
    artifact=raw if copied else downloads[0] if len(downloads)==1 else None
    if artifact is not None and not artifact.is_symlink() and 0<artifact.stat().st_size<=2000000:
        sys.path[:0]=[str(root/"app/poc"/x) for x in ("p2-sub-discovery","p2-aisub","p3-vietsub-trigger")]
        from agy_v13_browser_evidence import _subtitle_bytes
        from opensubtitles import validate_timed_text
        blob=artifact.read_bytes()
        if blob.startswith(b"PK"):
            try:
                with zipfile.ZipFile(io.BytesIO(blob)) as z:zcount=min(9,sum(not x.is_dir() and x.filename.lower().endswith(".srt") for x in z.infolist()))
            except (OSError,ValueError,zipfile.BadZipFile):zcount=9
        try:
            valid=int(validate_timed_text(_subtitle_bytes(blob),"srt")>0)
        except Exception:pass
        if copied:bound=int(any(hashlib.sha256(f.read_bytes()).digest()==hashlib.sha256(blob).digest() for f in downloads))
    print("R_"+code+"_"+status+"_D"+str(min(9,len(downloads)))+"_A"+str(copied)+"_E"+str(evd)+"_V"+str(ok)+"_Z"+str(zcount)+"_S"+str(valid)+"_H"+str(bound))

except Exception:
    print("R_READ_UNAVAILABLE")
'@
$lines=@(& py -3 -I -B -c $py $owner 2>$null)
$code='R_READ_UNAVAILABLE'
if($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and [string]$lines[0] -cmatch '^R_(READ_UNAVAILABLE|[A-Z0-9_]{3,86})$'){$code=[string]$lines[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
