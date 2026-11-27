Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'NONCE_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('NativeBrowserTest\g21-r4-owner-reconcile-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$head='687511732e84ef76becc2004e97c0ee9c6e0170b'
$code='G21_V33_LOCAL_ERROR'
try {
    $py=@'
import pathlib,sys,json,os,re,subprocess,shutil,urllib.request,hashlib,time
root,run,spool=map(pathlib.Path,sys.argv[1:4])
head=sys.argv[4];nonce=sys.argv[5]
def write(p,x):
    p.write_text(json.dumps(x,ensure_ascii=True,indent=2),encoding="utf-8")
def ps(cmd,timeout=15):
    return subprocess.run(["pwsh","-NoProfile","-NonInteractive","-Command",cmd],
        capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=timeout,check=True).stdout.strip()
def task_state():
    return ps("(Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -ErrorAction Stop).State.ToString()")
def pages():
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open("http://127.0.0.1:9555/json/list",timeout=3) as f:
        return [p for p in json.load(f) if p.get("type")=="page"]
def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else "MISSING"
def main():
    # Resolve the exact R4 HOLD, never replay a possibly invoked provider.
    def read_doc(p):
        if not p.is_file() or p.is_symlink() or not 0<p.stat().st_size<=4096:return {}
        return json.loads(p.read_text(encoding="utf-8-sig"))
    prior_nonces=[]
    for p in (spool/"History").glob("receipt-*.json"):
        d=read_doc(p);n=d.get("nonce","")
        if d.get("source_commit")!="c4fbf5e2f652502e06d6d49d7a3a82ef077689f6" or d.get("result")!="SUCCESS" or not re.fullmatch("[a-f0-9]{32}",str(n)):continue
        q=read_doc(spool/"History"/("request-"+n+".json"))
        stage=read_doc(spool/"Receipts"/("odyssey-stage-"+n+".json"))
        if q.get("nonce")==n and q.get("source_commit")==d["source_commit"] and stage.get("nonce")==n and stage.get("reason")=="G21_R4_RESIDUAL_HOLD":prior_nonces.append(n)
    if len(prior_nonces)!=1:return "G21_RECOVERY_PRIOR_RECEIPT_HOLD"
    oldrun=root/"NativeBrowserTest"/("g21-v33-r4-live-r1-"+prior_nonces[0])
    if (oldrun/"isolated-cache").exists() or (oldrun/"ACCEPTANCE.json").exists() or (oldrun/"OWNER_RECOVERY.json").exists():
        return "G21_RECOVERY_PRIOR_EFFECT_HOLD"
    # Checkout only exact source, no installed application writes.
    checkout=run/"candidate";checkout.mkdir()
    env=dict(os.environ,GIT_TERMINAL_PROMPT="0",GCM_INTERACTIVE="never")
    git=shutil.which("git")
    if not git:return "G21_V33_GIT_UNAVAILABLE"
    def g(*a):
        p=subprocess.run([git,*a],cwd=checkout,env=env,capture_output=True,text=True,
            encoding="utf-8",errors="replace",timeout=60)
        with (run/"git-private.txt").open("a",encoding="utf-8") as f:f.write(p.stdout+"\n"+p.stderr+"\n")
        if p.returncode:raise RuntimeError("GIT_"+a[0].upper())
        return p.stdout.strip()
    try:
        g("init","-q");g("fetch","--depth=1","--no-tags","https://github.com/trung-via/torrent-tv-vietsub.git",head)
        if g("rev-parse","FETCH_HEAD")!=head:return "G21_V33_SOURCE_DRIFT"
        g("checkout","--detach","FETCH_HEAD")
        if g("rev-parse","HEAD")!=head:return "G21_V33_SOURCE_DRIFT"
    except (RuntimeError,subprocess.TimeoutExpired):return "G21_V33_SOURCE_FETCH_HOLD"
    owner=root/"OwnerBridge"
    state=root/"P2"/"auto-lean120-state"
    inbox=owner/"inbox"
    health=owner/"agent-health.json"
    snap=spool.parent/"OwnerBridge"/"Diagnostics"/"owner-snapshot.json"
    def obj(p,limit):
        if not p.is_file() or p.is_symlink() or not 0<p.stat().st_size<=limit:
            raise ValueError("OBSERVATION_INVALID")
        return json.loads(p.read_text(encoding="utf-8-sig"))
    def pending():
        if not inbox.is_dir() or inbox.is_symlink() or not state.is_dir() or state.is_symlink():
            raise ValueError("WORK_STATE_UNKNOWN")
        return (sum(1 for _ in inbox.glob("event-*.json")),
                sum(1 for _ in state.rglob("*.inflight")),
                sum(1 for p in (root/"P2",owner,root/"subtitle-trials") for _ in p.rglob("browser.pending")))
    def process_inventory(owner_pid=None):
        # Scope by actual process ancestry or explicit Torrent TV/9555 command line.
        # Other project AGY/Codex processes are not stopped or counted as G1 work.
        rows=json.loads(ps(r"""@(Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,Name,CommandLine)|ConvertTo-Json -Compress -Depth 3"""))
        if isinstance(rows,dict):rows=[rows]
        ids={int(x["ProcessId"]):x for x in rows}
        def descendant(x):
            seen=set()
            while x is not None:
                p=int(x["ParentProcessId"])
                if owner_pid is not None and p==owner_pid:return True
                if p in seen or p<=0:return False
                seen.add(p);x=ids.get(p)
            return False
        active=other=runtime=0
        for x in rows:
            pid=int(x["ProcessId"]);cmd=x.get("CommandLine") or "";name=(x.get("Name") or "").lower()
            if pid in (os.getpid(),owner_pid):continue
            # Exclude only the inventory query child of this exact script.
            if int(x["ParentProcessId"])==os.getpid() and name=="pwsh.exe":continue
            explicit=bool(re.search(r"(?i)(?:--browser-url(?:=|\s+)http://127\.0\.0\.1:9555|TorrentTVVietsub[\\/].*(?:antigravity-cli|chrome-devtools-mcp|TTV_AGY_CLI))",cmd))
            provider=bool(re.search(r"(?i)^(?:agy|antigravity|gemini|codex)(?:\.exe)?$",name) or re.search(r"(?i)chrome-devtools-mcp|antigravity-cli|TTV_AGY_CLI",cmd))
            if descendant(x) or explicit:active+=1
            elif provider:other+=1
            if re.search(r"(?i)TorrentTVVietsub[\\/].*(?:start-owner-session-agent\.ps1|owner_p3_p4_entrypoint\.py|owner_session_bridge\.py)",cmd):
                runtime+=1
        return active,other,runtime
    def providers(owner_pid=None):
        return process_inventory(owner_pid)[0]
    def alive(pid):
        return ps("if(Get-Process -Id "+str(pid)+" -ErrorAction SilentlyContinue){'YES'}else{'NO'}")=="YES"
    def observe_idle():
        p,i,b=pending()
        if p or i or b:raise ValueError("OPEN_WORK_P"+str(p)+"_I"+str(i)+"_B"+str(b))
        if task_state().upper()=="RUNNING":
            h=obj(health,512);d=obj(snap,4096)
            if (h.get("schema")!="TTV-OWNER-AGENT-HEALTH-V1" or h.get("state")!="READY"
                or type(h.get("pid")) is not int or h["pid"]<=0 or not alive(h["pid"])
                or not 0<=time.time()-h.get("observed_utc_epoch",0)<=12
                or d.get("schema") not in ("TTV-HOSTOPS-OWNER-SNAPSHOT-V2","TTV-HOSTOPS-OWNER-SNAPSHOT-V3","TTV-HOSTOPS-OWNER-SNAPSHOT-V4")
                or d.get("status")!="READY_FRESH" or not 0<=time.time()-d.get("snapshot_utc_epoch",0)<=12
                or d.get("p3_state") not in ("FRESH_OFF","FRESH_OTHER","FRESH_INACTIVE","STALE","MISSING")
                or d.get("p2",{}).get("status")!="CLEAR"
                or d["p2"].get("pending_events")!=0 or d["p2"].get("inflight_count")!=0):
                raise ValueError("IDLE_NOT_VERIFIED")
            active,other,runtime=process_inventory(h["pid"])
            write(run/"PROCESS_SCOPE.json",{"torrent_tv_active":active,"other_provider_processes":other,"owner_runtime":runtime})
            if active:raise ValueError("PROVIDER_ACTIVE")
            return h["pid"]
        if providers():raise ValueError("PROVIDER_ACTIVE")
        return None
    # Reuse the existing task identity guards from the pinned checkout.
    def quote(v):return "'"+str(v).replace("'","''")+"'"
    guards=checkout/"poc"/"p2-sub-discovery"
    control=r"""$ErrorActionPreference='Stop'; . """+quote(guards/"owner-task-principal-identity.ps1")+r"""; . """+quote(guards/"owner-task-action-identity.ps1")+r"""; $id=[Security.Principal.WindowsIdentity]::GetCurrent(); $logged=(Get-CimInstance Win32_ComputerSystem).UserName;
    if(-not $id.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)){throw 'OWNER_IDENTITY'}
    $task=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\' -ErrorAction Stop
    if(-not (Test-TTVOwnerTaskPrincipal -Principal $task.Principal -ExpectedSid $id.User.Value) -or -not (Get-TTVOwnerTaskActionState -Task $task -ExpectedExecutable (Get-TTVOwnerCurrentPwshExecutable) -ExpectedLauncher """+quote(owner/"start-owner-session-agent.ps1")+r""").Accepted){throw 'OWNER_TASK_IDENTITY'}
    """
    def task_cmd(cmd):
        return ps(control+"; "+cmd,30)
    # Reuse the existing owner-control-v3 exact worker identification.
    worker_guard=r"""$base=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'; $owner=Join-Path $base 'OwnerBridge'; $app=Join-Path $owner 'app'; $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
function Workers{
 $paths=@((Join-Path $app 'poc\p2-sub-discovery\owner_p3_p4_entrypoint.py'),(Join-Path $app 'poc\p2-sub-discovery\owner_session_bridge.py'))
 foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe' OR Name='py.exe'")){
   if([string]$p.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'){continue}
   $hits=@($paths|Where-Object{([string]$p.CommandLine).IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0})
   $who=Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid
   if($hits.Count -ne 1 -or $who.ReturnValue -ne 0 -or $who.Sid -cne $sid -or -not $p.CreationDate){throw 'WORKER_IDENTITY'}
   $p
 }
}
"""
    def worker_snapshot():
        raw=task_cmd(worker_guard+r"""$w=@(Workers); ConvertTo-Json -InputObject @($w|Select-Object ProcessId,CreationDate,CommandLine) -Compress -Depth 3""")
        data=json.loads(raw)
        if not isinstance(data,list):raise ValueError("WORKERS_SCHEMA")
        return data
    def stop_residual(known):
        # After scheduler stop, only exact previous worker identities may be stopped.
        encoded=json.dumps(known,separators=(",",":"))
        cmd=worker_guard+r"""$before=@(ConvertFrom-Json -InputObject """+quote(encoded)+r"""); if((Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\').State.ToString() -cne 'Disabled'){throw 'TASK_NOT_DISABLED'}
        foreach($w in @(Workers)){
            $same=@($before|Where-Object{[int]$_.ProcessId -eq [int]$w.ProcessId -and ([datetime]$_.CreationDate).ToUniversalTime() -eq ([datetime]$w.CreationDate).ToUniversalTime() -and $_.CommandLine -ceq $w.CommandLine})
            if($same.Count -ne 1){throw 'WORKER_DRIFT'}
            Stop-Process -Id ([int]$w.ProcessId) -Force -ErrorAction Stop
        }; 'STOP_CHECKED'"""
        task_cmd(cmd)
    # Diagnose and repair only the exact Owner worker/task lifecycle; no AGY or TV.
    def busy(known):
        ids={int(w["ProcessId"]) for w in known}
        rows=json.loads(ps(r"""@(Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,Name,CommandLine)|ConvertTo-Json -Compress -Depth 3"""))
        if isinstance(rows,dict):rows=[rows]
        table={int(x["ProcessId"]):x for x in rows}
        for x in rows:
            pid=int(x["ProcessId"]);cmd=x.get("CommandLine") or ""
            if pid in ids or pid==os.getpid() or int(x["ParentProcessId"])==os.getpid():continue
            if re.search(r"(?i)(?:--browser-url(?:=|\s+)http://127\.0\.0\.1:9555|TorrentTVVietsub[\\/].*(?:antigravity-cli|chrome-devtools-mcp|TTV_AGY_CLI))",cmd):return True
            parent=int(x["ParentProcessId"]);seen=set()
            while parent>0 and parent not in seen:
                if parent in ids:return True
                seen.add(parent)
                if parent not in table:break
                parent=int(table[parent]["ParentProcessId"])
        return False
    def safe_idle(known):
        counts=pending()
        d=read_doc(snap)
        p3=d.get("p3_state","UNKNOWN")
        p2=d.get("p2",{})
        # The previous snapshot may be stale after a stopped launcher, but an
        # observed active/unknown request is never discarded. Durable claims
        # and actual descendant processes are checked independently twice.
        valid=d.get("schema") in ("TTV-HOSTOPS-OWNER-SNAPSHOT-V2","TTV-HOSTOPS-OWNER-SNAPSHOT-V3","TTV-HOSTOPS-OWNER-SNAPSHOT-V4")
        write(run/"IDLE_OBSERVATION.json",{"counts":counts,"p3":p3,"p2_status":p2.get("status"),"worker_count":len(known),"snapshot_age":time.time()-d.get("snapshot_utc_epoch",0),"busy":busy(known)})
        return counts==(0,0,0) and valid and p3 in ("FRESH_OFF","FRESH_OTHER","FRESH_INACTIVE","STALE","MISSING") and p2.get("status")=="CLEAR" and p2.get("pending_events")==0 and p2.get("inflight_count")==0 and not busy(known)
    def ready(since=0):
        h=read_doc(health);workers=worker_snapshot()
        if task_state().upper()!="RUNNING" or h.get("schema")!="TTV-OWNER-AGENT-HEALTH-V1" or h.get("state")!="READY":return False
        stamp=h.get("observed_utc_epoch",0)
        return type(h.get("pid")) is int and 0<=time.time()-stamp<=12 and stamp>=since and sum(int(w["ProcessId"])==h["pid"] for w in workers)==1
    prior=task_state().upper()
    if prior not in ("RUNNING","READY","DISABLED"):return "G21_RECOVERY_TASK_STATE_HOLD"
    task_cmd("'VERIFIED'")
    known=worker_snapshot()
    if prior=="RUNNING":
        if ready():return "G21_RECOVERY_ALREADY_READY"
        return "G21_RECOVERY_RUNNING_UNVERIFIED_HOLD"
    if not safe_idle(known):
        p,i,b=pending()
        return "G21_RECOVERY_IDLE_HOLD_P"+str(p)+"_I"+str(i)+"_B"+str(b)
    time.sleep(2)
    if task_state().upper()!=prior or worker_snapshot()!=known or not safe_idle(known):return "G21_RECOVERY_STATE_CHANGED_HOLD"
    # Journal before mutation, preserve previous logs/claims/cache and unrelated processes.
    journal=run/"OWNER_RECOVERY.json"
    write(journal,{"prior":prior,"worker_count":len(known),"stage":"PREPARED"})
    task_cmd("Disable-ScheduledTask -InputObject $task|Out-Null")
    if task_state().upper()!="DISABLED":return "G21_RECOVERY_DISABLE_HOLD"
    if worker_snapshot()!=known or not safe_idle(known):
        if prior!="DISABLED":task_cmd("Enable-ScheduledTask -InputObject $task|Out-Null")
        write(journal,{"prior":prior,"stage":"NO_STOP_STATE_CHANGED"})
        return "G21_RECOVERY_STATE_CHANGED_HOLD"
    if known:stop_residual(known)
    for _ in range(20):
        if not worker_snapshot() and task_state().upper()=="DISABLED":break
        time.sleep(.5)
    else:
        write(journal,{"prior":prior,"stage":"STOP_UNVERIFIED"})
        return "G21_RECOVERY_STOP_UNVERIFIED"
    if pending()!=(0,0,0) or busy([]):
        write(journal,{"prior":prior,"stage":"STOP_WORK_HOLD"})
        return "G21_RECOVERY_STOP_WORK_HOLD"
    write(journal,{"prior":prior,"stage":"QUIESCENT"})
    since=int(time.time())-1
    task_cmd("Enable-ScheduledTask -InputObject $task|Out-Null")
    if task_state().upper()!="RUNNING":task_cmd("Start-ScheduledTask -InputObject $task")
    for _ in range(45):
        try:
            if ready(since):
                write(journal,{"prior":prior,"stage":"RESTORED","removed_workers":len(known)})
                return "G21_OWNER_RECOVERED_W"+str(len(known))
        except Exception:pass
        time.sleep(1)
    write(journal,{"prior":prior,"stage":"START_UNVERIFIED"})
    return "G21_RECOVERY_START_UNVERIFIED"

try:
    import urllib.parse
    print(main())
except Exception as exc:
    import traceback
    (run/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("G21_V33_LOCAL_ERROR")
'@
    $f=Join-Path $run 'v33.py'
    [IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
    $out=@(& py -3 -I -B $f $root $run $spool $head $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
    if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
} catch {
    [IO.File]::WriteAllText((Join-Path $run 'host-private-error.txt'),($_|Out-String),[Text.UTF8Encoding]::new($false))
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
