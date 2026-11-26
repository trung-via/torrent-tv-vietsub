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
    import ast
    events=[]
    inbox=root/"inbox"
    for l in lines:
        m=re.match(r"OWNER_FULL_TRACE 'P2_(EVENT_CLAIMED|PREPROVIDER_TRANSIENT|EVENT_BLOCKED|EVENT_FINISHED)' (\{.*\})$",l)
        if not m:continue
        try:
            d=ast.literal_eval(m.group(2));eid=d.get("event_id")
            if not isinstance(eid,str) or not re.fullmatch(r"[a-f0-9]{32}",eid):continue
            fs=[inbox/("event-"+eid+ext) for ext in (".json",".blocked",".done",".review")]
            fs=[x for x in fs if x.is_file() and not x.is_symlink()]
            if len(fs)!=1:continue
            e=load(fs[0]);name=re.sub(r"[^a-z0-9]+"," ",str(e.get("selected_video_filename","")).lower())
            if e.get("event_id")!=eid or not re.search(r"\bjohn wick (?:chapter )?(?:4|iv)\b",name):continue
            fp=e.get("source_fingerprint")
            if not isinstance(fp,str) or not re.fullmatch(r"[a-f0-9]{64}",fp):continue
            events.append((m.group(1),fp))
        except (ValueError,SyntaxError,AttributeError,OSError):pass
    if not events:print("R_JW4_EVENT_UNBOUND");sys.exit(0)
    outcome,fp=events[-1]
    cache=root.parent/"subtitle-trials";job=cache/".native-v13"/fp
    if (job/"verified.json").is_file():
        v=load(job/"verified.json");n=v.get("cues")
        if type(n) is not int or not 0<n<100000:raise ValueError()
        print("R_JW4_EN_C"+str(n)+"_INDEX"+str(int((cache/(".auto-source-"+fp+".json")).is_file())));sys.exit(0)
    f=job/"terminal.json"
    if not f.is_file():
        print("R_JW4_PROVIDER_STARTED" if (job/"provider.started.json").is_file() else "R_JW4_"+outcome+"_NO_TERMINAL");sys.exit(0)
    q=load(f);v=q.get("reason")
    allowed=set()
    for name in ("agy_v13_native_producer.py","agy_v13_browser_evidence.py","agy_opensubtitles_acquisition.py"):
        tree=ast.parse((root/"app/poc/p2-sub-discovery"/name).read_text(encoding="utf-8-sig"))
        for node in ast.walk(tree):
            if isinstance(node,ast.Constant) and isinstance(node.value,str) and re.fullmatch(r"AGY_EN_[A-Z0-9_]{2,55}",node.value):allowed.add(node.value[7:])
            if isinstance(node,ast.Call) and isinstance(node.func,ast.Name) and node.func.id=="_hold" and node.args and isinstance(node.args[0],ast.Constant) and isinstance(node.args[0].value,str):allowed.add("NATIVE_"+node.args[0].value)
            if isinstance(node,ast.FunctionDef) and node.name=="filter_gate":
                for x in ast.walk(node):
                    if isinstance(x,ast.Constant) and isinstance(x.value,str) and re.fullmatch(r"[A-Z][A-Z0-9_]{2,50}",x.value):allowed.add(x.value)
    code=v[7:] if isinstance(v,str) and v.startswith("AGY_EN_") and v[7:] in allowed else "OTHER"
    status={"SOURCE_REJECTED":"S","RESULT_UNKNOWN_REVIEW_REQUIRED":"U","PRE_PROVIDER_BLOCKED":"P","NO_SOURCE":"N"}.get(q.get("status"),"X")
    print("R_JW4_"+code+"_"+status+"_P"+str(int((job/"provider.started.json").is_file()))+"_A"+str(int((job/"download.bin").is_file()))+"_E"+str(int((job/"evidence.json").is_file())))

except Exception:
    print("R_READ_UNAVAILABLE")
'@
$lines=@(& py -3 -I -B -c $py $owner 2>$null)
$code='R_READ_UNAVAILABLE'
if($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and [string]$lines[0] -cmatch '^R_(READ_UNAVAILABLE|[A-Z0-9_]{3,86})$'){$code=[string]$lines[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
