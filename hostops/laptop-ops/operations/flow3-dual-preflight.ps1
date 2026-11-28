# Read-only dual-lane Owner preflight, private staging only.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('OwnerBridge\backups\flow3-dual-preflight-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='FLOW3_DUAL_PREFLIGHT_LOCAL_ERROR'
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
    from concurrent.futures import ThreadPoolExecutor
    pkg="dbe54980dc5ffdfdec355ad7fa6a5ef22af512bb"
    prior_pkg="b1ee5e177b9768d4a5e96a79ca4b22602236855f"
    candidate="d93ca6bfaa25279402ee13a2bc8960d61992c6a4"
    merged="8eea1f7b01cea2c77f903d154130cb2603c87eec"
    def raw(ref,path,expected):
        with urllib.request.urlopen("https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/"+ref+"/"+path,timeout=25) as f:b=f.read(2_000_001)
        need(0<len(b)<=2_000_000 and blob(b)==expected,"SOURCE_BLOB")
        return b
    manifest=json.loads(raw(pkg,"manifest.json","66dbb868b13e220087efa2700b223d0e67c1d51c"))
    need(manifest["candidate_head"]==candidate and manifest["prior_package"]==prior_pkg and len(manifest["files"])==10 and len(manifest["delta"])==6,"PACKAGE_BIND")
    recipe=json.loads(raw(merged,"poc/p2-source/flow3_dual_owner.json",manifest["owner_recipe_blob"]))
    need(recipe["base_package"]==prior_pkg and len(recipe["rules"])==1,"RECIPE_BIND")
    prior=matching("deee80df994a16b595f5843fb4ce489bb0061dd1","FLOW3_RESUME_PASS_A2U4K2_HASH10_FRESH_OWNER")
    previous=owner/"backups"/("flow3-overlay-resume-"+prior)
    applied=read_doc(previous/"applied.json");started=read_doc(previous/"started.json")
    expected=applied["hashes"]
    need(applied["package"]==started["package"]==prior_pkg and expected==started["hashes"] and len(expected)==10,"PRIOR_INSTALL_BIND")
    targets={name:launcher if name==launcher.name else d2/name for name in expected}
    before={name:safe_file(path) for name,path in targets.items()}
    need({name:blob(b) for name,b in before.items()}==expected,"INSTALLED_DRIFT")
    stage=run/"stage";stage.mkdir()
    originals=run/"originals";originals.mkdir()
    changes=[]
    def fetch(row):return raw(pkg,row["path"],row["blob"])
    with ThreadPoolExecutor(max_workers=4) as pool:
        payload=dict(zip((x["path"] for x in manifest["files"]),pool.map(fetch,manifest["files"])))
    after=dict(expected)
    for row in manifest["delta"]:
        path=row["path"]; name=pathlib.PurePosixPath(path).name
        need(blob(payload[path])==row["new_blob"],"DELTA_BIND")
        if path.startswith("runner/"):
            need(name=="owner_movie_play.ps1","RUNNER_SCOPE")
            data=payload[path];(stage/name).write_bytes(data)
            changes.append({"name":name,"before":row["old_blob"],"after":row["new_blob"],"kind":"RUNNER_SOURCE"})
            continue
        need(name in expected and name in {"owner_session_bridge.py","owner_g2_discovery.py","owner_g2_support.py","owner_g2_inbox.py","owner_movie_handoff.py"},"OWNER_SCOPE")
        old=before[name]
        if row["kind"]=="context_patch":
            needle,replacement=recipe["rules"][0]
            orig=norm(old);n=needle.encode();replacement=replacement.encode()
            need(recipe["path"]==path and recipe["base_blob"]==row["old_blob"] and orig.count(n)==1,"BRIDGE_CONTEXT")
            old_src=raw(prior_pkg,path,row["old_blob"])
            need(old_src.count(n)==1 and old_src.replace(n,replacement,1)==payload[path],"BRIDGE_RECIPE")
            data=orig.replace(n,replacement,1)
            if old.count(b"\r\n") and old.count(b"\n")==old.count(b"\r\n"):data=data.replace(b"\n",b"\r\n")
        else:
            need(norm(old)==raw(prior_pkg,path,row["old_blob"]),"COPY_BASE_DRIFT")
            data=payload[path]
        ast.parse(data,filename=name)
        (stage/name).write_bytes(data);(originals/name).write_bytes(old)
        need(safe_file(stage/name)==data and safe_file(originals/name)==old,"STAGE_HASH")
        after[name]=blob(data)
        changes.append({"name":name,"before":blob(old),"after":blob(data),"kind":"OWNER_UPDATE"})
    need(len(changes)==6 and sum(x["kind"]=="OWNER_UPDATE" for x in changes)==5,"SCOPE_COUNT")
    # Staged imports on the already enrolled runtime, not an Owner startup.
    imp="import sys;sys.path[:0]=sys.argv[1:];import owner_session_bridge as b,owner_g2_inbox as i,owner_g2_support as s,owner_movie_handoff as h;assert b.poll_owner_g2_idle is i.poll_owner_g2_idle and callable(h.publish_library_receipt) and callable(s._ensure_browser_listener);print('IMPORT_PASS')"
    proc=subprocess.run([sys.executable,"-I","-B","-c",imp,str(stage),str(d2),str(app/"poc/p2-aisub"),str(app/"poc/p3-vietsub-trigger")],env=dict(os.environ,CI="true"),capture_output=True,timeout=30)
    (run/"import-stderr.txt").write_bytes(proc.stderr)
    need(proc.returncode==0 and b"IMPORT_PASS" in proc.stdout,"IMPORT_HOLD")
    def pid_ok(pid):
        return ps("$w=Get-CimInstance Win32_Process -Filter "+q("ProcessId="+str(pid))+";if($null -eq $w){throw 'PID'};$who=Invoke-CimMethod -InputObject $w -MethodName GetOwnerSid;if($who.ReturnValue -ne 0 -or $who.Sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or ([string]$w.CommandLine).IndexOf("+q(str(d2/"owner_p3_p4_entrypoint.py"))+",[StringComparison]::OrdinalIgnoreCase) -lt 0){throw 'PID_IDENTITY'};'OK'")=="OK"
    task_now=task_info()
    health=read_doc(owner/"agent-health.json");pid=health.get("pid")
    need(task_now=={"state":"RUNNING","enabled":True} and type(pid) is int and pid>0 and health.get("state")=="READY" and 0<=time.time()-health.get("observed_utc_epoch",0)<=30 and pid_ok(pid),"OWNER_HEARTBEAT")
    pending_g1=sum(1 for p in inbox.glob("event-*.json"))
    pending_g2=sum(1 for p in inbox.glob("g2-*.json") if re.fullmatch(r"g2-[a-f0-9]{32}\.json",p.name) and not p.with_suffix(".receipt.json").exists())
    marker=sum(1 for p in cache.rglob("browser.pending"))+sum(1 for p in owner.rglob("browser.pending"))
    inflight=sum(1 for p in state.rglob("*.inflight"))+sum(1 for p in state.rglob("active.lock"))
    provider=int(ps(r"""$p=@(Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(agy|antigravity|node|pwsh|pythonw?|py)(\.exe)?$' -and $_.CommandLine -match '(?i)TorrentTVVietsub[\\/].*(?:antigravity-cli|chrome-devtools-mcp|[\\/]agy(?:\.exe|\.cmd)?)' });$p.Count"""))
    write_doc("delta-plan.json",{"package":pkg,"candidate":candidate,"merged":merged,"prior_receipt":prior,"before":expected,"after":after,"changes":changes,"pid":pid,"heartbeat":health["observed_utc_epoch"],"pending_g1":pending_g1,"pending_g2":pending_g2,"markers":marker,"inflight":inflight,"provider":provider})
    need({name:blob(safe_file(path)) for name,path in targets.items()}==expected,"INSTALLED_CHANGED_DURING_READ")
    return "FLOW3_DUAL_PREFLIGHT_"+("BUSY" if any((pending_g1,pending_g2,marker,inflight,provider)) else "READY")+"_HASH10_U5_R1_HB1"
try: print(main())
except Hold as e: print("FLOW3_DUAL_PREFLIGHT_HOLD_"+str(e))
except Exception:
    import traceback
    (run/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("FLOW3_DUAL_PREFLIGHT_LOCAL_ERROR")
'@
$f=Join-Path $run 'deploy.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $run $spool $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
}catch{[IO.File]::WriteAllText((Join-Path $run 'host-private-error.txt'),($_|Out-String),[Text.UTF8Encoding]::new($false))}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
