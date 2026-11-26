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
    if not starts:print("R_V132_LOG_UNBOUND");sys.exit(0)
    epoch=int(lines[starts[-1]].rsplit("=",1)[1])
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
            if e.get("event_id")!=eid or not isinstance(fp,str) or not re.fullmatch(r"[a-f0-9]{64}",fp):continue
            events.append((m.group(1),fp,files[0],eid,e))
        except (ValueError,SyntaxError,OSError,AttributeError):pass
    if not events:print("R_V132_EVENT_UNBOUND");sys.exit(0)
    outcome,fp,event,eid,e=max(events,key=lambda row:row[2].stat().st_mtime)
    t0=event.stat().st_mtime
    if t0<epoch or time.time()-t0>3600:print("R_V132_EVENT_NOT_FRESH");sys.exit(0)
    def delta(t):
        return str(round(t-t0)) if t>=t0-1 and t-t0<86400 else "U"
    job=cache/".native-v13"/fp
    pth=job/"prompt.txt"
    from agy_v13_browser_evidence import RECIPE,RECIPE_VERSION
    if RECIPE_VERSION!="V13.2":print("R_V132_NOT_INSTALLED");sys.exit(0)
    recipe_ok=pth.is_file() and not pth.is_symlink() and pth.stat().st_size<=65536 and pth.read_text(encoding="utf-8").startswith(RECIPE) and pth.stat().st_mtime>=t0-1
    if not recipe_ok:
        print("R_V132_"+("EVENT_BLOCKED" if outcome=="EVENT_BLOCKED" else "WAIT_FRESH_RECIPE"));sys.exit(0)
    term=job/"terminal.json"
    if not term.is_file():print("R_V132_TERMINAL_MISSING");sys.exit(0)
    q=read(term,4096);reason=q.get("reason")
    allowed={"NATIVE_NO_SOURCE","NATIVE_RESULT_UNKNOWN","NATIVE_SOURCE_REJECTED","ENGLISH_LIST_AND_DOWNLOAD_BOUND","DOWNLOAD_BOUND_LIST_COVERAGE_HOLD","DOWNLOAD_UNVERIFIED","CLICK_UNBOUND","LIST_COVERAGE_UNVERIFIED"}
    for f in ("agy_v13_native_producer.py","agy_v13_browser_evidence.py","agy_opensubtitles_acquisition.py"):
        tree=ast.parse((root/"app/poc/p2-sub-discovery"/f).read_text(encoding="utf-8-sig"))
        for node in ast.walk(tree):
            if isinstance(node,ast.Constant) and isinstance(node.value,str) and re.fullmatch(r"AGY_EN_[A-Z0-9_]{2,55}",node.value):allowed.add(node.value[7:])
            if isinstance(node,ast.Call) and isinstance(node.func,ast.Name) and node.func.id=="_hold" and node.args and isinstance(node.args[0],ast.Constant) and isinstance(node.args[0].value,str):allowed.add("NATIVE_"+node.args[0].value)
    code=reason[7:] if isinstance(reason,str) and reason.startswith("AGY_EN_") and reason[7:] in allowed else "NONE" if reason is None else "OTHER"
    status={"SOURCE_REJECTED":"S","RESULT_UNKNOWN_REVIEW_REQUIRED":"U","PRE_PROVIDER_BLOCKED":"P","NO_SOURCE":"N"}.get(q.get("status"),"X")
    provider=job/"provider.started.json";p=read(provider,4096).get("started") if provider.is_file() else None
    print("R_V132_"+code+"_"+status+"_P"+(delta(p) if isinstance(p,(float,int)) else "U")+"_A"+str(int((job/"download.bin").is_file()))+"_E"+str(int((job/"evidence.json").is_file()))+"_T"+delta(term.stat().st_mtime))

except Exception:
    print("R_READ_UNAVAILABLE")
'@
$lines=@(& py -3 -I -B -c $py $owner 2>$null)
$code='R_READ_UNAVAILABLE'
if($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and [string]$lines[0] -cmatch '^R_(READ_UNAVAILABLE|[A-Z0-9_]{3,86})$'){$code=[string]$lines[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
