# Reconcile exact stale G2 browser claim; no provider call, denied-site replay or playback.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('OwnerBridge\backups\flow3-g2-marker-repair-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='G2_MARKER_REPAIR_LOCAL_ERROR'
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
def task_info():
    return json.loads(ps(r"""$t=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\';$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;$u=[string]$t.Principal.UserId;if($u -notmatch '^S-1-'){$u=([Security.Principal.NTAccount]::new($u)).Translate([Security.Principal.SecurityIdentifier]).Value};if($u -cne $sid -or $t.Principal.LogonType -ine 'Interactive' -or @($t.Actions).Count -ne 1){throw 'TASK_IDENTITY'};$a=$t.Actions[0];if([IO.Path]::GetFileName([string]$a.Execute) -ine 'pwsh.exe' -or [string]$a.Arguments -notmatch '^(-NoLogo\s+-NoProfile\s+-NonInteractive\s+-File\s+)' -or ([string]$a.Arguments -replace '^(-NoLogo\s+-NoProfile\s+-NonInteractive\s+-File\s+)','').Trim('"') -ine """+q(launcher)+r"""){throw 'TASK_ACTION'};([pscustomobject]@{state=([string]$t.State).ToUpperInvariant();enabled=[bool]$t.Settings.Enabled}|ConvertTo-Json -Compress)"""))
def task():return task_info()["state"]
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
def apply_context(old,baseline,target):
    # Apply only exact unique G2 hunks on the installed text. No fuzzy merge.
    old,baseline,target=map(norm,(old,baseline,target))
    if old==baseline:return target
    if old==target:return old
    lines=old.splitlines(keepends=True); b=baseline.splitlines(keepends=True); t=target.splitlines(keepends=True)
    groups=list(difflib.SequenceMatcher(None,b,t,autojunk=False).get_grouped_opcodes(3))
    for group in groups:
        start,end=group[0][1],group[-1][2]; ts,te=group[0][3],group[-1][4]
        before=b[start:end]; after=t[ts:te]
        hits=[i for i in range(len(lines)-len(before)+1) if lines[i:i+len(before)]==before]
        need(len(hits)==1,"SHARED_CONTEXT_CONFLICT")
        i=hits[0];lines[i:i+len(before)]=after
    return b"".join(lines)
def replace(p,b):
    tmp=p.with_name("."+p.name+".g2-"+nonce+".tmp")
    with tmp.open("xb") as f:f.write(b);f.flush();os.fsync(f.fileno())
    os.replace(tmp,p)
