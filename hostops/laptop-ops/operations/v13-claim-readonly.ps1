# Exact Owner-local claim audit, no writes except diagnostic receipt.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$py=@'
import pathlib,sys,json,time,re,ast
root=pathlib.Path(sys.argv[1])
def load(p):
    return json.loads(p.read_text(encoding="utf-8-sig"))
try:
    h=load(root/"agent-health.json")
    if h["state"]!="READY" or not 0<=time.time()-h["observed_utc_epoch"]<=30:raise ValueError()
    p=root/"diagnostics"/"owner-full.log"
    with p.open("rb") as f:
        n=f.seek(0,2); off=max(0,n-4194304);f.seek(off);raw=f.read(4194304)
    if off:raw=raw.partition(b"\n")[2]
    lines=raw.decode("utf-8","replace").splitlines()
    starts=[i for i,l in enumerate(lines) if re.fullmatch(r"OWNER_FULL_DIAGNOSTICS_STARTED pid="+str(int(h["pid"]))+r" epoch=[0-9]+",l)]
    if not starts:print("C_AUDIT_LOG_PID_UNBOUND");sys.exit(0)
    lines=lines[starts[-1]+1:]
    last={}
    for l in lines:
        m=re.match(r"OWNER_FULL_TRACE 'P2_(EVENT_CLAIMED|PREPROVIDER_TRANSIENT|EVENT_BLOCKED|EVENT_FINISHED)' (\{.*\})$",l)
        if m:
            try:
                d=ast.literal_eval(m.group(2));eid=d.get("event_id")
                if isinstance(eid,str) and re.fullmatch(r"[a-f0-9]{32}",eid):last[eid]=m.group(1)
            except Exception:pass
    inbox=root/"inbox";native=root.parent/"subtitle-trials"/".native-v13";state=root.parent/"P2"/"auto-lean120-state"
    counts=dict(orphan=0,pending=0,transient=0,terminal=0,claimed=0,unknown=0,pre=0,provider=0,aged=0)
    for c in inbox.glob("claim-*"):
        eid=c.name[6:]
        if any((inbox/("event-"+eid+x)).is_file() for x in (".blocked",".done",".review")):continue
        p=inbox/("event-"+eid+".json")
        if not p.is_file():counts["orphan"]+=1;continue
        counts["pending"]+=1
        status=last.get(eid,"UNKNOWN")
        counts[{"PREPROVIDER_TRANSIENT":"transient","EVENT_CLAIMED":"claimed","EVENT_BLOCKED":"terminal","EVENT_FINISHED":"terminal"}.get(status,"unknown")]+=1
        if time.time()-c.stat().st_mtime>180:counts["aged"]+=1
        fp=load(p).get("source_fingerprint")
        if isinstance(fp,str) and re.fullmatch(r"[a-f0-9]{64}",fp):
            d=native/fp
            if (d/"provider.started.json").exists():counts["provider"]+=1
            if (d/"terminal.json").is_file() and load(d/"terminal.json").get("status")=="PRE_PROVIDER_BLOCKED":counts["pre"]+=1
    print("C_O%d_P%d_T%d_F%d_C%d_U%d_B%d_E%d_A%d_N%d_I%d"%(counts["orphan"],counts["pending"],counts["transient"],counts["terminal"],counts["claimed"],counts["unknown"],counts["pre"],counts["provider"],counts["aged"],int((native/"browser.pending").exists()),len(list(state.rglob("*.inflight")))))
except Exception:print("C_AUDIT_UNAVAILABLE")
'@
$lines=@(& py -3 -I -B -c $py $root 2>$null)
$code='C_AUDIT_UNAVAILABLE'
if($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and [string]$lines[0] -cmatch '^C_[A-Z0-9_]{3,90}$'){$code=[string]$lines[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
