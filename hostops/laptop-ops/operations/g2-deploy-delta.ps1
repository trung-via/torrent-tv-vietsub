# Approved standalone G2 delta; no provider, torrent, TV, APK or G1-link actions.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('OwnerBridge\backups\g2-delta-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='G2_DEPLOY_LOCAL_ERROR'
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
def idle():
    need(task()=="DISABLED","TASK_NOT_DISABLED")
    for p in (inbox,state,cache,d2):
        need(p.is_dir() and not p.is_symlink(),"STATE_ROOT")
    need(not any(state.rglob("*.inflight")) and not any(state.rglob("active.lock")) and not any(cache.rglob("browser.pending")) and not any(owner.rglob("browser.pending")),"OPEN_EFFECT")
    # No other project's provider processes are touched.
    s=ps(r"""$p=@(Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(pythonw?|py|pwsh|agy|antigravity|node)(\.exe)?$' -and $_.CommandLine -match '(?i)TorrentTVVietsub[\\/].*(?:owner_p3_p4_entrypoint\.py|owner_session_bridge\.py|start-owner-session-agent\.ps1|antigravity-cli|chrome-devtools-mcp)' }); $p.Count""")
    # Inventory command is itself a pwsh process containing the regex text, but
    # does not contain a literal TorrentTVVietsub path before those filenames.
    need(s=="0","WORKER_ACTIVE")