def main():
    from urllib.parse import urlsplit
    n=matching("10e3c1e43e0133313292eb61c864661d0a87e5ab","FLOW3_POST_HUMAN_HOLD_AGY_STREAM_ACCESS_BLOCKED")
    parent=cache/"movie-discovery"/".native-v13";batch=parent/("g2-"+n);mark=parent/"browser.pending"
    terminal=read_doc(batch/"terminal.json");receipt=read_doc(inbox/("g2-"+n+".receipt.json"))
    need(terminal.get("owner_request_id")==n and terminal.get("reason")=="AGY_STREAM_ACCESS_BLOCKED" and terminal.get("results")==[] and receipt.get("request_id")==n and receipt.get("reason")=="AGY_STREAM_ACCESS_BLOCKED" and receipt.get("results")==[],"TERMINAL_BIND")
    marker=safe_file(mark)
    need(marker.decode("utf-8")==batch.name,"MARKER_BIND")
    need(not (inbox/("g2-"+n+".selected.json")).exists() and not (spool/"Receipts"/("g2-"+n+".library.json")).exists(),"PRIOR_EFFECT")
    latest=hashlib.sha256(b"ttv-production-movie-v1:7235929746").hexdigest()[:32]
    lr=read_doc(inbox/("g2-"+latest+".receipt.json"))
    need(lr.get("request_id")==latest and lr.get("reason")=="G2_BROWSER_BUSY_OR_UNKNOWN" and lr.get("results")==[],"LATEST_RECEIPT")
    need(not (inbox/("g2-"+latest+".selected.json")).exists() and not (spool/"Receipts"/("g2-"+latest+".library.json")).exists(),"LATEST_EFFECT")
    def quiet():
        need(not any(re.fullmatch(r"g2-[a-f0-9]{32}\.json",p.name) and not p.with_suffix(".receipt.json").exists() for p in inbox.glob("g2-*.json")),"G2_PENDING")
        # Only movie lane; G1 work is not a reason to change or stop G1.
        result=ps(r"""$all=@(Get-CimInstance Win32_Process);$p=@($all|Where-Object {$_.ProcessId -ne $PID -and $_.Name -match '^(agy|antigravity|node|pwsh|pythonw?|py)(\.exe)?$' -and $_.CommandLine -match '(?i)movie-discovery|CDP9556MovieProfile|browser-url=http://127\.0\.0\.1:9556'});$c=@($all|Where-Object{$_.Name -eq 'chrome.exe' -and $_.CommandLine -match '(?i)CDP9556MovieProfile' -and $_.CommandLine -match '(?:^|\s|")--remote-debugging-port=9556(?:\s|"|\z)'});$l=@(Get-NetTCPConnection -State Listen -ErrorAction Stop|Where-Object{$_.LocalPort -eq 9556});$pids=@($l|Select-Object -ExpandProperty OwningProcess -Unique);$owned=$false;if($c.Count -eq 1 -and $pids.Count -eq 1 -and $pids[0] -eq $c[0].ProcessId -and @($l|Where-Object{$_.LocalAddress -notin @('127.0.0.1','::1')}).Count -eq 0){$o=Invoke-CimMethod -InputObject $c[0] -MethodName GetOwnerSid;$owned=($o.ReturnValue -eq 0 -and $o.Sid -ceq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value)};@{provider=$p.Count;chrome=$c.Count;listeners=$pids.Count;owned=$owned}|ConvertTo-Json -Compress""")
        r=json.loads(result);need(r["provider"]==0,"G2_PROVIDER_ACTIVE")
        if r["listeners"]==0:
            need(r["chrome"]==0,"G2_CHROME_WITHOUT_LISTENER")
            return {"state":"OFF","pages":[]}
        need(r["owned"] is True,"G2_BROWSER_IDENTITY")
        opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
        def get(path):
            with opener.open("http://127.0.0.1:9556"+path,timeout=5) as f:return json.load(f)
        ver=get("/json/version");ident=ver.get("webSocketDebuggerUrl","")
        need(str(ver.get("Browser","")).startswith("Chrome/") and ident.startswith("ws://127.0.0.1:9556/devtools/browser/"),"CDP_IDENTITY")
        pages=[x for x in get("/json/list") if x.get("type")=="page"]
        rows=[{"id":x.get("id"),"url":x.get("url")} for x in pages]
        need(all(isinstance(x["id"],str) and re.fullmatch(r"[A-Fa-f0-9]{32}",x["id"]) and isinstance(x["url"],str) for x in rows),"PAGE_ID")
        return {"state":"ON","browser":ident,"pages":sorted(rows,key=lambda x:x["id"])}
    blank={"about:blank","chrome://newtab/","chrome://new-tab-page/"}
    first=quiet()
    need(quiet()==first and safe_file(mark)==marker,"RECONCILE_DRIFT")
    pages=first["pages"]
    # This is cleanup of a terminal denied metadata job, not an attempt
    # to obtain access to the denied site. No provider call or replay.
    old=[x for x in pages if urlsplit(x["url"]).hostname=="ext.to" and urlsplit(x["url"]).scheme=="https"]
    baseline=[x for x in pages if x["url"] in blank]
    need(len(old)<=1 and len(baseline)<=1 and len(old)+len(baseline)==len(pages),"UNRELATED_PAGE_PRESERVED")
    write_doc("browser-before.json",{"state":first["state"],"old_tabs":len(old),"blank_tabs":len(baseline)})
    if old:
        opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
        # Close only the old source tab in this verified dedicated browser.
        # Retain the terminal denial and all request/receipt evidence.
        write_doc("close-intent.json",{"request_id":n,"tab":old[0]["id"]})
        try:
            with opener.open("http://127.0.0.1:9556/json/close/"+old[0]["id"],timeout=5) as f:f.read(1024)
        except (OSError,ValueError):pass
        time.sleep(2)
    after=quiet()
    if after["state"]=="ON":
        need(after.get("browser")==first.get("browser"),"BROWSER_ID_CHANGED")
        need(all(x["url"] in blank for x in after["pages"]) and len(after["pages"])<=1,"CLEANUP_UNCONFIRMED")
        if not after["pages"]:
            opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
            with opener.open(urllib.request.Request("http://127.0.0.1:9556/json/new?about:blank",method="PUT"),timeout=5) as f:f.read(2048)
            after=quiet()
    need(after["state"]=="OFF" or (len(after["pages"])==1 and after["pages"][0]["url"] in blank),"BASELINE_NOT_READY")
    need(quiet()==after and safe_file(mark)==marker,"RECONCILE_DRIFT")
    archive=run/"browser.pending.archived"
    os.rename(mark,archive)
    need(safe_file(archive)==marker and not mark.exists(),"ARCHIVE_VERIFY")
    write_doc("marker-archived.json",{"request_id":n,"blob":blob(marker),"browser":after["state"],"denial_preserved":True})
    return "G2_MARKER_REPAIR_PASS"
try: print(main())
except Hold as e: print("G2_MARKER_REPAIR_HOLD_"+str(e))
except Exception:
    import traceback
    (run/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("G2_MARKER_REPAIR_LOCAL_ERROR")
'@
$f=Join-Path $run 'deploy.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $run $spool $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
}catch{[IO.File]::WriteAllText((Join-Path $run 'host-private-error.txt'),($_|Out-String),[Text.UTF8Encoding]::new($false))}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
