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
    from agy_v13_browser_evidence import filter_gate
    from collections import Counter
    import hashlib
    proof=read(job/"evidence.json")
    outcomes=proof["outcomes"]
    gate=filter_gate(outcomes,proof["artifacts"])
    if not gate["accepted"]:raise ValueError()
    count=Counter(o.get("tool") for o in outcomes)
    duplicate=0;seen=set()
    for o in outcomes:
        if o.get("tool") in ("take_snapshot","evaluate_script","list_pages"):
            key=(o.get("tool"),hashlib.sha256(json.dumps(o.get("output"),sort_keys=True,ensure_ascii=False).encode()).hexdigest())
            duplicate+=int(key in seen);seen.add(key)
    stdout=job/"agy-stdout.jsonl"
    if stdout.is_symlink() or not 0<stdout.stat().st_size<=16777216:raise ValueError()
    # CLI final receipt time is approximated by last stream write, not a tool timestamp.
    p=read(job/"provider.started.json",4096)["started"]
    cli=round(stdout.stat().st_mtime-p)
    post=round((job/"download.bin").stat().st_mtime-stdout.stat().st_mtime)
    if min(cli,post)<-1 or max(cli,post)>86400:raise ValueError()
    print("R_BT_RE_O"+str(len(outcomes))+"L"+str(count["list_pages"])+"N"+str(count["navigate_page"])+"S"+str(count["take_snapshot"])+"E"+str(count["evaluate_script"])+"C"+str(count["click"])+"F"+str(count["fill"])+"K"+str(count["press_key"])+"W"+str(count["wait_for"])+"D"+str(duplicate)+"R"+str(gate["english_candidates"])+"I"+str(gate["detail_candidates"])+"_CLI"+str(cli)+"_POST"+str(post))

except Exception:
    print("R_READ_UNAVAILABLE")
'@
$lines=@(& py -3 -I -B -c $py $owner 2>$null)
$code='R_READ_UNAVAILABLE'
if($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and [string]$lines[0] -cmatch '^R_(READ_UNAVAILABLE|[A-Z0-9_]{3,86})$'){$code=[string]$lines[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
