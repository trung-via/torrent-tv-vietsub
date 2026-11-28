# Read-only reconciliation of the exact production attempt. No provider or browser mutations.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('OwnerBridge\backups\g2-production-readout-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='G2_READ_LOCAL_ERROR'
try {
$py=@'
import ast,hashlib,json,os,pathlib,re,shutil,subprocess,sys,time,urllib.request,difflib
root,run,spool=map(pathlib.Path,sys.argv[1:4])
nonce=sys.argv[4]
owner=root/"OwnerBridge"; app=owner/"app"; d2=app/"poc/p2-sub-discovery"; launcher=owner/"start-owner-session-agent.ps1"
inbox=owner/"inbox"; state=root/"P2/auto-lean120-state"; cache=root/"subtitle-trials"
base="b0e0cba86a09a7353c416536088d666363f3676c"; head="47c265fc908171ab18bb0707b2e26b014fb39d40"
new={"agy_owner_warm_session.py":"9cbc45c643d99cc9655fe9a7357eafd07cd227d0","owner_g2_discovery.py":"2707298aaa10e38c79f44505a6853ed31336ff0d","owner_g2_submit.py":"196da5a5e560faa9f780428073e67a75e956d73b","owner_movie_handoff.py":"0e5d351af58d089bd53d3fd78b4a6f46509ecbbb"}
shared={"agy_v13_native_producer.py":("20e9c725bce400593ae9a5ba27eda19f2aed797f","cfd8af916f73eff84cbb46ca75f0eab184540641"),"owner_p3_p4_runtime.py":("f8b6aa4b22647190e372d91f5bda045e7f17a326","33277f5ea67cabf95cb096ba87a6c2c659bfb6e1"),"owner_session_bridge.py":("6c0d14c66e401f5cdb9ac0ccd2974208355b167f","3b6faaeb4481ea8c1a06b0bcd777dbdad336070e")}
class Hold(Exception):pass
def need(ok,reason):
    if not ok:raise Hold(reason)
def blob(b):return hashlib.sha1(b"blob "+str(len(b)).encode()+b"\0"+b).hexdigest()
def norm(b):return b.replace(b"\r\n",b"\n")
def ps(s,timeout=20):
    p=subprocess.run(["pwsh","-NoProfile","-NonInteractive","-Command","$ErrorActionPreference='Stop';"+s],capture_output=True,encoding="utf-8",errors="replace",timeout=timeout)
    need(p.returncode==0,"TASK_OR_PS_FAILED")
    return p.stdout.strip()
def q(s):return "'"+str(s).replace("'","''")+"'"
def write_doc(name,v):(run/name).write_text(json.dumps(v,indent=2),encoding="utf-8")
def safe_file(p):
    need(p.is_file() and not p.is_symlink() and not (p.stat().st_file_attributes & 1024),"FILE_IDENTITY")
    return p.read_bytes()
def source(ref,name,expected):
    url=f"https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/{ref}/poc/p2-sub-discovery/{name}"
    with urllib.request.urlopen(url,timeout=25) as f:b=f.read(2_000_000)
    need(blob(b)==expected,"SOURCE_HASH")
    return b
def task():
    return ps(r"""$t=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\';$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;$u=[string]$t.Principal.UserId;if($u -notmatch '^S-1-'){$u=([Security.Principal.NTAccount]::new($u)).Translate([Security.Principal.SecurityIdentifier]).Value};if($u -cne $sid -or $t.Principal.LogonType -ine 'Interactive' -or @($t.Actions).Count -ne 1){throw 'TASK_IDENTITY'};$a=$t.Actions[0];if([IO.Path]::GetFileName([string]$a.Execute) -ine 'pwsh.exe' -or [string]$a.Arguments -notmatch '^(-NoLogo\s+-NoProfile\s+-NonInteractive\s+-File\s+)' -or ([string]$a.Arguments -replace '^(-NoLogo\s+-NoProfile\s+-NonInteractive\s+-File\s+)','').Trim('"') -ine """+q(launcher)+r"""){throw 'TASK_ACTION'};[string]$t.State""").upper()
def read_doc(p):
    return json.loads(safe_file(p).decode("utf-8-sig"))
def main():
    found=set()
    for folder in (spool/"History",spool/"Receipts"):
        for p in folder.glob("receipt*.json"):
            try:r=read_doc(p)
            except (OSError,ValueError,Hold):continue
            n=r.get("nonce","")
            if r.get("source_commit")!="cc5d4b8d8f883c8975ac028cfa75f418d17d2314" or r.get("result")!="SUCCESS" or not re.fullmatch(r"[a-f0-9]{32}",str(n)):continue
            s=read_doc(spool/"Receipts"/("odyssey-stage-"+n+".json"))
            if s.get("nonce")==n and s.get("reason")=="G2_PROD_OWNER_HOLD_G2_BROWSER_EFFECT_REVIEW_REQUIRED":found.add(n)
    need(len(found)==1,"ORIGINAL_RECEIPT")
    n=next(iter(found));old=owner/"backups"/("g2-production-"+n)
    sub=read_doc(old/"submitted.json");req=read_doc(old/"private-request.json")
    need(sub.get("request_id")==n and req.get("request_id")==n,"SUBMISSION_BINDING")
    fixture=sub.get("fixture");need(fixture in ("COSMOS","BUNNY"),"FIXTURE")
    d=read_doc(inbox/("g2-"+n+".receipt.json"))
    folder=cache/".native-v13"/("g2-"+n)
    term=read_doc(folder/"terminal.json")
    need(d.get("request_id")==n and term.get("owner_request_id")==n and d.get("reason")==term.get("reason")=="G2_BROWSER_EFFECT_REVIEW_REQUIRED","TERMINAL_BINDING")
    rows=d.get("results",[]);need(rows==term.get("results") and isinstance(rows,list) and len(rows)<=1,"RESULT_BINDING")
    row=rows[0] if rows else {}
    sel=row.get("selection",{})
    good=bool(row.get("status")=="SELECTION_READY" and row.get("owner_request_id")==n and row.get("query")==req["queries"][0] or False)
    # Stored query also contains dataclass defaults; match explicit request fields.
    good=bool(row.get("status")=="SELECTION_READY" and row.get("owner_request_id")==n and all(row.get("query",{}).get(k)==v for k,v in req["queries"][0].items()) and sel.get("expected_hash")==req["queries"][0]["verified_release_hash"] and all(sel.get(k) is True for k in ("source_authorized","media_authorized","release_matched")))
    ms=row.get("timing",{}).get("final_ms",0);ms=ms if type(ms) is int and 0<=ms<=200000 else 0
    traces=list(folder.glob("*/agy-stdout.jsonl")); finals=turnerr=0
    for f in traces:
        need(f.stat().st_size<=16777216,"TRACE_LIMIT")
        for line in safe_file(f).decode("utf-8",errors="replace").splitlines():
            try:e=json.loads(line)
            except ValueError:continue
            if isinstance(e,dict) and e.get("event")=="result" and isinstance(e.get("result"),dict):finals+=1
        turnerr+=int((f.parent/"turn-terminal.json").exists())
    pend=cache/".native-v13"/"browser.pending"
    pending=int(pend.is_file() and safe_file(pend).decode("utf-8")==folder.name)
    lib=spool/"Receipts"/("g2-"+n+".library.json")
    selected=inbox/("g2-"+n+".selected.json")
    claim=inbox/("g2-"+n+".claim")
    # Read current loopback inventory only. Do not close any page or clear any claim.
    try:
        with urllib.request.build_opener(urllib.request.ProxyHandler({})).open("http://127.0.0.1:9555/json/list",timeout=4) as f:pages=[p for p in json.load(f) if p.get("type")=="page"]
        count=len(pages)
        from urllib.parse import urlsplit
        web=sum(urlsplit(p.get("url","")).hostname=="webtorrent.io" for p in pages)
        blank=sum(p.get("url") in ("about:blank","chrome://newtab/","chrome://new-tab-page/") or urlsplit(p.get("url","")).hostname in ("opensubtitles.org","www.opensubtitles.org") for p in pages)
    except Exception:count=web=blank=99
    h=read_doc(owner/"agent-health.json")
    fresh=bool(task()=="RUNNING" and h.get("state")=="READY" and type(h.get("pid")) is int and 0<=time.time()-h.get("observed_utc_epoch",0)<=30)
    if fresh:
        pid=h["pid"]
        fresh=ps("if(Get-Process -Id "+str(pid)+" -ErrorAction SilentlyContinue){'YES'}else{'NO'}")=="YES"
    # Check real Library presence, without add/get mutation.
    request=urllib.request.Request("http://127.0.0.1:8090/torrents",data=b'{"action":"list"}',headers={"Content-Type":"application/json"},method="POST")
    try:
        with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(request,timeout=5) as f:items=json.load(f)
        present=int(any(isinstance(x,dict) and str(x.get("hash","")).lower()==req["queries"][0]["verified_release_hash"] for x in (items or [])))
    except Exception:present=9
    status=row.get("status","NONE");status=status if status in ("SELECTION_READY","NO_PLAUSIBLE_CANDIDATE","ACCESS_BLOCKED","UNKNOWN","NONE","NO_MATCH") else "OTHER"
    # Local report retains safe structural facts, never prints private identifiers.
    write_doc("readout.json",{"fixture":fixture,"rows":len(rows),"selection_valid":good,"status":status,"ms":ms,"trace_count":len(traces),"finals":finals,"turn_errors":turnerr,"pending":pending,"selected":selected.exists(),"library_receipt":lib.exists(),"claim":claim.exists(),"pages":count,"webtorrent_pages":web,"baseline_like_pages":blank,"library_present":present,"fresh":fresh,"browser_restored":term.get("browser_restored")})
    return f"G2_READ_{fixture}_R{len(rows)}_V{int(good)}_MS{ms}_F{finals}_E{turnerr}_P{pending}_S{int(selected.exists())}_L{int(lib.exists())}_T{present}_C{count}W{web}B{blank}_O{int(fresh)}"
try: print(main())
except Hold as e: print("G2_READ_HOLD_"+str(e))
except Exception:
    import traceback
    (run/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("G2_READ_LOCAL_ERROR")
'@
$f=Join-Path $run 'deploy.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $run $spool $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
}catch{[IO.File]::WriteAllText((Join-Path $run 'host-private-error.txt'),($_|Out-String),[Text.UTF8Encoding]::new($false))}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
