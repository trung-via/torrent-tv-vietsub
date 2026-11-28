# Resume applied G2 delta: archive exactly one pending request, start and observe heartbeat. No install or provider test.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('OwnerBridge\backups\g2-start-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='G2_START_LOCAL_ERROR'
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
def read_doc(p):
    return json.loads(safe_file(p).decode("utf-8-sig"))
def pending_files():
    a=list(inbox.glob("event-*.json"))
    b=[p for p in inbox.glob("g2-*.json") if re.fullmatch(r"g2-[a-f0-9]{32}\.json",p.name) and not p.with_suffix(".claim").exists() and not p.with_suffix(".receipt.json").exists()]
    return a+b
def main():
    idle()
    # Bind to the original completed deployment and its private applied manifest.
    matches=set()
    for folder in (spool/"History",spool/"Receipts"):
        for p in folder.glob("receipt*.json"):
            try:r=read_doc(p)
            except (OSError,ValueError,Hold):continue
            n=r.get("nonce","")
            if r.get("source_commit")!="0ecf5774c267da08b9d79659b0fae360fb14ddd5" or r.get("result")!="SUCCESS" or not re.fullmatch(r"[a-f0-9]{32}",str(n)):continue
            s=read_doc(spool/"Receipts"/("odyssey-stage-"+n+".json"))
            if s.get("nonce")==n and s.get("reason")=="G2_DEPLOY_APPLIED_START_HOLD_PENDING_1":matches.add(n)
    need(len(matches)==1,"ORIGINAL_RECEIPT_HOLD")
    prior=owner/"backups"/("g2-delta-"+next(iter(matches)))
    applied=read_doc(prior/"applied.json"); manifest=read_doc(prior/"manifest.json")
    names=set(new)|set(shared)|{launcher.name}
    hashes=applied.get("hashes",{})
    need(applied.get("head")==head and manifest.get("head")==head and set(hashes)==names,"DEPLOY_MANIFEST_HOLD")
    targets={name:launcher if name==launcher.name else d2/name for name in names}
    def verify():
        need(all(blob(safe_file(p))==hashes[name]==manifest["files"][name]["after"] for name,p in targets.items()),"INSTALLED_HASH_DRIFT")
    verify()
    # No unresolved earlier start attempt. Never repeat archive or start blindly.
    for old in (owner/"backups").glob("g2-start-*"):
        if old!=run and ((old/"archived.json").exists() or (old/"start-attempt.json").exists()):raise Hold("PRIOR_START_EFFECT_RECONCILE")
    items=pending_files();need(len(items)==1,"PENDING_COUNT_CHANGED")
    p=items[0]; data=safe_file(p); kind="G1" if p.name.startswith("event-") else "G2"
    need(bool(re.fullmatch(r"(?:event-[A-Za-z0-9_-]+|g2-[a-f0-9]{32})\.json",p.name)),"PENDING_NAME")
    # Preserve the exact original bytes outside the polled inbox. Do not remove
    # claims/retry records/checkpoints; no replay or reclassification.
    archive=run/"parked";archive.mkdir()
    dst=archive/p.name
    write_doc("archive-intent.json",{"kind":kind,"name":p.name,"blob":blob(data),"prior":prior.name})
    idle();verify()
    need(pending_files()==[p] and safe_file(p)==data and not dst.exists(),"PENDING_DRIFT")
    os.rename(p,dst)
    need(safe_file(dst)==data and not p.exists(),"ARCHIVE_HASH")
    write_doc("archived.json",{"kind":kind,"name":p.name,"blob":blob(data)})
    idle();verify()
    need(not pending_files(),"NEW_PENDING_AFTER_ARCHIVE")
    since=int(time.time())
    write_doc("start-attempt.json",{"head":head,"since":since})
    ps(r"""Enable-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'|Out-Null;Start-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'""")
    for _ in range(45):
        time.sleep(1)
        try:
            h=read_doc(owner/"agent-health.json");pid=int(h["pid"])
            if h["state"]!="READY" or int(h["observed_utc_epoch"])<since or pid<=0 or task()!="RUNNING":continue
            s=ps("$w=Get-CimInstance Win32_Process -Filter "+q("ProcessId="+str(pid))+";if($null -eq $w){throw 'PID'};$who=Invoke-CimMethod -InputObject $w -MethodName GetOwnerSid;if($who.ReturnValue -ne 0 -or $who.Sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or ([string]$w.CommandLine).IndexOf("+q(str(d2/"owner_p3_p4_entrypoint.py"))+",[StringComparison]::OrdinalIgnoreCase) -lt 0){throw 'PID_IDENTITY'};'OK'")
            if s!="OK":continue
            verify()
            write_doc("started.json",{"head":head,"pid":pid,"observed":h["observed_utc_epoch"],"archived_kind":kind})
            return "G2_START_PASS_ARCHIVED_"+kind+"_8FILES_FRESH_OWNER"
        except (OSError,ValueError,KeyError,Hold):continue
    return "G2_START_ARCHIVED_"+kind+"_HEARTBEAT_UNVERIFIED"
try: print(main())
except Hold as e: print("G2_START_HOLD_"+str(e))
except Exception:
    import traceback
    (run/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("G2_START_LOCAL_ERROR")
'@
$f=Join-Path $run 'deploy.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $run $spool $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
}catch{[IO.File]::WriteAllText((Join-Path $run 'host-private-error.txt'),($_|Out-String),[Text.UTF8Encoding]::new($false))}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
