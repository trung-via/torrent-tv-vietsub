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
    lines=lines[starts[-1]+1:]
    idx=[i for i,l in enumerate(lines) if "OWNER_FULL_TRACE 'P3_SELECTION_ACCEPTED'" in l and "'status': 'DISPATCH'" in l]
    if not idx:raise ValueError()
    lines=lines[idx[-1]+1:]
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
    folders=[native/fp]
    if native.is_dir() and not native.is_symlink():
        folders+=sorted(native.glob(fp+".preprovider-*"),key=lambda p:p.stat().st_mtime,reverse=True)[:8]
    terminals=[]
    allowed={"AGY_EN_NATIVE_GLOBAL_MCP_CONFLICT","AGY_EN_NATIVE_CONFIG_INVALID","AGY_EN_NATIVE_SHARED_RELATIVE_RULE","AGY_EN_NATIVE_EXISTING_RESTRICTION","AGY_EN_NATIVE_RELATIVE_RULE_UNKNOWN","AGY_EN_NATIVE_BROWSER_START_UNVERIFIED","AGY_EN_NATIVE_BROWSER_PROFILE_RUNNING_NO_LISTENER","AGY_EN_NATIVE_BROWSER_PROFILE_OR_EXECUTABLE_MISSING","AGY_EN_NATIVE_BROWSER_IDENTITY","AGY_EN_NATIVE_CDP_IDENTITY","AGY_EN_NATIVE_TASK_TAB_AMBIGUOUS","AGY_EN_NATIVE_TASK_TAB_UNAVAILABLE","AGY_EN_NATIVE_PROFILE_REQUIRED","AGY_EN_NATIVE_SESSION_SETTINGS_UNAVAILABLE","AGY_EN_NATIVE_VIDEO_PROBE_REQUIRED","AGY_EN_NATIVE_FFPROBE_REQUIRED","AGY_EN_NATIVE_FFPROBE_UNAVAILABLE"}
    for d in folders:
        f=d/"terminal.json"
        if d.is_symlink() or not f.is_file() or f.is_symlink():continue
        q=load(f);v=q.get("reason");status=q.get("status")
        code=v.removeprefix("AGY_EN_NATIVE_") if v in allowed else ("OTHER_"+str(q.get("error_type")) if q.get("error_type") in {"ValueError","OSError","TimeoutError","URLError","RuntimeError","AgyEnglishUnavailable","FileNotFoundError","TimeoutExpired","PermissionError","HTTPError"} else "OTHER")
        if status=="PRE_PROVIDER_BLOCKED":terminals.append((f.stat().st_mtime,code))
    if terminals:
        terminal=max(terminals)[1]
        print("R_EXACT_"+terminal.upper())
    else:
        print("R_EXACT_NO_TERMINAL")

except Exception:
    print("R_READ_UNAVAILABLE")
'@
$lines=@(& py -3 -I -B -c $py $owner 2>$null)
$code='R_READ_UNAVAILABLE'
if($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and [string]$lines[0] -cmatch '^R_(READ_UNAVAILABLE|[A-Z0-9_]{3,86})$'){$code=[string]$lines[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
