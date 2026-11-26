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
    native=root.parent/"subtitle-trials"/".native-v13"
    recent=[]
    if native.is_dir() and not native.is_symlink():
        for d in native.iterdir():
            if not d.is_dir() or d.is_symlink():continue
            f=d/"terminal.json"
            if f.is_file() and not f.is_symlink() and 0<=time.time()-f.stat().st_mtime<=600:
                recent.append(f)
    terminal="NONE"
    if len(recent)==1:
        q=load(recent[0])
        s=q.get("status")
        terminal={"PRE_PROVIDER_BLOCKED":"PRECALL","NO_SOURCE":"NOSOURCE","SOURCE_REJECTED":"REJECT","RESULT_UNKNOWN_REVIEW_REQUIRED":"UNKNOWN"}.get(s,"OTHER")
    elif len(recent)>1:terminal="MULTI"
    pending=int((native/"browser.pending").is_file())
    print("R_"+reason+"_P2_"+outcome+"_N_"+terminal+"_B"+str(pending))
except Exception:
    print("R_READ_UNAVAILABLE")
'@
$lines=@(& py -3 -I -B -c $py $owner 2>$null)
$code='R_READ_UNAVAILABLE'
if($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and [string]$lines[0] -cmatch '^R_(READ_UNAVAILABLE|[A-Z0-9_]{3,86})$'){$code=[string]$lines[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
