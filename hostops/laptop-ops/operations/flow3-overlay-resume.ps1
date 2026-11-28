# Resume only exact staged delta after task disable verification HOLD. No AGY or device request.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('OwnerBridge\backups\flow3-overlay-resume-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='FLOW3_RESUME_LOCAL_ERROR'
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
    pkg="b1ee5e177b9768d4a5e96a79ca4b22602236855f"
    prior=matching("dab0f7bf8a7d04e8b5dcb4f9cf820c5d17202347","FLOW3_APPLY_HOLD_TASK_DISABLE_UNVERIFIED")
    previous=owner/"backups"/("flow3-overlay-apply-"+prior)
    intent=read_doc(previous/"change-intent.json")
    n=matching("63e5b0cfc5ab2987013ff9a5fa24bc623d402d45","FLOW3_PREFLIGHT_READY_ZIP10_A2U4K2_HB1")
    pre=owner/"backups"/("flow3-overlay-readout-"+n)
    plan=read_doc(pre/"delta-plan.json")
    need(intent.get("package")==plan.get("package")==pkg and intent.get("preflight")==n,"PRIOR_INTENT_BINDING")
    need(not any((previous/x).exists() for x in ("chain-stop-intent.json","applied.json","start-attempt.json","started.json","rollback.json")),"PRIOR_EFFECT_RECONCILE")
    need(not any((p/"change-intent.json").exists() or (p/"chain-stop-intent.json").exists() for p in (owner/"backups").glob("flow3-overlay-resume-*") if p!=run),"PRIOR_RESUME_RECONCILE")
    actual=intent["before"];expected=intent["expected"];changes=plan["owner_files"]
    need(actual==plan["source_before"] and set(actual)==set(new)|set(shared)|{launcher.name},"BEFORE_BINDING")
    wanted=dict(actual);wanted.update({x["name"]:x["after"] for x in changes})
    need(expected==wanted and len(expected)==10 and len(changes)==8,"EXPECTED_BINDING")
    add={"owner_g2_support.py","owner_g2_inbox.py"}
    update={"owner_g2_discovery.py","owner_g2_submit.py","owner_p3_p4_runtime.py","owner_session_bridge.py"}
    keep={"agy_owner_warm_session.py","owner_movie_handoff.py"}
    need({x["name"] for x in changes if x["action"]=="ADD"}==add and {x["name"] for x in changes if x["action"]=="UPDATE"}==update and {x["name"] for x in changes if x["action"]=="KEEP"}==keep,"DELTA_SCOPE")
    targets={name:launcher if name==launcher.name else d2/name for name in actual}
    alltargets=dict(targets);alltargets.update({name:d2/name for name in add})
    stage=previous/"stage";backup=previous/"originals"
    before_bytes={};after_bytes={}
    for x in changes:
        name=x["name"];after=safe_file(stage/name)
        need(blob(after)==x["after"]==expected[name],"STAGED_HASH")
        ast.parse(after,filename=name)
        after_bytes[name]=after
        before=safe_file(backup/name) if name in update else safe_file(d2/name) if name in keep else None
        need((blob(before) if before is not None else None)==x["before"] and (name in add or x["before"]==actual[name]),"BACKUP_BINDING")
        before_bytes[name]=before
    def verify_before():
        need(all(blob(safe_file(p))==actual[name] for name,p in targets.items()),"BEFORE_DRIFT")
        need(all(not (d2/name).exists() and not (d2/name).is_symlink() for name in add),"NEW_MODULE_DRIFT")
    def verify_after():
        need(all(blob(safe_file(p))==expected[name] for name,p in alltargets.items()),"AFTER_DRIFT")
    verify_before()
    historical=intent["workers"]
    need(isinstance(historical,list) and len([x for x in historical if x["role"]=="python"])==1,"PRIOR_WORKERS")
    pid=next(x["pid"] for x in historical if x["role"]=="python")
    def pid_ok(pid):
        return ps("$w=Get-CimInstance Win32_Process -Filter "+q("ProcessId="+str(pid))+";if($null -eq $w){throw 'PID'};$who=Invoke-CimMethod -InputObject $w -MethodName GetOwnerSid;if($who.ReturnValue -ne 0 -or $who.Sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or ([string]$w.CommandLine).IndexOf("+q(str(d2/"owner_p3_p4_entrypoint.py"))+",[StringComparison]::OrdinalIgnoreCase) -lt 0){throw 'PID_IDENTITY'};'OK'")=="OK"
    def quiet():
        pending_g1=sum(1 for p in inbox.glob("event-*.json"))
        pending_g2=sum(1 for p in inbox.glob("g2-*.json") if re.fullmatch(r"g2-[a-f0-9]{32}\.json",p.name) and not p.with_suffix(".claim").exists() and not p.with_suffix(".receipt.json").exists())
        marker=sum(1 for p in cache.rglob("browser.pending"))+sum(1 for p in owner.rglob("browser.pending"))
        inflight=sum(1 for p in state.rglob("*.inflight"))+sum(1 for p in state.rglob("active.lock"))
        provider=int(ps(r"""$p=@(Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(agy|antigravity|node|pwsh|pythonw?|py)(\.exe)?$' -and $_.CommandLine -match '(?i)TorrentTVVietsub[\\/].*(?:antigravity-cli|chrome-devtools-mcp|[\\/]agy(?:\.exe|\.cmd)?)' });$p.Count"""))
        need(not any((pending_g1,pending_g2,marker,inflight,provider)),"OTHER_WORK_PENDING")
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
    quiet();verify_before()
    observed=task_info()
    w,ignored=inventory()
    need(all(x in historical for x in w),"OWNER_CHAIN_DRIFT")
    counts={role:sum(x["role"]==role for x in w) for role in ("launcher","shim","python")}
    need(all(v<=1 for v in counts.values()),"OWNER_CHAIN_COUNT")
    byrole={x["role"]:x for x in w}
    if "python" in byrole:
        h=read_doc(owner/"agent-health.json")
        need(byrole["python"]["pid"]==pid and h.get("pid")==pid and h.get("state")=="READY" and 0<=time.time()-h.get("observed_utc_epoch",0)<=30 and pid_ok(pid),"OWNER_PID_DRIFT")
    if "shim" in byrole and "python" in byrole:need(byrole["python"]["parent"]==byrole["shim"]["pid"],"SHIM_CHAIN")
    if "launcher" in byrole:
        child=byrole.get("shim") or byrole.get("python")
        if child:need(child["parent"]==byrole["launcher"]["pid"],"LAUNCHER_CHAIN")
    write_doc("task-readout.json",{"observed":observed,"workers":w,"prior":prior})
    # The prior disable command returned successfully. An already-disabled
    # task may report Running until the action exits. Do not reissue disable.
    need(observed["enabled"] is False,"TASK_STILL_ENABLED")
    quiet();verify_before()
    need(task_info()["enabled"] is False and inventory()[0]==w,"PRESTOP_DRIFT")
    write_doc("change-intent.json",{"package":pkg,"preflight":n,"prior":prior,"before":actual,"expected":expected,"workers":w})
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
        if task_info()["enabled"] is False and task()!="RUNNING" and not inventory()[0]:break
        time.sleep(1)
    else:raise Hold("CHAIN_STOP_UNVERIFIED")
    quiet();verify_before()
    need(task_info()["enabled"] is False and not inventory()[0],"STOPPED_DRIFT")
    mutated=[]
    try:
        # Add dependencies before changing callers. The Owner is stopped.
        for name in ("owner_g2_support.py","owner_g2_inbox.py","owner_g2_discovery.py",
                     "owner_g2_submit.py","owner_p3_p4_runtime.py","owner_session_bridge.py"):
            p=d2/name
            if before_bytes[name] is None:
                # Exclusive add, not replacement of an unexpected new file.
                with p.open("xb") as f:
                    mutated.append(name);f.write(after_bytes[name]);f.flush();os.fsync(f.fileno())
            else:
                need(safe_file(p)==before_bytes[name],"APPLY_DRIFT")
                replace(p,after_bytes[name]);mutated.append(name)
            need(safe_file(p)==after_bytes[name],"APPLY_HASH")
        verify_after()
        write_doc("applied.json",{"package":pkg,"hashes":expected,"preflight":n})
        quiet()
    except Exception:
        for name in reversed(mutated):
            p=d2/name
            if before_bytes[name] is None:
                p.unlink()
            else:
                replace(p,safe_file(backup/name))
        verify_before()
        write_doc("rollback.json",{"restored":True,"task":task()})
        raise
    # Do not roll back or replay after start intent; inspect actual receipt.
    since=time.time()
    write_doc("start-attempt.json",{"package":pkg,"since":since,"old_pid":pid})
    ps(r"""Enable-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'|Out-Null;Start-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'""")
    for _ in range(45):
        time.sleep(1)
        try:
            h=read_doc(owner/"agent-health.json");newpid=h.get("pid")
            if h.get("state")!="READY" or type(newpid) is not int or newpid==pid or h.get("observed_utc_epoch",0)<int(since) or task()!="RUNNING" or not pid_ok(newpid):continue
            current,_=inventory()
            actual_python=[x for x in current if x["role"]=="python"]
            if len(actual_python)!=1 or actual_python[0]["pid"]!=newpid:continue
            verify_after()
            write_doc("started.json",{"package":pkg,"pid":newpid,"observed":h["observed_utc_epoch"],"hashes":expected})
            return "FLOW3_RESUME_PASS_A2U4K2_HASH10_FRESH_OWNER"
        except (OSError,ValueError,KeyError,Hold):continue
    return "FLOW3_RESUME_APPLIED_HEARTBEAT_UNVERIFIED_NO_REPLAY"
try: print(main())
except Hold as e: print("FLOW3_RESUME_HOLD_"+str(e))
except Exception:
    import traceback
    (run/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("FLOW3_RESUME_LOCAL_ERROR")
'@
$f=Join-Path $run 'deploy.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $run $spool $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
}catch{[IO.File]::WriteAllText((Join-Path $run 'host-private-error.txt'),($_|Out-String),[Text.UTF8Encoding]::new($false))}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
