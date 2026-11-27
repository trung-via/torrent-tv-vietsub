Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'NONCE_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('NativeBrowserTest\g2-speed-first-bunny-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$head='47c265fc908171ab18bb0707b2e26b014fb39d40'
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
    def read_doc(p):
        if not p.is_file() or p.is_symlink() or not 0<p.stat().st_size<=1048576:return {}
        return json.loads(p.read_text(encoding="utf-8-sig"))
    # Distinct one-shot legal media trial. Do not repeat earlier provider effects.
    for p in (root/"NativeBrowserTest").glob("g2-speed-first-bunny-*"):
        if p!=run and (p/"isolated-cache").exists():return "G2_SPEED_PRIOR_EFFECT_HOLD"
    # Reuse the exact prior run's verified checkout and checks. No rebuild.
    matches=[]
    for folder in (spool/"History",spool/"Receipts"):
        for p in folder.glob("receipt*.json"):
            d=read_doc(p);n=d.get("nonce","")
            if d.get("source_commit")!="3d741240bf6c055c731412532d88bef0d1a45090" or d.get("result")!="SUCCESS" or not re.fullmatch("[a-f0-9]{32}",str(n)):continue
            st=read_doc(spool/"Receipts"/("odyssey-stage-"+n+".json"))
            if st.get("nonce")==n and st.get("reason")=="G21_V33_R4_IDLE_OPEN_WORK_P1_I0_B0":matches.append(n)
    matches=list(set(matches))
    if len(matches)!=1:return "G2_SPEED_PRIOR_CHECKS_HOLD"
    old=root/"NativeBrowserTest"/("g2-speed-first-bunny-"+matches[0])
    if read_doc(old/"SOURCE_CHECKS.json")!={"targeted_python":2,"powershell_parse":2,"head":head}:return "G2_SPEED_PRIOR_CHECKS_HOLD"
    checkout=old/"candidate"
    if subprocess.check_output(["git","-C",str(checkout),"rev-parse","HEAD"],text=True).strip()!=head:return "G2_SPEED_SOURCE_DRIFT"
    if subprocess.check_output(["git","-C",str(checkout),"status","--porcelain","--untracked-files=no"],text=True).strip():return "G2_SPEED_SOURCE_DIRTY"
    sys.path[:0]=[str(checkout/"poc/p2-sub-discovery"),str(checkout/"poc/p2-aisub")]
    write(run/"SOURCE_CHECKS_REUSED.json",{"head":head,"prior":matches[0]})
    from owner_g2_submit import submit_private_file
    from owner_session_bridge import poll_private_g2, install_owner_full_diagnostics
    from agy_v13_native_producer import NativeBrowserProducer
    # Real writer publication in isolated owner inbox, no live Owner effect.
    private=run/"isolated-owner";private.mkdir()
    install_owner_full_diagnostics(private)
    payload={"schema":"TTV-OWNER-G2-SELECTION-V1","request_id":nonce,
       "authorized_source":True,"source_url":"https://webtorrent.io/free-torrents",
       "queries":[{"title":"Big Buck Bunny","year":2008,"resolution":"1080p",
                   "select_release":True,"media_authorized":True,"play":False,
                   "verified_release_hash":"dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c"}]}
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
    # Human stopped Owner. Pending unexecuted G1 events remain untouched.
    # Never overlap a live worker or unresolved provider/browser effect.
    prior=task_state().upper()
    if prior!="DISABLED":return "G2_SPEED_OWNER_NOT_STOPPED"
    task_cmd("'VERIFIED'")
    p,i,b=pending()
    if i or b:return "G2_SPEED_OPEN_EFFECT_I"+str(i)+"_B"+str(b)
    for event in inbox.glob("event-*.json"):
        if (inbox/("claim-"+event.stem.removeprefix("event-"))).exists():return "G2_SPEED_UNRESOLVED_EVENT_CLAIM"
    active,other,runtime=process_inventory()
    if worker_snapshot() or active or runtime or busy([]):return "G2_SPEED_WORKER_ACTIVE"
    write(run/"OWNER_RECOVERY.json",{"prior":prior,"stage":"UNCHANGED_DISABLED","preserved_events":p})
    profile=root/"NativeBrowserTest"/"CDP9555Profile"
    from agy_v13_native_producer import _ensure_browser_listener
    try:
        _ensure_browser_listener(shutil.which("pwsh"),profile)
    except Exception:
        return "G21_V33_R4_BROWSER_HOLD"
    try:
        if task_state().upper()!="DISABLED" or worker_snapshot() or pending()[1:]!=(0,0) or busy([]):
            return "G2_SPEED_QUIESCENCE_CHANGED"
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
        # Discovery-only training: no library handoff, no add and no TV.
        expected="dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c"
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
        write(run/"ACCEPTANCE.json",{"head":head,"receipt":result,"restored":restored,
              "total_ms":elapsed,"training_only":True})
        if result.get("request_id")!=nonce:return "G2_SPEED_IDENTITY_HOLD"
        if not restored:return "G2_SPEED_BROWSER_RESTORE_HOLD"
        batch=cache/".native-v13"/("g2-"+nonce)
        if (cache/".native-v13"/"browser.pending").exists():return "G2_SPEED_BROWSER_CLAIM_HOLD"
        if result.get("status")!="COMPLETE":
            reason=result.get("reason",result.get("status","UNKNOWN"))
            if not isinstance(reason,str) or not re.fullmatch("[A-Z0-9_]{1,65}",reason):reason="UNCLASSIFIED"
            return "G2_SPEED_HOLD_"+reason
        rows=result.get("results",[])
        if len(rows)!=1 or rows[0].get("owner_request_id")!=nonce:return "G2_SPEED_ROW_BINDING_HOLD"
        row=rows[0];timing=row.get("timing",{});ms=timing.get("final_ms",0)
        if type(ms) is not int or ms<=0:return "G2_SPEED_TIMING_HOLD"
        if row.get("status")!="SELECTION_READY":
            reason=row.get("status","UNKNOWN")
            if not isinstance(reason,str) or not re.fullmatch("[A-Z0-9_]{1,50}",reason):reason="UNKNOWN"
            return "G2_SPEED_"+reason+"_MS"+str(ms)
        if result.get("selection_published") is not True:return "G2_SPEED_PUBLISH_HOLD"
        selection=read_doc(private/"inbox"/("g2-"+nonce+".selected.json"))
        if (selection.get("request_id")!=nonce or selection.get("play") is not False
                or selection.get("selection",{}).get("expected_hash")!=expected
                or (private/"inbox"/("g2-"+nonce+".library.json")).exists()):
            return "G2_SPEED_SELECTION_BINDING_HOLD"
        return "G2_SPEED_SELECTION_PASS_AGY"+str(ms)+"_TOTAL"+str(elapsed)
    finally:
        write(run/"OWNER_RECOVERY.json",{"prior":prior,"stage":"UNCHANGED_DISABLED" if task_state().upper()=="DISABLED" else "EXTERNAL_STATE_CHANGED","preserved_events":p})

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
