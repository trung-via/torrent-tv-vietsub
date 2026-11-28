# Recover exact verified production selection only. No AGY, browser mutation, restart or reinstall.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('OwnerBridge\backups\g2-production-resume-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='G2_RESUME_LOCAL_ERROR'
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
def matching(source_commit,reason):
    found=set()
    for folder in (spool/"History",spool/"Receipts"):
        for p in folder.glob("receipt*.json"):
            try:r=read_doc(p)
            except (OSError,ValueError,Hold):continue
            n=r.get("nonce","")
            if r.get("source_commit")!=source_commit or r.get("result")!="SUCCESS" or not re.fullmatch(r"[a-f0-9]{32}",str(n)):continue
            s=read_doc(spool/"Receipts"/("odyssey-stage-"+n+".json"))
            if s.get("nonce")==n and s.get("reason")==reason:found.add(n)
    need(len(found)==1,"PRIOR_RECEIPT")
    return next(iter(found))
def main():
    n=matching("cc5d4b8d8f883c8975ac028cfa75f418d17d2314","G2_PROD_OWNER_HOLD_G2_BROWSER_EFFECT_REVIEW_REQUIRED")
    rn=matching("aaab468bde71a09ca559206fe4bac8639e2eb407","G2_READ_COSMOS_R1_V1_MS55859_F1_E0_P1_S0_L0_T0_C1W0B1_O1")
    observed=read_doc(owner/"backups"/("g2-production-readout-"+rn)/"readout.json")
    need(observed.get("selection_valid") is True and observed.get("fixture")=="COSMOS" and observed.get("library_present")==0,"READOUT_BINDING")
    old=owner/"backups"/("g2-production-"+n)
    sub=read_doc(old/"submitted.json");req=read_doc(old/"private-request.json")
    need(sub.get("request_id")==n and sub.get("fixture")=="COSMOS" and req.get("request_id")==n,"SUBMISSION_BINDING")
    orig=matching("0ecf5774c267da08b9d79659b0fae360fb14ddd5","G2_DEPLOY_APPLIED_START_HOLD_PENDING_1")
    manifest=read_doc(owner/"backups"/("g2-delta-"+orig)/"applied.json")
    hashes=manifest.get("hashes",{});names=set(new)|set(shared)|{launcher.name}
    need(manifest.get("head")==head and set(hashes)==names,"DEPLOY_MANIFEST")
    need(all(blob(safe_file(launcher if name==launcher.name else d2/name))==hashes[name] for name in names),"INSTALLED_HASH_DRIFT")
    need(task()=="RUNNING","OWNER_NOT_RUNNING")
    h=read_doc(owner/"agent-health.json")
    need(h.get("state")=="READY" and type(h.get("pid")) is int and 0<=time.time()-h.get("observed_utc_epoch",0)<=30,"OWNER_HEARTBEAT")
    need(not any(inbox.glob("event-*.json")) and not any(state.rglob("*.inflight")),"G1_BUSY")
    need(not any((p/"resume-intent.json").exists() for p in (owner/"backups").glob("g2-production-resume-*") if p!=run),"PRIOR_RESUME_NO_REPLAY")
    folder=cache/".native-v13"/("g2-"+n)
    d=read_doc(inbox/("g2-"+n+".receipt.json"));term=read_doc(folder/"terminal.json");cp=read_doc(folder/"checkpoint.json")
    need(d.get("request_id")==n and d.get("status")=="REVIEW_REQUIRED" and term.get("owner_request_id")==n and cp.get("owner_request_id")==n and d.get("reason")==term.get("reason")==term.get("cleanup_reason")=="G2_BROWSER_EFFECT_REVIEW_REQUIRED","TERMINAL_BINDING")
    rows=d.get("results",[]);need(len(rows)==1 and rows==term.get("results")==cp.get("results"),"CHECKPOINT_BINDING")
    row=rows[0];expected="c9e15763f722f23e98a29decdfae341b98d53056"
    need(row.get("owner_request_id")==n and row.get("status")=="SELECTION_READY" and row.get("selection",{}).get("expected_hash")==expected and req["queries"][0]["verified_release_hash"]==expected,"ROW_BINDING")
    turn=row.get("turn_request_id","");need(bool(re.fullmatch(r"[a-f0-9]{32}",turn)),"TURN_BINDING")
    turnpath=folder/turn
    need(read_doc(turnpath/"result.json")==row and not (turnpath/"turn-terminal.json").exists(),"TURN_CHECKPOINT")
    trace=turnpath/"agy-stdout.jsonl";need(trace.stat().st_size<=16777216,"TRACE_LIMIT")
    finals=[]
    for line in safe_file(trace).decode("utf-8",errors="replace").splitlines():
        try:e=json.loads(line)
        except ValueError:continue
        if isinstance(e,dict) and e.get("event")=="result" and isinstance(e.get("result"),dict):finals.append(e["result"])
    need(len(finals)==1 and isinstance(finals[0].get("response"),str),"TRACE_FINAL")
    raw=finals[0]["response"].strip()
    fence=re.fullmatch(r"\x60{3}(?:json)?\s*(.*?)\s*\x60{3}",raw,re.S)
    payload=json.loads(fence[1] if fence else raw)
    # Recompute the source-bound selection from original trace, not a new provider turn.
    sys.path[:0]=[str(d2),str(app/"poc/p2-aisub"),str(app/"poc/p3-vietsub-trigger")]
    from owner_session_bridge import _g2_request,_publish_g2_selection
    from owner_g2_discovery import _selected_metadata
    from owner_movie_handoff import publish_library_receipt,HandoffHold
    query=_g2_request(req,n)[0]
    verified=_selected_metadata(payload,query,turn,"webtorrent.io",trace)
    need(verified.get("status")=="SELECTION_READY" and verified.get("selection")==row.get("selection") and verified.get("release_name")==row.get("release_name"),"OFFLINE_SELECTION_RECHECK")
    marker=cache/".native-v13"/"browser.pending"
    need(safe_file(marker).decode("utf-8")==folder.name,"BROWSER_MARKER_DRIFT")
    need((inbox/("g2-"+n+".claim")).is_file(),"ORIGINAL_CLAIM")
    # Browser hold is preserved. This handoff has no browser/AGY dependency.
    write_doc("resume-intent.json",{"request_id":n,"fixture":"COSMOS","head":head})
    need(_publish_g2_selection(inbox,n,query,rows),"SELECTION_PUBLISH")
    began=time.monotonic()
    try:
        status=publish_library_receipt(inbox,n)
        for _ in range(6):
            if status!="FILE_SELECTION_PENDING":break
            time.sleep(5)
            status=publish_library_receipt(inbox,n)
    except HandoffHold as e:
        reason=str(e)
        return "G2_RESUME_LIBRARY_HOLD_"+(reason if re.fullmatch(r"[A-Z0-9_]{1,55}",reason) else "UNKNOWN")
    need(status=="LIBRARY_READY","LIBRARY_PENDING_NO_REPLAY")
    lib=read_doc(spool/"Receipts"/("g2-"+n+".library.json"))
    need(lib.get("request_id")==n and lib.get("status")=="LIBRARY_READY" and lib.get("torrent_hash")==expected and lib.get("play") is True and type(lib.get("file_id")) is int,"LIBRARY_BINDING")
    ms=round((time.monotonic()-began)*1000)
    # New private pointer connects this maintenance receipt to the ORIGINAL request.
    pointer={"schema":"TTV-G2-RESUME-V1","nonce":nonce,"request_id":n,"fixture":"COSMOS","library_ms":ms}
    target=spool/"Receipts"/("g2-resume-"+nonce+".json")
    with target.open("x",encoding="utf-8") as f:json.dump(pointer,f);f.flush();os.fsync(f.fileno())
    write_doc("resumed.json",pointer)
    return f"G2_RESUME_COSMOS_LIBRARY_READY_MS{ms}"
try: print(main())
except Hold as e: print("G2_RESUME_HOLD_"+str(e))
except Exception:
    import traceback
    (run/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("G2_RESUME_LOCAL_ERROR")
'@
$f=Join-Path $run 'deploy.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $run $spool $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
}catch{[IO.File]::WriteAllText((Join-Path $run 'host-private-error.txt'),($_|Out-String),[Text.UTF8Encoding]::new($false))}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