def pending():
    # Preserve all events. Starting with an old unconsumed event could call AGY.
    a=list(inbox.glob("event-*.json"))
    b=[p for p in inbox.glob("g2-*.json") if re.fullmatch(r"g2-[a-f0-9]{32}\.json",p.name) and not p.with_suffix(".claim").exists() and not p.with_suffix(".receipt.json").exists()]
    return len(a)+len(b)
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
    idle()
    need(blob(norm(safe_file(d2/"agy_v13_browser_evidence.py")))=="37913c008f2cc521494ac076fe1e7b8fa2ba08b2","BROWSER_BASELINE")
    stage=run/"stage";stage.mkdir()
    originals={};targets={};modes={}
    for name,sha in new.items():
        p=d2/name; b=source(head,name,sha)
        if p.exists():need(norm(safe_file(p))==b,"NEW_FILE_CONFLICT");originals[p]=safe_file(p)
        else:need(not p.is_symlink(),"FILE_IDENTITY");originals[p]=None
        targets[p]=b;modes[name]="new"
    for name,(a,b) in shared.items():
        p=d2/name; old=safe_file(p);orig=source(base,name,a);target=source(head,name,b)
        originals[p]=old;targets[p]=apply_context(old,orig,target)
        modes[name]="exact" if norm(old)==orig or norm(old)==target else "context"
    old=safe_file(launcher);txt=old.decode("utf-8-sig")
    matches=list(re.finditer(r"(?im)^([ \t]*)\$env:TTV_NATIVE_V13\s*=\s*(['\"])1\2[ \t]*(?=\r?$)",txt))
    need(len(matches)==1 and not re.search(r"(?i)TTV_G2_WARM",txt),"LAUNCHER_FLAG_CONFLICT")
    m=matches[0]; nl="\r\n" if "\r\n" in txt else "\n"
    changed=txt[:m.end()]+nl+m.group(1)+"$env:TTV_G2_WARM = '1'"+txt[m.end():]
    originals[launcher]=old;targets[launcher]=(b"\xef\xbb\xbf" if old.startswith(b"\xef\xbb\xbf") else b"")+changed.encode()
    for p,b in targets.items():
        (stage/p.name).write_bytes(b)
        if p.suffix==".py":ast.parse(b.decode("utf-8-sig"),filename=p.name)
    ps("$tokens=$null;$errs=$null;[System.Management.Automation.Language.Parser]::ParseFile("+q(stage/launcher.name)+",[ref]$tokens,[ref]$errs)|Out-Null;if(@($errs).Count){throw 'PARSE'}")
    # Imports only; do not instantiate a producer, contact AGY, or poll the inbox.
    imp="import sys;sys.path[:0]=sys.argv[1:];import agy_owner_warm_session,agy_v13_native_producer,owner_g2_discovery,owner_g2_submit,owner_movie_handoff,owner_session_bridge,owner_p3_p4_runtime;assert callable(agy_v13_native_producer.NativeBrowserProducer.discover_movies);assert callable(owner_session_bridge.poll_private_g2);assert callable(owner_movie_handoff.publish_library_receipt);print('G2_IMPORT_PASS')"
    proc=subprocess.run([sys.executable,"-I","-B","-c",imp,str(stage),str(d2),str(app/"poc/p2-aisub"),str(app/"poc/p3-vietsub-trigger")],capture_output=True,timeout=45)
    (run/"import-private.txt").write_bytes(proc.stderr)
    need(proc.returncode==0 and b"G2_IMPORT_PASS" in proc.stdout,"IMPORT_HOLD")
    saved=run/"originals";saved.mkdir()
    for p,b in originals.items():
        if b is not None:(saved/p.name).write_bytes(b);need((saved/p.name).read_bytes()==b,"BACKUP_HASH")
    write_doc("manifest.json",{"head":head,"base":base,"files":{p.name:{"before":blob(b) if b is not None else None,"after":blob(targets[p])} for p,b in originals.items()},"modes":modes})
    applied=[];start_attempt=False
    try:
        idle()
        for p,b in targets.items():
            old=originals[p]
            need((safe_file(p)==old) if old is not None else not p.exists(),"INSTALL_DRIFT")
            if old==b:continue
            replace(p,b);applied.append(p);need(safe_file(p)==b,"INSTALL_HASH")
        idle()
        write_doc("applied.json",{"head":head,"hashes":{p.name:blob(safe_file(p)) for p in targets}})
        if pending():return "G2_DEPLOY_APPLIED_START_HOLD_PENDING_"+str(pending())
        since=int(time.time())
        start_attempt=True
        ps(r"""Enable-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'|Out-Null;Start-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'""")
        for _ in range(45):
            time.sleep(1)
            try:
                h=json.loads(safe_file(owner/"agent-health.json").decode("utf-8-sig"));pid=int(h["pid"])
                if h["state"]!="READY" or int(h["observed_utc_epoch"])<since-1 or pid<=0 or task()!="RUNNING":continue
                s=ps("$w=Get-CimInstance Win32_Process -Filter "+q("ProcessId="+str(pid))+";if($null -eq $w){throw 'PID'};$who=Invoke-CimMethod -InputObject $w -MethodName GetOwnerSid;if($who.ReturnValue -ne 0 -or $who.Sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or ([string]$w.CommandLine).IndexOf("+q(str(d2/"owner_p3_p4_entrypoint.py"))+",[StringComparison]::OrdinalIgnoreCase) -lt 0){throw 'PID_IDENTITY'};'OK'")
                if s!="OK":continue
                need(all(safe_file(p)==b for p,b in targets.items()),"RUNNING_HASH_DRIFT")
                write_doc("started.json",{"head":head,"pid":pid,"observed":h["observed_utc_epoch"]})
                return "G2_DEPLOY_PASS_8FILES_FRESH_OWNER"
            except (OSError,ValueError,KeyError,Hold):continue
        return "G2_DEPLOY_APPLIED_START_UNVERIFIED"
    except Exception:
        if start_attempt:raise Hold("APPLIED_START_UNKNOWN_NO_REPLAY")
        try:
            idle()
            for p in reversed(applied):
                need(safe_file(p)==targets[p],"ROLLBACK_DRIFT")
                if originals[p] is None:p.unlink()
                else:replace(p,originals[p])
            write_doc("rollback.json",{"restored":True})
        except Exception:raise Hold("ROLLBACK_HOLD")
        raise
try: print(main())
except Hold as e: print("G2_DEPLOY_HOLD_"+str(e))
except Exception:
    import traceback
    (run/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("G2_DEPLOY_LOCAL_ERROR")
'@
$f=Join-Path $run 'deploy.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $run $spool $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
}catch{[IO.File]::WriteAllText((Join-Path $run 'host-private-error.txt'),($_|Out-String),[Text.UTF8Encoding]::new($false))}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
