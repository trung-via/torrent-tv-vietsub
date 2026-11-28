# Read-only Flow3 source package verification and installed delta planning. No installed file or task change.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('OwnerBridge\backups\flow3-overlay-readout-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='FLOW3_PREFLIGHT_LOCAL_ERROR'
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
    from concurrent.futures import ThreadPoolExecutor
    ref="472d8c367601116a6c66297a7e0e74821124126e"
    pkg="b1ee5e177b9768d4a5e96a79ca4b22602236855f"
    def raw(ref,path):
        with urllib.request.urlopen("https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/"+ref+"/"+path,timeout=25) as f:
            data=f.read(2_000_001)
        need(0<len(data)<=2_000_000,"SOURCE_LENGTH")
        return data
    builder=raw(ref,"poc/p2-source/build_flow3_owner_overlay.py")
    recipe_data=raw(ref,"poc/p2-source/flow3_owner_overlay.json")
    need(blob(builder)=="b56722a73b391ac126ddedd523280cac72b5660f" and blob(recipe_data)=="d9c41b13651258a1610a0629eb8f9cd3e9952860","MERGED_RECIPE_HASH")
    recipe=json.loads(recipe_data)
    need(recipe["package_commit"]==pkg and recipe["runtime_base"]=="a6bd7882054b2d942809502c34c25c5b9c682cd1","PACKAGE_BINDING")
    rows=recipe["patches"]+recipe["copies"]
    keys=list(dict.fromkeys([(recipe["runtime_base"] if "base_blob" in x else recipe["merged_g2_source"],x["source"]) for x in rows]+[(pkg,x["path"]) for x in rows]+[(pkg,"manifest.json"),(pkg,"README.md")]))
    with ThreadPoolExecutor(max_workers=4) as pool:
        data=dict(zip(keys,pool.map(lambda k:raw(*k),keys)))
    ns={"__name__":"flow3_source_builder","__file__":str(run/"build_flow3_owner_overlay.py")}
    exec(compile(builder,"build_flow3_owner_overlay.py","exec"),ns)
    files=ns["assemble"](recipe,lambda ref,path:data[(ref,path)])
    need(len(files)==12,"PACKAGE_COUNT")
    # Private disposable diagnostic outputs only; no installed files touched.
    z1,z2=run/"flow3-source.zip",run/"flow3-source-repeat.zip"
    ns["write_zip"](z1,files);ns["write_zip"](z2,files)
    need(safe_file(z1)==safe_file(z2),"ZIP_NOT_REPRODUCIBLE")
    import zipfile
    with zipfile.ZipFile(z1) as z:
        need(z.testzip() is None and {name:z.read(name) for name in z.namelist()}==files,"ZIP_READBACK")
    package_sha=hashlib.sha256(safe_file(z1)).hexdigest()
    write_doc("package-verified.json",{"commit":pkg,"payloads":10,"sha256":package_sha,"reproducible":True})
    prior=matching("02b80c398411ab425d988f53224ab2993d3f96ba","G2_FINAL_PASS_MARKER_ARCHIVED_DELTA1_8HASH_FRESH_OWNER_L0S1P1")
    prev=owner/"backups"/("g2-finalize-chain-"+prior)
    applied=read_doc(prev/"applied.json");started=read_doc(prev/"started.json")
    hashes=applied.get("hashes",{})
    need(applied.get("head")==recipe["runtime_base"] and started.get("head")==recipe["runtime_base"] and set(hashes)==set(new)|set(shared)|{launcher.name},"PREVIOUS_DEPLOYMENT_BINDING")
    targets={name:launcher if name==launcher.name else d2/name for name in hashes}
    actual={name:blob(safe_file(p)) for name,p in targets.items()}
    need(actual==hashes,"INSTALLED_SOURCE_DRIFT")
    changes=[]
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
        changes.append({"name":name,"before":blob(before) if before is not None else None,
                        "after":blob(after),"action":"KEEP" if before==after else "ADD" if before is None else "UPDATE"})
    need(len(changes)==8,"OWNER_FILE_COUNT")
    unchanged={name:actual[name] for name in ("agy_v13_native_producer.py",launcher.name)}
    write_doc("delta-plan.json",{"package":pkg,"prior_receipt":prior,"source_before":actual,
                                  "owner_files":changes,"preserve":unchanged,
                                  "runner_scripts":"KEEP_PINNED_NO_INSTALL","zip_sha256":package_sha,
                                  "observed_utc_epoch":time.time()})
    current=task()
    health=read_doc(owner/"agent-health.json");pid=health.get("pid")
    def pid_ok(pid):
        return ps("$w=Get-CimInstance Win32_Process -Filter "+q("ProcessId="+str(pid))+";if($null -eq $w){throw 'PID'};$who=Invoke-CimMethod -InputObject $w -MethodName GetOwnerSid;if($who.ReturnValue -ne 0 -or $who.Sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or ([string]$w.CommandLine).IndexOf("+q(str(d2/"owner_p3_p4_entrypoint.py"))+",[StringComparison]::OrdinalIgnoreCase) -lt 0){throw 'PID_IDENTITY'};'OK'")=="OK"
    need(current=="RUNNING" and type(pid) is int and pid>0 and health.get("state")=="READY" and 0<=time.time()-health.get("observed_utc_epoch",0)<=30 and pid_ok(pid),"OWNER_NOT_FRESH")
    pending_g1=sum(1 for p in inbox.glob("event-*.json"))
    pending_g2=sum(1 for p in inbox.glob("g2-*.json") if re.fullmatch(r"g2-[a-f0-9]{32}\.json",p.name) and not p.with_suffix(".claim").exists() and not p.with_suffix(".receipt.json").exists())
    marker=sum(1 for p in cache.rglob("browser.pending"))+sum(1 for p in owner.rglob("browser.pending"))
    inflight=sum(1 for p in state.rglob("*.inflight"))+sum(1 for p in state.rglob("active.lock"))
    provider=int(ps(r"""$p=@(Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(agy|antigravity|node|pwsh|pythonw?|py)(\.exe)?$' -and $_.CommandLine -match '(?i)TorrentTVVietsub[\\/].*(?:antigravity-cli|chrome-devtools-mcp|[\\/]agy(?:\.exe|\.cmd)?)' });$p.Count"""))
    write_doc("readiness.json",{"owner_task":current,"pid":pid,"observed":health["observed_utc_epoch"],"g1":pending_g1,"g2":pending_g2,"markers":marker,"inflight":inflight,"provider":provider})
    count=lambda action:sum(x["action"]==action for x in changes)
    status="READY" if not any((pending_g1,pending_g2,marker,inflight,provider)) else "BUSY"
    return "FLOW3_PREFLIGHT_"+status+"_ZIP10_A"+str(count("ADD"))+"U"+str(count("UPDATE"))+"K"+str(count("KEEP"))+"_HB1"
try: print(main())
except Hold as e: print("FLOW3_PREFLIGHT_HOLD_"+str(e))
except Exception:
    import traceback
    (run/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("FLOW3_PREFLIGHT_LOCAL_ERROR")
'@
$f=Join-Path $run 'deploy.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $run $spool $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
}catch{[IO.File]::WriteAllText((Join-Path $run 'host-private-error.txt'),($_|Out-String),[Text.UTF8Encoding]::new($false))}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
