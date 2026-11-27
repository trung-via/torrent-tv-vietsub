Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'NONCE_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('NativeBrowserTest\g21-r5-acceptance-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$head='660cad50141a47ebfc3069de398b934529f731f1'
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
    # Continue the exact successful recovery; no repeat of the residual cleanup.
    def read_doc(p):
        if not p.is_file() or p.is_symlink() or not 0<p.stat().st_size<=1048576:return {}
        return json.loads(p.read_text(encoding="utf-8-sig"))
    def paired(source,reason):
        found=[]
        for p in (spool/"History").glob("receipt-*.json"):
            d=read_doc(p);n=d.get("nonce","")
            if d.get("source_commit")!=source or d.get("result")!="SUCCESS" or not re.fullmatch("[a-f0-9]{32}",str(n)):continue
            q=read_doc(spool/"History"/("request-"+n+".json"))
            s=read_doc(spool/"Receipts"/("odyssey-stage-"+n+".json"))
            if q.get("nonce")==n and q.get("source_commit")==source and s.get("nonce")==n and s.get("reason")==reason:found.append(n)
        return found
    # Read the exact prior R4 terminal evidence, without repeating R4 or recovery.
    previous=paired("93874fb147b7031215df8b228c970576d1ef8546","G21_V33_CONSUMER_REVIEW_REQUIRED")
    observed=paired("9184b357930515c5bc3ebf6b312965941a8ea2ec","G21_READ_FINAL_JSON_T2_F1_R1_M6_E0_S1_P0_BY_JY_OREADY")
    if len(previous)!=1 or len(observed)!=1:return "G21_R5_PRIOR_RECEIPT_HOLD"
    oldrun=root/"NativeBrowserTest"/("g21-r4-acceptance-"+previous[0])
    if read_doc(oldrun/"OWNER_RECOVERY.json").get("stage")!="RESTORED" or not (oldrun/"ACCEPTANCE.json").is_file():
        return "G21_R5_PRIOR_EFFECT_HOLD"
    # Any previous R5 provider window is a hard stop; preserve all evidence.
    for p in (root/"NativeBrowserTest").glob("g21-r5-acceptance-*"):
        if p!=run and (p/"isolated-cache").exists():return "G21_R5_PRIOR_PROVIDER_EFFECT_HOLD"
    # New HEAD requires only a new isolated checkout, not installation.
    checkout=run/"candidate";checkout.mkdir()
    env=dict(os.environ,GIT_TERMINAL_PROMPT="0",GCM_INTERACTIVE="never")
    git=shutil.which("git")
    if not git:return "G21_R5_GIT_UNAVAILABLE"
    def g(*a):
        p=subprocess.run([git,*a],cwd=checkout,env=env,capture_output=True,text=True,
            encoding="utf-8",errors="replace",timeout=60)
        with (run/"git-private.txt").open("a",encoding="utf-8") as f:f.write(p.stdout+"\n"+p.stderr+"\n")
        if p.returncode:raise RuntimeError("GIT_"+a[0].upper())
        return p.stdout.strip()
    try:
        g("init","-q");g("fetch","--depth=1","--no-tags","https://github.com/trung-via/torrent-tv-vietsub.git",head)
        if g("rev-parse","FETCH_HEAD")!=head:return "G21_R5_SOURCE_DRIFT"
        g("checkout","--detach","FETCH_HEAD")
        if g("rev-parse","HEAD")!=head:return "G21_R5_SOURCE_DRIFT"
    except (RuntimeError,subprocess.TimeoutExpired):return "G21_R5_SOURCE_FETCH_HOLD"
    sys.path[:0]=[str(checkout/"poc/p2-sub-discovery"),str(checkout/"poc/p2-aisub")]
    from owner_g2_submit import submit_private_file
    from owner_session_bridge import poll_private_g2, install_owner_full_diagnostics
    from agy_v13_native_producer import NativeBrowserProducer
    # Real writer publication in isolated owner inbox, no live Owner effect.
    private=run/"isolated-owner";private.mkdir()
    install_owner_full_diagnostics(private)
    payload={"schema":"TTV-OWNER-G2-METADATA-V1","request_id":nonce,
       "authorized_source":True,"source_url":"https://www.sunpictures.in/?sunpict_movies=jailer2",
       "queries":[{"title":"Jailer 2","year":2026},{"title":"Jailer 2","year":2026}]}
    req=run/"private-request.json";write(req,payload)
    first=submit_private_file(private,req);second=submit_private_file(private,req)
    event=private/"inbox"/("g2-"+nonce+".json")
    if first!=nonce or second!=nonce or not event.is_file():return "G21_V33_WRITER_HOLD"
    # Record structural prior evidence only; no model call here.
    preflight={"head":head,"writer_idempotent":True,"owner_task":task_state()}
    try:
        before=pages()
        preflight["pages"]=len(before)
        preflight["baseline_opensubtitles"]=sum(urllib.parse.urlsplit(p.get("url","")).hostname in ("opensubtitles.org","www.opensubtitles.org") for p in before)
    except Exception:
        before=[];preflight["pages"]=-1
    write(run/"PREFLIGHT.json",preflight)
    if len(before)!=1:return "G21_V33_R4_BASE_TAB_COUNT_"+str(len(before))
    original=before[0]
    blank=original.get("url") in ("about:blank","chrome://newtab/","chrome://new-tab-page/")
    if preflight.get("baseline_opensubtitles")!=1 and not blank:
        return "G21_V33_R4_BASE_OTHER_TAB_HOLD"
    if not re.fullmatch(r"[A-Fa-f0-9]{32}",str(original.get("id",""))):
        return "G21_V33_R4_BASE_ID_HOLD"
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
            if busy(worker_snapshot()):raise ValueError("PROVIDER_ACTIVE")
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
    prior=task_state().upper()
    if prior!="RUNNING":return "G21_ACCEPTANCE_OWNER_NOT_RUNNING_HOLD"
    try:
        task_cmd("'VERIFIED'")
        oldpid=observe_idle()
        known=worker_snapshot()
        if prior=="RUNNING" and not any(int(w["ProcessId"])==oldpid for w in known):return "G21_R4_WORKER_ID_HOLD"
        if prior!="RUNNING" and known:return "G21_R4_RESIDUAL_HOLD"
        time.sleep(1)
        if task_state().upper()!=prior or observe_idle()!=oldpid or worker_snapshot()!=known:
            return "G21_V33_R4_IDLE_CHANGED"
    except Exception as e:
        write(run/"IDLE_HOLD.json",{"reason":str(e)})
        reason=str(e)
        return "G21_V33_R4_IDLE_"+reason if re.fullmatch(r"(?:OPEN_WORK_P\d+_I\d+_B\d+|PROVIDER_ACTIVE|IDLE_NOT_VERIFIED)",reason) else "G21_V33_R4_IDLE_HOLD"
    profile=root/"NativeBrowserTest"/"CDP9555Profile"
    from agy_v13_native_producer import _ensure_browser_listener
    try:
        _ensure_browser_listener(shutil.which("pwsh"),profile)
    except Exception:
        return "G21_V33_R4_BROWSER_HOLD"
    # Journal original task state BEFORE any task mutation; never alter app/cache.
    write(run/"OWNER_RECOVERY.json",{"prior":prior,"pid":oldpid,"stage":"PREPARED"})
    changed=False
    outcome="G21_V33_R4_LOCAL_ERROR"
    try:
        if prior!="DISABLED":
            changed=True
            task_cmd("Disable-ScheduledTask -InputObject $task|Out-Null")
            if prior=="RUNNING":
                if pending()!=(0,0,0) or busy(worker_snapshot()):return "G21_V33_R4_OPEN_WORK_CHANGED"
                if task_state().upper()=="RUNNING":task_cmd("Stop-ScheduledTask -InputObject $task")
                # Stop-ScheduledTask can terminate launcher without its Python child.
                # Recheck durable work and only act on the same verified worker.
                if pending()!=(0,0,0) or busy(worker_snapshot()):return "G21_R4_POST_STOP_WORK_HOLD"
                if worker_snapshot():
                    stop_residual(known)
        for _ in range(10):
            if task_state().upper()=="DISABLED" and not worker_snapshot():break
            time.sleep(.3)
        else:
            write(run/"STOP_OBSERVATION.json",{"task":task_state(),"worker_count":len(worker_snapshot()),"oldpid_alive":oldpid is not None and alive(oldpid)})
            return "G21_R4_STOP_UNVERIFIED"
        active,other,runtime=process_inventory(oldpid)
        if pending()!=(0,0,0) or busy([]) or runtime:return "G21_V33_R4_STOP_WORK_HOLD"
        write(run/"OWNER_RECOVERY.json",{"prior":prior,"pid":oldpid,"stage":"QUIESCENT"})
        current=pages()
        if len(current)!=1 or current[0].get("id")!=original["id"] or current[0].get("url")!=original["url"]:
            return "G21_V33_R4_BASE_CHANGED"
        before=current
        cache=run/"isolated-cache";cache.mkdir()
        producer=NativeBrowserProducer(profile=profile,probe=lambda _:None)
        conf=[pathlib.Path.home()/".gemini/antigravity-cli/settings.json",
              pathlib.Path.home()/".gemini/config/config.json",
              pathlib.Path.home()/".gemini/config/mcp_config.json"]
        hashes=[digest(p) for p in conf]
        log=[]
        started=time.monotonic()
        n=poll_private_g2(owner_root=private,cache_root=cache,discover=producer.discover_movies,
                          submit=lambda work:work(),emit=log.append)
        elapsed=round((time.monotonic()-started)*1000)
        receipt=private/"inbox"/("g2-"+nonce+".receipt.json")
        if n!=1 or not receipt.is_file():return "G21_V33_CONSUMER_RECEIPT_MISSING"
        result=json.loads(receipt.read_text("utf-8"))
        if hashes!=[digest(p) for p in conf]:return "G21_V33_GLOBAL_CONFIG_CHANGED"
        try:restored={p["id"]:p["url"] for p in pages()}=={p["id"]:p["url"] for p in before}
        except Exception:restored=False
        repeated=poll_private_g2(owner_root=private,cache_root=cache,discover=producer.discover_movies,
                                 submit=lambda work:work(),emit=log.append)
        write(run/"ACCEPTANCE.json",{"head":head,"receipt":result,"restored":restored,"duplicate_count":repeated,"total_ms":elapsed})
        if result.get("request_id")!=nonce or repeated!=0:return "G21_V33_IDENTITY_HOLD"
        if not restored:return "G21_V33_RESTORE_HOLD"
        batch=cache/".native-v13"/("g2-"+nonce)
        if (cache/".native-v13"/"browser.pending").exists():return "G21_R5_BROWSER_CLAIM_HOLD"
        if result.get("status")!="COMPLETE":
            reason=result.get("reason",result.get("status","UNKNOWN"))
            if not isinstance(reason,str) or not re.fullmatch("[A-Z0-9_]{1,65}",reason):reason="UNCLASSIFIED"
            return "G21_R5_HOLD_"+reason
        rows=result.get("results",[])
        checkpoint=read_doc(batch/"checkpoint.json")
        completed=read_doc(batch/"completed.json")
        bound=read_doc(batch/"request.json")
        if len(rows)!=2 or checkpoint.get("owner_request_id")!=nonce or completed.get("owner_request_id")!=nonce or bound.get("owner_request_id")!=nonce:
            return "G21_R5_CHECKPOINT_BINDING_HOLD"
        if checkpoint.get("results")!=rows or completed.get("results")!=rows or completed.get("clean_exit") is not True or completed.get("status")!="COMPLETE":
            return "G21_R5_CHECKPOINT_CONTENT_HOLD"
        ids=[];conversations=[]
        for i,row in enumerate(rows):
            rid=row.get("turn_request_id","")
            if row.get("owner_request_id")!=nonce or row.get("turn_index")!=i or not re.fullmatch("[a-f0-9]{32}",rid):return "G21_R5_TURN_BINDING_HOLD"
            ids.append(rid)
            if read_doc(batch/rid/"result.json")!=row:return "G21_R5_TURN_RESULT_HOLD"
            trace=batch/rid/"agy-stdout.jsonl"
            if not trace.is_file() or trace.is_symlink() or trace.stat().st_size>16777216:return "G21_R5_TRACE_HOLD"
            finals=[]
            for line in trace.read_text(encoding="utf-8",errors="replace").splitlines():
                try:e=json.loads(line)
                except ValueError:continue
                if isinstance(e,dict) and e.get("event")=="result" and isinstance(e.get("result"),dict):finals.append(e["result"].get("conversation_id"))
            if len(finals)!=1 or not isinstance(finals[0],str) or not finals[0]:return "G21_R5_FINAL_HOLD"
            conversations.append(finals[0])
            t=row.get("timing",{})
            if not 0<t.get("final_ms",0)<=120000 or t.get("mcp_outcomes",0)<1:return "G21_R5_TIMING_HOLD"
        if len(set(ids))!=2 or len(set(conversations))!=1:return "G21_R5_WARM_IDENTITY_HOLD"
        kind="MATCH" if all(row.get("status")=="MATCH_FOUND" and row.get("candidates") for row in rows) else "METADATA_UNVERIFIED"
        return "G21_R5_PASS_"+kind+"_C"+str(rows[0]["timing"]["final_ms"])+"_W"+str(rows[1]["timing"]["final_ms"])
    finally:
        if changed:
            try:
                # Restore original enabled state even on timeout/error/early return.
                # Never create a second Owner after a partial stop.
                if task_state().upper()!="RUNNING" and worker_snapshot():
                    remaining=worker_snapshot()
                    if task_state().upper()!="DISABLED" or pending()!=(0,0,0) or busy(remaining):
                        raise RuntimeError("RESTORE_RESIDUAL_UNVERIFIED")
                    stop_residual(known)
                    if worker_snapshot():raise RuntimeError("RESTORE_RESIDUAL_UNVERIFIED")
                task_cmd("Enable-ScheduledTask -InputObject $task|Out-Null")
                if prior=="RUNNING":
                    if task_state().upper()!="RUNNING":
                        if worker_snapshot():raise RuntimeError("RESTORE_RESIDUAL_UNVERIFIED")
                        task_cmd("Start-ScheduledTask -InputObject $task")
                    ok=False
                    for _ in range(30):
                        try:
                            hh=obj(health,512)
                            if (task_state().upper()=="RUNNING" and hh.get("state")=="READY"
                                and type(hh.get("pid")) is int and alive(hh["pid"])
                                and any(int(w["ProcessId"])==hh["pid"] for w in worker_snapshot())
                                and 0<=time.time()-hh.get("observed_utc_epoch",0)<=10):
                                ok=True;break
                        except Exception:pass
                        time.sleep(1)
                    if not ok:raise RuntimeError("RESTORE_HEALTH_UNVERIFIED")
                elif task_state().upper() not in ("READY","RUNNING"):
                    raise RuntimeError("RESTORE_ENABLE_UNVERIFIED")
                write(run/"OWNER_RECOVERY.json",{"prior":prior,"stage":"RESTORED"})
            except Exception as e:
                write(run/"OWNER_RECOVERY.json",{"prior":prior,"stage":"RESTORE_HOLD","error":str(e)})
                return "G21_V33_R4_OWNER_RESTORE_HOLD"
        else:
            write(run/"OWNER_RECOVERY.json",{"prior":prior,"stage":"UNCHANGED_DISABLED"})

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
