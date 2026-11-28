# Human-authorized apply of exact preflight delta; one existing Owner restart. No AGY or device request.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('OwnerBridge\backups\flow3-overlay-apply-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='FLOW3_APPLY_LOCAL_ERROR'
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
    import zipfile
    pkg="b1ee5e177b9768d4a5e96a79ca4b22602236855f"
    ref="472d8c367601116a6c66297a7e0e74821124126e"
    n=matching("63e5b0cfc5ab2987013ff9a5fa24bc623d402d45","FLOW3_PREFLIGHT_READY_ZIP10_A2U4K2_HB1")
    pre=owner/"backups"/("flow3-overlay-readout-"+n)
    plan=read_doc(pre/"delta-plan.json"); proof=read_doc(pre/"package-verified.json")
    need(plan.get("package")==proof.get("commit")==pkg and proof.get("payloads")==10 and proof.get("reproducible") is True,"PREFLIGHT_BINDING")
    need(not any((p/"change-intent.json").exists() for p in (owner/"backups").glob("flow3-overlay-apply-*") if p!=run),"PRIOR_APPLY_RECONCILE")
    z=safe_file(pre/"flow3-source.zip")
    package_sha=hashlib.sha256(z).hexdigest()
    need(package_sha==proof["sha256"]==plan["zip_sha256"],"PACKAGE_DRIFT")
    with urllib.request.urlopen("https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/"+ref+"/poc/p2-source/flow3_owner_overlay.json",timeout=25) as f:recipe_data=f.read(100_000)
    need(blob(recipe_data)=="d9c41b13651258a1610a0629eb8f9cd3e9952860","RECIPE_HASH")
    recipe=json.loads(recipe_data);rows=recipe["patches"]+recipe["copies"]
    need(recipe["package_commit"]==pkg,"PACKAGE_BINDING")
    import io
    with zipfile.ZipFile(io.BytesIO(z)) as archive:
        need(archive.testzip() is None and len(archive.namelist())==12 and set(archive.namelist())=={x["path"] for x in rows}|{"manifest.json","README.md"},"ZIP_CONTENT")
        files={x["path"]:archive.read(x["path"]) for x in rows}
    need(all(blob(files[x["path"]])==x["blob"] for x in rows),"PAYLOAD_HASH")
    data={}
    for x in recipe["patches"]:
        with urllib.request.urlopen("https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/"+recipe["runtime_base"]+"/"+x["source"],timeout=25) as f:b=f.read(2_000_000)
        need(blob(b)==x["base_blob"],"BASE_HASH")
        data[(recipe["runtime_base"],x["source"])]=b
    prior=matching("02b80c398411ab425d988f53224ab2993d3f96ba","G2_FINAL_PASS_MARKER_ARCHIVED_DELTA1_8HASH_FRESH_OWNER_L0S1P1")
    prev=owner/"backups"/("g2-finalize-chain-"+prior)
    applied=read_doc(prev/"applied.json");started=read_doc(prev/"started.json")
    hashes=applied.get("hashes",{})
    need(applied.get("head")==recipe["runtime_base"] and started.get("head")==recipe["runtime_base"] and set(hashes)==set(new)|set(shared)|{launcher.name},"PREVIOUS_DEPLOYMENT_BINDING")
    targets={name:launcher if name==launcher.name else d2/name for name in hashes}
    actual={name:blob(safe_file(p)) for name,p in targets.items()}
    need(actual==hashes,"INSTALLED_SOURCE_DRIFT")
    changes=[]; before_bytes={}; after_bytes={}
    for x in rows:
        if x["path"].startswith("runner/"):continue
        name=pathlib.PurePosixPath(x["path"]).name
        path=d2/name
        target=files[x["path"]]
        before=safe_file(path) if path.exists() or path.is_symlink() else None
        if "base_blob" in x:
            need(before is not None and name in hashes,"SHARED_MISSING")
            baseline=data[(recipe["runtime_base"],x["source"])]
            # Compare exact old G2 block, preserving unrelated installed G1 bytes.
            orig=norm(before);base_text=norm(baseline)
            def one(buf,anchor):
                b=anchor.encode("utf-8")
                need(buf.count(b)==1,"SHARED_CONTEXT_CONFLICT")
                return b
            if x["kind"]=="bridge":
                begin,end=one(orig,x["begin"]),one(orig,x["end"])
                one(base_text,x["begin"]);one(base_text,x["end"])
                i,j=orig.index(begin),orig.index(end)
                bi,bj=base_text.index(begin),base_text.index(end)
                need(j>i and bj>bi and orig[i:j]==base_text[bi:bj],"SHARED_G2_BLOCK_CONFLICT")
                orig=orig[:i]+x["replace_block"].encode("utf-8")+orig[j:]
            old=one(orig,x["old"]);after=orig.replace(old,x["new"].encode("utf-8"),1)
            # Preserve uniform CRLF if the enrolled source uses it.
            if before.count(b"\r\n") and before.count(b"\n")==before.count(b"\r\n"):
                after=after.replace(b"\n",b"\r\n")
        else:
            after=target
            if name not in hashes and before is not None:
                need(before==target,"NEW_MODULE_CONFLICT")
        ast.parse(after,filename=name)
        before_bytes[name]=before; after_bytes[name]=after
        changes.append({"name":name,"before":blob(before) if before is not None else None,
                        "after":blob(after),"action":"KEEP" if before==after else "ADD" if before is None else "UPDATE"})
    need(len(changes)==8,"OWNER_FILE_COUNT")
    unchanged={name:actual[name] for name in ("agy_v13_native_producer.py",launcher.name)}
    need(plan["prior_receipt"]==prior and plan["source_before"]==actual and plan["owner_files"]==changes and plan["preserve"]==unchanged,"PREFLIGHT_PLAN_DRIFT")
    need(sum(x["action"]=="ADD" for x in changes)==2 and sum(x["action"]=="UPDATE" for x in changes)==4 and sum(x["action"]=="KEEP" for x in changes)==2,"DELTA_SCOPE")
    expected=dict(actual);expected.update({x["name"]:x["after"] for x in changes})
    alltargets=dict(targets);alltargets.update({x["name"]:d2/x["name"] for x in changes})
    def verify_before():
        need(all(blob(safe_file(p))==actual[name] for name,p in targets.items()),"BEFORE_DRIFT")
        need(all(not (d2/x["name"]).exists() and not (d2/x["name"]).is_symlink() for x in changes if x["action"]=="ADD"),"NEW_MODULE_DRIFT")
    def verify_after():
        need(all(blob(safe_file(p))==expected[name] for name,p in alltargets.items()),"AFTER_DRIFT")
    stage=run/"stage";stage.mkdir();backup=run/"originals";backup.mkdir()
    for x in changes:
        name=x["name"]
        (stage/name).write_bytes(after_bytes[name])
        need(safe_file(stage/name)==after_bytes[name],"STAGE_HASH")
        if x["action"]=="UPDATE":
            (backup/name).write_bytes(before_bytes[name])
            need(safe_file(backup/name)==before_bytes[name],"BACKUP_HASH")
    # Import actual staged modules with installed sibling dependencies; no runtime start.
    imp="import sys;sys.path[:0]=sys.argv[1:];import owner_session_bridge as b,owner_p3_p4_runtime as r,owner_g2_inbox as i,owner_g2_submit as s,owner_movie_handoff as h;assert b.poll_owner_g2_idle is i.poll_owner_g2_idle and callable(r._native_owner_factory) and callable(s.submit_private_file) and callable(h.publish_library_receipt);print('IMPORT_PASS')"
    env=dict(os.environ,CI="true")
    proc=subprocess.run([sys.executable,"-I","-B","-c",imp,str(stage),str(d2),str(app/"poc/p2-aisub"),str(app/"poc/p3-vietsub-trigger")],env=env,capture_output=True,timeout=30)
    (run/"import-stderr.txt").write_bytes(proc.stderr)
    need(proc.returncode==0 and b"IMPORT_PASS" in proc.stdout,"IMPORT_HOLD")
    current=task()
    health=read_doc(owner/"agent-health.json");pid=health.get("pid")
    def pid_ok(pid):
        return ps("$w=Get-CimInstance Win32_Process -Filter "+q("ProcessId="+str(pid))+";if($null -eq $w){throw 'PID'};$who=Invoke-CimMethod -InputObject $w -MethodName GetOwnerSid;if($who.ReturnValue -ne 0 -or $who.Sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or ([string]$w.CommandLine).IndexOf("+q(str(d2/"owner_p3_p4_entrypoint.py"))+",[StringComparison]::OrdinalIgnoreCase) -lt 0){throw 'PID_IDENTITY'};'OK'")=="OK"
    need(current=="RUNNING" and type(pid) is int and pid>0 and health.get("state")=="READY" and 0<=time.time()-health.get("observed_utc_epoch",0)<=30 and pid_ok(pid),"OWNER_NOT_FRESH")
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
    w,ignored=inventory()
    counts={role:sum(x["role"]==role for x in w) for role in ("launcher","shim","python")}
    need(all(v<=1 for v in counts.values()) and counts["python"]==1,"OWNER_CHAIN_COUNT")
    byrole={x["role"]:x for x in w}
    need(byrole["python"]["pid"]==pid,"OWNER_PID_DRIFT")
    if "shim" in byrole:need(byrole["python"]["parent"]==byrole["shim"]["pid"],"SHIM_CHAIN")
    if "launcher" in byrole:
        child=byrole.get("shim") or byrole["python"]
        need(child["parent"]==byrole["launcher"]["pid"],"LAUNCHER_CHAIN")
    need(task()=="RUNNING" and inventory()[0]==w,"PRESTOP_DRIFT")
    quiet();verify_before()
    write_doc("change-intent.json",{"package":pkg,"preflight":n,"before":actual,"expected":expected,"workers":w})
    # Disable scheduling, then stop only the identified chain. Do not repeat
    # the unreliable Stop-ScheduledTask call from earlier maintenance.
    ps(r"""Disable-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'|Out-Null""")
    need(task()=="DISABLED","TASK_DISABLE_UNVERIFIED")
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
    quiet();verify_before()
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
            return "FLOW3_APPLY_PASS_A2U4K2_HASH10_FRESH_OWNER"
        except (OSError,ValueError,KeyError,Hold):continue
    return "FLOW3_APPLIED_HEARTBEAT_UNVERIFIED_NO_REPLAY"
try: print(main())
except Hold as e: print("FLOW3_APPLY_HOLD_"+str(e))
except Exception:
    import traceback
    (run/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("FLOW3_APPLY_LOCAL_ERROR")
'@
$f=Join-Path $run 'deploy.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $run $spool $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
}catch{[IO.File]::WriteAllText((Join-Path $run 'host-private-error.txt'),($_|Out-String),[Text.UTF8Encoding]::new($false))}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
