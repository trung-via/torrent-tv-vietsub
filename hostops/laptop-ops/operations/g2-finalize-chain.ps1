# Human-approved final narrow delta and archive completed Cosmos browser marker. No AGY or TV effect.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('OwnerBridge\backups\g2-finalize-chain-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='G2_FINAL_LOCAL_ERROR'
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
    final="a6bd7882054b2d942809502c34c25c5b9c682cd1"
    original=matching("0ecf5774c267da08b9d79659b0fae360fb14ddd5","G2_DEPLOY_APPLIED_START_HOLD_PENDING_1")
    n=matching("cc5d4b8d8f883c8975ac028cfa75f418d17d2314","G2_PROD_OWNER_HOLD_G2_BROWSER_EFFECT_REVIEW_REQUIRED")
    rn=matching("890dd00767a3f5efb496d16910aeb41c7415ec20","G2_RESUME_COSMOS_LIBRARY_READY_MS5253")
    receipt=read_doc(spool/"Receipts"/("g2-resume-"+rn+".json"))
    need(receipt.get("request_id")==n and receipt.get("nonce")==rn and receipt.get("fixture")=="COSMOS","RECOVERY_BINDING")
    lib=read_doc(spool/"Receipts"/("g2-"+n+".library.json"))
    need(lib.get("request_id")==n and lib.get("status")=="LIBRARY_READY" and lib.get("torrent_hash")=="c9e15763f722f23e98a29decdfae341b98d53056" and lib.get("play") is True,"LIBRARY_BINDING")
    folder=cache/".native-v13"/("g2-"+n)
    terminal=read_doc(folder/"terminal.json");checkpoint=read_doc(folder/"checkpoint.json")
    need(terminal.get("owner_request_id")==n and terminal.get("reason")=="G2_BROWSER_EFFECT_REVIEW_REQUIRED" and terminal.get("results")==checkpoint.get("results") and len(terminal["results"])==1 and terminal["results"][0].get("status")=="SELECTION_READY","CHECKPOINT_BINDING")
    mark=cache/".native-v13"/"browser.pending";marker=safe_file(mark)
    need(marker.decode("utf-8")==folder.name,"MARKER_BINDING")
    need((inbox/("g2-"+n+".claim")).is_file() and (inbox/("g2-"+n+".receipt.json")).is_file(),"ORIGINAL_CLAIM")
    prev=matching("669e5583cb573005f794c6b3e04e9070d8a9372f","G2_FINAL_HOLD_STOP_UNVERIFIED")
    previous=owner/"backups"/("g2-finalize-"+prev)
    intent=read_doc(previous/"change-intent.json")
    need(intent.get("request_id")==n and intent.get("head")==final and intent.get("old_head")==head and type(intent.get("old_pid")) is int,"INTENT_BINDING")
    need(not any((previous/x).exists() for x in ("marker-archived.json","applied.json","start-attempt.json","started.json","browser.pending.archived")),"PRIOR_MUTATION_RECONCILE")
    last=matching("43963a384e7f55746c46d9cdb88b805c40303436","G2_FINAL_HOLD_UNEXPECTED_OWNER_WORKER")
    lastroot=owner/"backups"/("g2-finalize-reconcile-"+last)
    readout=read_doc(lastroot/"stop-readout.json")
    need(readout.get("task")=="DISABLED" and readout.get("old_pid")==intent["old_pid"],"PRIOR_READOUT_BINDING")
    need(not any((lastroot/x).exists() for x in ("change-intent.json","orphan-stop-intent.json","marker-archived.json","applied.json","start-attempt.json")),"PRIOR_EFFECT")
    need(not any((p/"change-intent.json").exists() or (p/"chain-stop-intent.json").exists() for p in (owner/"backups").glob("g2-finalize-chain-*") if p!=run),"PRIOR_CHAIN_EFFECT")
    manifest=read_doc(owner/"backups"/("g2-delta-"+original)/"applied.json")
    hashes=manifest.get("hashes",{});names=set(new)|set(shared)|{launcher.name}
    need(manifest.get("head")==head and set(hashes)==names,"DEPLOY_MANIFEST")
    targets={name:launcher if name==launcher.name else d2/name for name in names}
    def verify(expected):
        need(all(blob(safe_file(p))==expected[name] for name,p in targets.items()),"INSTALLED_HASH_DRIFT")
    verify(hashes)
    def quiet():
        need(not any(inbox.glob("event-*.json")) and not any(state.rglob("*.inflight")) and not any(state.rglob("active.lock")),"OTHER_WORK_PENDING")
        need(not any(re.fullmatch(r"g2-[a-f0-9]{32}\.json",p.name) and not p.with_suffix(".claim").exists() and not p.with_suffix(".receipt.json").exists() for p in inbox.glob("g2-*.json")),"OTHER_G2_PENDING")
        need(set(cache.rglob("browser.pending"))=={mark} and not any(owner.rglob("browser.pending")),"OTHER_BROWSER_EFFECT")
        # Owner-specific provider process inventory; never terminate any provider.
        s=ps(r"""$p=@(Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(agy|antigravity|node|pwsh|pythonw?|py)(\.exe)?$' -and $_.CommandLine -match '(?i)TorrentTVVietsub[\\/].*(?:antigravity-cli|chrome-devtools-mcp|[\\/]agy(?:\.exe|\.cmd)?)' });$p.Count""")
        need(s=="0","PROVIDER_ACTIVE")
    def browser():
        from urllib.parse import urlsplit
        opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
        def get(path):
            with opener.open("http://127.0.0.1:9555"+path,timeout=4) as f:return json.load(f)
        v=get("/json/version")
        ident=v.get("webSocketDebuggerUrl","")
        need(str(v.get("Browser","")).startswith("Chrome/") and ident.startswith("ws://127.0.0.1:9555/devtools/browser/"),"BROWSER_IDENTITY")
        pages=[p for p in get("/json/list") if p.get("type")=="page"]
        need(len(pages)==1,"BROWSER_NOT_IDLE")
        p=pages[0];url=p.get("url","");u=urlsplit(url)
        need(bool(re.fullmatch(r"[A-Fa-f0-9]{32}",p.get("id",""))) and (url in ("about:blank","chrome://newtab/","chrome://new-tab-page/") or u.scheme=="https" and u.hostname in ("opensubtitles.org","www.opensubtitles.org")),"BROWSER_BASE_TAB")
        return ident,p["id"],url
    def pid_ok(pid):
        return ps("$w=Get-CimInstance Win32_Process -Filter "+q("ProcessId="+str(pid))+";if($null -eq $w){throw 'PID'};$who=Invoke-CimMethod -InputObject $w -MethodName GetOwnerSid;if($who.ReturnValue -ne 0 -or $who.Sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or ([string]$w.CommandLine).IndexOf("+q(str(d2/"owner_p3_p4_entrypoint.py"))+",[StringComparison]::OrdinalIgnoreCase) -lt 0){throw 'PID_IDENTITY'};'OK'")=="OK"
    # Reconcile the previous stop, never repeat Disable/Stop-ScheduledTask.
    observed_task=task()
    need(observed_task=="DISABLED","PRIOR_TASK_NOT_DISABLED")
    pid=intent["old_pid"]
    need(pid>0,"PRIOR_PID")
    quiet();b=browser();time.sleep(1);need(browser()==b,"BROWSER_UNSTABLE")
    path=d2/"owner_session_bridge.py";before=safe_file(path)
    after=safe_file(previous/"stage"/path.name)
    need(blob(before)==intent["before"] and blob(after)==intent["after"] and safe_file(previous/"original-owner_session_bridge.py")==before,"STAGE_BACKUP_BINDING")
    ast.parse(after.decode("utf-8-sig"),filename=path.name)
    (run/"original-owner_session_bridge.py").write_bytes(before)
    # Classify by parsed argv, not a command-line substring or hard-coded count.
    # Only actual invocations of the enrolled launcher and exact entrypoint
    # with its expected owner/cache/state roots can be selected.
    import ctypes
    from ctypes import wintypes
    split=ctypes.windll.shell32.CommandLineToArgvW
    split.argtypes=[wintypes.LPCWSTR,ctypes.POINTER(ctypes.c_int)]
    split.restype=ctypes.POINTER(wintypes.LPWSTR)
    free=ctypes.windll.kernel32.LocalFree
    free.argtypes=[ctypes.c_void_p];free.restype=ctypes.c_void_p
    def argv(line):
        c=ctypes.c_int();p=split(line,ctypes.byref(c))
        need(bool(p),"ARGV_PARSE")
        try:return [p[i] for i in range(c.value)]
        finally:free(ctypes.cast(p,ctypes.c_void_p))
    def canonical(x):return os.path.normcase(os.path.normpath(x))
    ep=canonical(str(d2/"owner_p3_p4_entrypoint.py"));lp=canonical(str(launcher))
    def inventory():
        cmd=r"""$e="""+q(str(d2/"owner_p3_p4_entrypoint.py"))+r""";$l="""+q(str(launcher))+r""";$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;$a=@(Get-CimInstance Win32_Process|Where-Object{$_.ProcessId -ne $PID -and $_.Name -match '^(pythonw?|py|pwsh)(\.exe)?$' -and (([string]$_.CommandLine).IndexOf($e,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or ([string]$_.CommandLine).IndexOf($l,[StringComparison]::OrdinalIgnoreCase) -ge 0)});$out=@(foreach($w in $a){$who=Invoke-CimMethod -InputObject $w -MethodName GetOwnerSid;[pscustomobject]@{pid=[int]$w.ProcessId;parent=[int]$w.ParentProcessId;name=[string]$w.Name;created=[string]$w.CreationDate;line=[string]$w.CommandLine;owned=($who.ReturnValue -eq 0 -and $who.Sid -ceq $sid)}});ConvertTo-Json -InputObject $out -Compress"""
        raw=json.loads(ps(cmd));need(isinstance(raw,list),"INVENTORY")
        found=[];ignored=0
        for x in raw:
            args=argv(x["line"]); tokens=[canonical(a) for a in args]
            name=x["name"].lower().removesuffix(".exe")
            role=None
            if name=="pwsh" and lp in tokens:
                i=tokens.index(lp)
                if i>0 and args[i-1].lower()=="-file" and i==len(args)-1:role="launcher"
            if name in ("py","python","pythonw") and ep in tokens:
                i=tokens.index(ep)
                flags=args[i+1:]
                expected=["--owner-root",str(owner),"--cache-root",str(cache),"--state-root",str(state),"--start-lan"]
                if [canonical(a) for a in flags]==[canonical(a) for a in expected]:role="shim" if name=="py" else "python"
            if role:
                need(x["owned"] is True,"OWNER_SID")
                found.append({"pid":x["pid"],"parent":x["parent"],"created":x["created"],"role":role})
            else:ignored+=1
        return sorted(found,key=lambda x:x["pid"]),ignored
    w,ignored=inventory()
    historical={x["pid"] for x in readout.get("workers",[])}
    # Every selected process must be in the previous exact-path inventory.
    # A new PID or unrelated invocation remains HOLD.
    need(all(x["pid"] in historical for x in w),"NEW_OWNER_WORKER")
    counts={r:sum(x["role"]==r for x in w) for r in ("launcher","shim","python")}
    write_doc("chain-readout.json",{"counts":counts,"ignored":ignored,"workers":w,"old_pid":pid})
    need(all(v<=1 for v in counts.values()),"MULTIPLE_OWNER_CHAINS")
    python=[x for x in w if x["role"]=="python"]
    need(not python or python[0]["pid"]==pid,"PYTHON_PID_DRIFT")
    # Parent relationships, when both levels remain, must form the same chain.
    byrole={x["role"]:x for x in w}
    if "shim" in byrole and "python" in byrole:need(byrole["python"]["parent"]==byrole["shim"]["pid"],"SHIM_CHAIN")
    if "launcher" in byrole:
        child=byrole.get("shim") or byrole.get("python")
        if child:need(child["parent"]==byrole["launcher"]["pid"],"LAUNCHER_CHAIN")
    quiet();need(task()=="DISABLED" and browser()==b and inventory()[0]==w,"CHAIN_DRIFT")
    if w:
        write_doc("chain-stop-intent.json",{"workers":w})
        # Prevent a surviving launcher or shim from relaunching its child.
        for role in ("launcher","shim","python"):
            x=byrole.get(role)
            if not x:continue
            current,_=inventory()
            same=[y for y in current if y["pid"]==x["pid"]]
            if not same:continue
            need(same==[x],"STOP_IDENTITY_DRIFT")
            stop=r"""$w=Get-CimInstance Win32_Process -Filter """+q("ProcessId="+str(x["pid"]))+r""";if($null -eq $w){'GONE';return};$who=Invoke-CimMethod -InputObject $w -MethodName GetOwnerSid;if($who.ReturnValue -ne 0 -or $who.Sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or [string]$w.CreationDate -cne """+q(x["created"])+r"""){throw 'STOP_IDENTITY'};Stop-Process -Id $w.ProcessId -ErrorAction Stop;'STOPPED'"""
            need(ps(stop) in ("GONE","STOPPED"),"CHAIN_STOP")
    for _ in range(10):
        if task()=="DISABLED" and not inventory()[0]:break
        time.sleep(1)
    else:raise Hold("CHAIN_STOP_UNVERIFIED")
    write_doc("change-intent.json",{"request_id":n,"old_head":head,"head":final,"before":blob(before),"after":blob(after),"old_pid":pid,"prior":prev,"chain":counts,"ignored":ignored})
    quiet();need(browser()==b and safe_file(mark)==marker,"STOPPED_BROWSER_DRIFT")
    verify(hashes)
    # No original tab identity persisted: archive stale marker by explicit Human
    # authority, completed original request, idle current browser, no live effect.
    archive=run/"browser.pending.archived"
    os.rename(mark,archive);need(safe_file(archive)==marker and not mark.exists(),"MARKER_ARCHIVE")
    write_doc("marker-archived.json",{"request_id":n,"blob":blob(marker)})
    applied=False
    try:
        replace(path,after);applied=True
        expected=dict(hashes);expected[path.name]=blob(after);verify(expected)
        write_doc("applied.json",{"head":final,"hashes":expected})
        need(not any(inbox.glob("event-*.json")) and not any(state.rglob("*.inflight")) and not any(cache.rglob("browser.pending")) and not any(owner.rglob("browser.pending")),"NEW_WORK_AFTER_APPLY")
        need(not any(re.fullmatch(r"g2-[a-f0-9]{32}\.json",p.name) and not p.with_suffix(".claim").exists() and not p.with_suffix(".receipt.json").exists() for p in inbox.glob("g2-*.json")),"NEW_G2_AFTER_APPLY")
    except Exception:
        if applied and safe_file(path)==after:replace(path,before)
        if not mark.exists() and archive.exists():os.rename(archive,mark)
        write_doc("rollback.json",{"source":blob(safe_file(path))==blob(before),"marker":mark.exists()})
        raise
    since=int(time.time());write_doc("start-attempt.json",{"head":final,"since":since})
    ps(r"""Enable-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'|Out-Null;Start-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'""")
    for _ in range(45):
        time.sleep(1)
        try:
            h=read_doc(owner/"agent-health.json");newpid=h.get("pid")
            if h.get("state")!="READY" or type(newpid) is not int or newpid==pid or h.get("observed_utc_epoch",0)<since or task()!="RUNNING" or not pid_ok(newpid):continue
            verify(expected)
            need(not mark.exists() and safe_file(archive)==marker,"MARKER_POST_START")
            write_doc("started.json",{"head":final,"pid":newpid,"observed":h["observed_utc_epoch"]})
            return "G2_FINAL_PASS_MARKER_ARCHIVED_DELTA1_8HASH_FRESH_OWNER_L"+str(counts["launcher"])+"S"+str(counts["shim"])+"P"+str(counts["python"])
        except (OSError,ValueError,KeyError,Hold):continue
    return "G2_FINAL_APPLIED_HEARTBEAT_UNVERIFIED_NO_REPLAY"
try: print(main())
except Hold as e: print("G2_FINAL_HOLD_"+str(e))
except Exception:
    import traceback
    (run/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("G2_FINAL_LOCAL_ERROR")
'@
$f=Join-Path $run 'deploy.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $run $spool $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
}catch{[IO.File]::WriteAllText((Join-Path $run 'host-private-error.txt'),($_|Out-String),[Text.UTF8Encoding]::new($false))}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
