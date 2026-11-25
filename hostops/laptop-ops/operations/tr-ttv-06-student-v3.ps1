# BT05: automatic terminal report export, exact BT04 replay option.
param([switch]$ReplayBT04)
# Never edit shared settings or touch Owner production.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$env:TTV_PINNED_SOURCE=[string]$rq.source_commit
$env:TTV_READOUT_NONCE=[string]$rq.nonce
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('bt18-'+$(if($ReplayBT04){'replay'}else{'hydrogen-opensubtitles'})+'-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$reportWriter=@'
import json,pathlib,sys,os,re,hashlib
root,dest,spool=map(pathlib.Path,sys.argv[1:4])
nonce,source,mode,result_code=sys.argv[4:8]
assert re.fullmatch("[a-f0-9]{32}",nonce) and re.fullmatch("[a-f0-9]{40}",source)
assert mode in ("LIVE","REPLAY")
assert re.fullmatch("[A-Z0-9_]{3,90}",result_code)
prior=nonce
data=dest
original=source
def read(p,cap=67108864):
    if not p.is_file() or p.is_symlink() or p.stat().st_size>cap:return ""
    return p.read_text(encoding="utf-8-sig",errors="replace")
def obj(p):
    try:
        x=json.loads(read(p))
        return x if isinstance(x,dict) else {}
    except ValueError:return {}
def save(p,x):
    tmp=p.with_name(p.name+".tmp")
    with tmp.open("w",encoding="utf-8",newline="\n") as f:
        json.dump(x,f,ensure_ascii=True,indent=2)
        f.write("\n");f.flush();os.fsync(f.fileno())
    os.replace(tmp,p)
if mode=="REPLAY":
    original="4cd3124ac8c7102028ff0b1f079a5b3b522b15c9"
    matches=[]
    for f in (spool/"History").glob("receipt-*.json"):
        q=obj(f)
        if q.get("source_commit")==original and q.get("result")=="SUCCESS" and re.fullmatch("[a-f0-9]{32}",str(q.get("nonce",""))):matches.append(q)
    assert len(matches)==1,"REPLAY_RECEIPT_NOT_UNIQUE"
    prior=matches[0]["nonce"]
    data=root/("bt04-neon-subtitlecat-"+prior)
    assert data.is_dir() and not data.is_symlink()
report=obj(data/"BRAIN_TEACHER_REPORT.json")
recipe=obj(data/"TEACHER_RECIPE_PRIVATE.json")
if report and report.get("source_commit")!=original:raise ValueError("REPORT_SOURCE_DRIFT")
timing=obj(data/"stream-timing.json")
raw=read(data/"agy-stdout.jsonl")
records=[];invalid=0
for line in raw.splitlines():
    try:
        e=json.loads(line)
        if isinstance(e,dict):records.append(e)
        else:invalid+=1
    except ValueError:invalid+=1
times=timing.get("event_arrival_seconds",[])
if not times:
    times=[]
    for line in read(data/"event-arrivals.jsonl").splitlines():
        try:times.append(json.loads(line))
        except ValueError:break
timed=isinstance(times,list) and len(times)==len(records) and all(type(t) in (float,int) and 0<=t<1000000 for t in times)
known={"list_pages","select_page","navigate_page","take_snapshot","click","fill","press_key","wait_for","evaluate_script","read_file","write_file","run_shell_command","execute_command","list_network_requests","call_mcp_tool"}
trace=[];answers=[];first=-1;last=-1;outcomes=0
for i,e in enumerate(records):
    st=e.get("step_update") if isinstance(e.get("step_update"),dict) else {}
    info=st.get("tool_info") if isinstance(st.get("tool_info"),dict) else {}
    params=info.get("parameters") if isinstance(info.get("parameters"),dict) else {}
    n=params.get("ToolName") if st.get("tool_name")=="call_mcp_tool" else st.get("tool_name")
    n=n.upper() if isinstance(n,str) and n in known else "OTHER"
    result=e.get("result")
    if e.get("event")=="result" and isinstance(result,dict) and isinstance(result.get("response"),str):answers.append(result["response"])
    if n=="OTHER":continue
    t=round(times[i]*1000) if timed else -1
    k="ERROR" if any(x not in (None,"",False,[],{}) for x in (info.get("error"),st.get("error"),e.get("error"))) else "OUTPUT" if "output" in info else "CALL"
    trace.append(f"{i}:{t}:{n}:{k}")
    if st.get("tool_name")=="call_mcp_tool":
        if first<0:first=t
        if k in ("ERROR","OUTPUT"):outcomes+=1;last=t
def valid(x):
    return isinstance(x,dict) and isinstance(x.get("actions"),list) and isinstance(x.get("reusable_recipe"),list)
if not valid(recipe):
    recipe={}
    for a in reversed(answers):
        for m in re.finditer(r"\{",a):
            try:q,_=json.JSONDecoder().raw_decode(a[m.start():])
            except ValueError:continue
            if valid(q):recipe=q;break
        if recipe:break
error=read(data/"probe-error.txt",65536)
errkind="NONE"
if error:
    m=re.match(r"([A-Za-z]+Error):",error)
    errkind=m.group(1).upper() if m and m.group(1).upper() in {"KEYERROR","VALUEERROR","TYPEERROR","NAMEERROR","ATTRIBUTEERROR","OSERROR","PERMISSIONERROR","FILENOTFOUNDERROR","RUNTIMEERROR","TIMEOUTERROR","UNICODEERROR","JSONDECODEERROR"} else "OTHER_ERROR"
def integer(v,default=-1):
    return v if type(v) is int and -1<=v<=2147483647 else default
artifacts=report.get("artifacts",[])
artifacts=artifacts if isinstance(artifacts,list) else []
verified=[a for a in artifacts if isinstance(a,dict) and a.get("copied_to_job") is True and integer(a.get("cues"),0)>0 and re.fullmatch("[a-f0-9]{64}",str(a.get("sha256","")))]
elapsed=integer(report.get("elapsed_seconds"))
download=integer(timing.get("download_mtime_elapsed"))
is_report=bool(valid(recipe))
state="MODEL_REPORT_PRESENT" if is_report else "MODEL_REPORT_MISSING"
status=recipe.get("status") if is_report else None
status="CANDIDATE_DOWNLOADED" if status in ("DOWNLOAD_INITIATED","CANDIDATE_DOWNLOADED") and len(verified)==1 and report.get("filter_gate",{}).get("download_verified") is True else "DOWNLOAD_FAILED" if status in ("DOWNLOAD_INITIATED","CANDIDATE_DOWNLOADED") else status
status=status if status in ("CANDIDATE_DOWNLOADED","NO_PLAUSIBLE_CANDIDATE","ACCESS_BLOCKED","AUTH_REQUIRED","DOWNLOAD_FAILED","TOOL_UNAVAILABLE","UNKNOWN") else "NOT_REPORTED"
release_label=recipe.get("release_match") if is_report else None
release_label=release_label if release_label in ("EXACT_METADATA","EVIDENCED_COMPATIBLE","UNKNOWN","CONFLICT") else "NOT_REPORTED"
allowed_codes={"LIST_TASK_TAB","NAVIGATE_PROVIDER","QUERY_TITLE_YEAR","FILTER_ENGLISH","MATCH_RELEASE","CHECK_DETAIL","BIND_CANDIDATE","DOWNLOAD_ONCE","COMPACT_DOM","AVOID_REPEAT_SNAPSHOT","STOP_ON_DENIAL","MARK_UNKNOWN_METADATA","CHECK_TIMELINE","HOST_VERIFY_FILE","FINAL_REPORT"}
codes=recipe.get("recipe_codes",[]) if is_report else []
codes=[x for x in codes if isinstance(x,str) and x in allowed_codes][:64] if isinstance(codes,list) else []
public={"schema":"TTV-BRAIN-HANDOFF-V1","nonce":nonce,"source":source,"original_source":original,"mode":mode,"state":state,"model_status":status,"model_release":release_label,"recipe_codes":codes,"error_kind":errkind,"result_code":result_code,"events":len(records),"invalid":invalid,"timed":int(timed),"elapsed":elapsed,"download":download,"first_mcp_ms":first,"last_mcp_ms":last,"mcp_outcomes":outcomes,"final_chars":sum(map(len,answers)),"actions":len(recipe.get("actions",[])),"recipe_steps":len(recipe.get("reusable_recipe",[])),"artifacts":len(verified),"cues":max((a["cues"] for a in verified),default=0),"title_language":int(report.get("title_language_evidence") is True),"exact":int(report.get("exact_release_line_evidence") is True),"sync":int(report.get("playback_sync_verified") is True),"denied":int(report.get("permission_denied") is True),"trace":trace}
# Model's explicit final report is untrusted evidence, not executable instructions.
# No private reasoning or raw stream is included in the handoff.
private={"schema":"TTV-BRAIN-RESULT-V1","handoff":public,"model_report":recipe if is_report else None,"host_evidence":{k:report.get(k) for k in ("model","provider","provider_access","selection_evaluation","filter_gate","artifacts","title_language_evidence","exact_release_line_evidence","release_match_verified","playback_sync_verified","exit")},"report_files_present":{k:(data/k).is_file() for k in ("agy-stdout.jsonl","stream-timing.json","event-arrivals.jsonl","BRAIN_TEACHER_REPORT.json","TEACHER_RECIPE_PRIVATE.json","probe-error.txt")}}
save(dest/"BRAIN_RESULT.json",private)
save(dest/"BRAIN_HANDOFF.json",public)
save(spool/"Receipts"/("brain-handoff-"+nonce+".json"),public)
# Verify the persisted consumer payload before returning.
assert obj(dest/"BRAIN_RESULT.json").get("handoff")==public and obj(dest/"BRAIN_HANDOFF.json")==public
assert obj(spool/"Receipts"/("brain-handoff-"+nonce+".json"))==public
'@
$writerFile=Join-Path $run 'brain-report-export.py'
[IO.File]::WriteAllText($writerFile,$reportWriter,[Text.UTF8Encoding]::new($false))
function Export-BrainReport([string]$mode,[string]$result){
  & py -3 -I -B $writerFile $root $run $spool $rq.nonce $rq.source_commit $mode $result
  if($LASTEXITCODE -ne 0){throw 'BRAIN_REPORT_EXPORT_FAILED'}
}
if($ReplayBT04){
  Export-BrainReport 'REPLAY' 'BT04_RECOVERED'
  $doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason='BT05_REPLAY_REPORT_EXPORTED'}
  [IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
  Write-Output 'BT05_REPLAY_REPORT_EXPORTED'
  return
}
$code='BT05_PRECHECK_ERROR'
try{
function Listener([int]$port){
  @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique)
}
$before9444=@(Listener 9444)
$before9555=@(Listener 9555)
$task=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'
$ownerState=[string]$task.State
$hostTask=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-Laptop-HostOps' -TaskPath '\'
$profile=Join-Path $root 'CDP9555Profile'
$active9555=@(Listener 9555)
$started9555=0
$verified=$false
$code='BT04_BROWSER_NOT_VERIFIED'
if([string]$hostTask.Settings.ExecutionTimeLimit -ne 'PT0S'){$code='TR04C_TASK_LIMIT'}
else{
 # Recover only the enrolled dedicated profile when its browser is actually absent.
 # Never kill another process, replace the profile, or rotate endpoints.
 if($active9555.Count -eq 0){
  $roots=@(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object {$_.CommandLine -and $_.CommandLine -notmatch '--type=' -and $_.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0})
  $chrome=Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'
  if($roots.Count -ne 0){$code='BT04_PROFILE_RUNNING_NO_LISTENER'}
  elseif(-not (Test-Path -LiteralPath $profile -PathType Container) -or -not (Test-Path -LiteralPath $chrome -PathType Leaf)){$code='BT04_PROFILE_OR_CHROME_MISSING'}
  else{
   Start-Process -FilePath $chrome -ArgumentList @('--user-data-dir="'+$profile+'"','--remote-debugging-port=9555','--remote-debugging-address=127.0.0.1','--no-first-run','--no-default-browser-check','--new-window','https://www.opensubtitles.org/')
   $started9555=1
   for($i=0;$i -lt 30;$i++){
    Start-Sleep -Milliseconds 500
    $active9555=@(Listener 9555)
    if($active9555.Count -eq 1){break}
   }
   $code='BT04_RESTORE_NO_LISTENER'
  }
 }
 if($active9555.Count -gt 1){$code='BT04_LISTENER_AMBIGUOUS'}
 elseif($active9555.Count -eq 1){
  $p=Get-CimInstance Win32_Process -Filter ("ProcessId="+$active9555[0])
  $ls=@(Get-NetTCPConnection -LocalPort 9555 -State Listen -ErrorAction SilentlyContinue)
  if($p -and $p.Name -eq 'chrome.exe' -and $p.CommandLine -and $p.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0 -and $p.CommandLine -match '(?:^|\s|")--remote-debugging-port=9555(?:\s|"|\z)' -and @($ls|Where-Object {$_.LocalAddress -notin @('127.0.0.1','::1')}).Count -eq 0){
   $verified=$true
  }else{$code='BT04_LISTENER_IDENTITY_MISMATCH'}
 }
}
if($verified){
$py=@'
import sys,pathlib,os,json,re,subprocess,hashlib,shutil,urllib.request,urllib.parse,time,zipfile,sqlite3
owner,run,profile=map(pathlib.Path,sys.argv[1:])
sys.path.insert(0,str(owner/"app/poc/p2-aisub"))
from translator_gateway import preflight_antigravity,_validated_antigravity_alias
def read(p):
    if not p.is_file(): return {}
    if p.is_symlink() or p.stat().st_size>4194304: raise ValueError("CONFIG_UNSAFE")
    x=json.loads(p.read_text(encoding="utf-8-sig"))
    if not isinstance(x,dict): raise ValueError("CONFIG_NOT_OBJECT")
    return x
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else "MISSING"
def write(p,x):p.write_text(json.dumps(x,ensure_ascii=True,indent=2)+"\n",encoding="utf-8")
def probe():
    cli=preflight_antigravity()
    ps=shutil.which("pwsh")
    if not ps:return "TR04A_NO_PWSH"
    env=dict(os.environ)
    for k in ("GEMINI_API_KEY","GOOGLE_API_KEY","GOOGLE_GEMINI_BASE_URL","AGY_ADC_AUTH","GOOGLE_CLOUD_PROJECT","GOOGLE_CLOUD_QUOTA_PROJECT"):env.pop(k,None)
    env["TTV_AGY_CLI"]=str(cli)
    env["TTV_SOURCE_SHA"]=os.environ.get("TTV_PINNED_SOURCE","")
    helpcmd="& $env:TTV_AGY_CLI --help; exit $LASTEXITCODE"
    q=subprocess.run([ps,"-NoProfile","-NonInteractive","-Command",helpcmd],env=env,cwd=run,capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=20)
    helptext=q.stdout+"\n"+q.stderr
    (run/"cli-help.txt").write_text(helptext,encoding="utf-8")
    home=pathlib.Path.home()
    settings=home/".gemini"/"antigravity-cli"/"settings.json"
    shared=home/".gemini"/"config"/"config.json"
    global_mcp=home/".gemini"/"config"/"mcp_config.json"
    paths=[settings,shared,global_mcp]
    config_before=[sha(p) for p in paths]
    config=read(settings); sharedconfig=read(shared); servers=read(global_mcp).get("mcpServers",{})
    if not isinstance(servers,dict):return "TR04A_MCP_SCHEMA_UNKNOWN"
    if "ttv-browser" in servers:return "TR04A_GLOBAL_TTV_CONFLICT"
    # Identify exact relative rule, with structural locations only, no exported values.
    hits=[]
    def scan(v,trail,idx):
        if isinstance(v,dict):
            for k,x in v.items():scan(x,trail+[k],idx)
        elif isinstance(v,list):
            for i,x in enumerate(v):scan(x,trail+[i],idx)
        elif isinstance(v,str) and re.search(r"(?<![A-Za-z0-9_./\\])\.git[/\\]aios[/\\]?(?=[)\s]*$)",v):hits.append((idx,trail,v))
    scan(config,[],0);scan(sharedconfig,[],1)
    session_flag=bool(re.search(r"(?m)^\s*--?settings(?:[ =\t]|$)",helptext))
    # Retain actual documented CLI flag evidence in the private run directory.
    write(run/"config-audit.json",{"relative_rule_locations":[{"source":i,"path":[str(v) for v in t]} for i,t,_ in hits],"session_settings_flag":session_flag,"global_mcp_count":len(servers),"global_ttv_conflict":False})
    agents=run/".agents";agents.mkdir()
    write(agents/"mcp_config.json",{"mcpServers":{"ttv-browser":{"command":"cmd.exe","args":["/d","/c","npx","-y","chrome-devtools-mcp@1.14.0","--browser-url=http://127.0.0.1:9555","--no-usage-statistics"]}}})
    # Confirm loopback Chrome without reading tabs or visiting a website.
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open("http://127.0.0.1:9555/json/version",timeout=3) as f:version=json.load(f)
    if not str(version.get("Browser","")).startswith("Chrome/") or not str(version.get("webSocketDebuggerUrl","")).startswith("ws://127.0.0.1:9555/"):return "TR04A_ENDPOINT_UNVERIFIED"
    if not session_flag:
        return "TR04A_NO_SESSION_FLAG_R%dS%d"%(sum(i==0 for i,_,_ in hits),sum(i==1 for i,_,_ in hits))
    if any(i!=0 for i,_,_ in hits):return "TR04A_SHARED_RULE_NEEDS_SCOPE"
    if not hits:return "TR04A_RULE_NOT_LOCATED"
    # Only transform an exact file rule. Keep its original allow/deny/ask intent.
    for idx,t,val in hits:
        if not re.fullmatch(r"(?:read_file|write_file)\(\.git[/\\]aios[/\\]?\)",val):
            return "TR04A_RULE_FORM_UNKNOWN"
        if len(t)!=3 or t[0]!="permissions" or t[1] not in ("allow","deny","ask") or not isinstance(t[2],int):return "TR04A_RULE_SCOPE_UNKNOWN"
        config[t[0]][t[1]][t[2]]=val[:val.index("(")+1]+(run/".git"/"aios").as_posix()+")"
    perms=config.setdefault("permissions",{})
    if not isinstance(perms,dict):return "TR04A_PERM_SCHEMA_UNKNOWN"
    for key in ("allow","deny","ask"):
        if not isinstance(perms.get(key,[]),list):return "TR04A_PERM_SCHEMA_UNKNOWN"
    # Respect any existing explicit deny or ask; no global wildcard grant.
    for key in ("deny","ask"):
        for rule in perms.get(key,[]):
            if isinstance(rule,str) and (rule.startswith("mcp(ttv-browser") or rule=="mcp(*)"):return "TR04A_EXISTING_RESTRICTION"
    # Explicit tool grants limited to this benchmark and native 9555 server.
    tools=("list_pages","select_page","navigate_page","take_snapshot","click","fill","press_key","wait_for","evaluate_script")
    for k in ("deny","ask"):
        if any(isinstance(v,str) and (v.startswith("mcp(ttv-browser") or v=="mcp(*)") for v in perms.get(k,[])):return "TR04B_EXISTING_RESTRICTION"
    allowed=perms.setdefault("allow",[])
    for tool in tools:
        rule="mcp(ttv-browser/"+tool+")"
        if rule not in allowed:allowed.append(rule)
    if config.get("agentMode")=="auto":config.pop("agentMode")
    override=run/"session-settings.json"
    write(override,config)
    env["TTV_SESSION_SETTINGS"]=str(override)
    env["TTV_AGY_MODEL"]=_validated_antigravity_alias("gemini-4-hydrogen-low","low")
    # One ordinary pre-existing provider tab only. Do not reload, rotate or solve a challenge.
    with opener.open("http://127.0.0.1:9555/json/list",timeout=3) as f:tabs=json.load(f)
    pages=[t for t in tabs if t.get("type")=="page"]
    cat_hosts={"www.subtitlecat.com","subtitlecat.com"}
    os_hosts={"www.opensubtitles.org","opensubtitles.org"}
    host=lambda t:urllib.parse.urlsplit(t.get("url","")).hostname
    site=[t for t in pages if host(t) in os_hosts]
    if not site:site=[t for t in pages if host(t) in cat_hosts]
    if not site:
        # Ordinary homepage on the same verified profile, only if no provider tab exists.
        req=urllib.request.Request("http://127.0.0.1:9555/json/new?https://www.opensubtitles.org/",method="PUT")
        with opener.open(req,timeout=5) as f:new=json.load(f)
        for _ in range(20):
            time.sleep(.5)
            with opener.open("http://127.0.0.1:9555/json/list",timeout=3) as f:tabs=json.load(f)
            site=[t for t in tabs if t.get("type")=="page" and t.get("id")==new.get("id") and host(t) in os_hosts]
            if site:break

    if any(re.search(r"/\.within\.website/|making sure you.re not a bot|captcha|access denied|just a moment|forbidden",t.get("url","")+" "+t.get("title",""),re.I) for t in site):return "BT04_ACCESS_BLOCKED_PRE"
    if len(site)!=1:return "BT04_TASK_TAB_AMBIGUOUS"
    target=site[0]
    u=urllib.parse.urlsplit(target.get("url",""))
    if u.scheme!="https":return "BT04_TASK_TAB_UNVERIFIED"
    initial_host=u.hostname
    # Keep original browser download preferences unchanged; snapshot known download directory.
    prefs=read(profile/"Default"/"Preferences")
    download=prefs.get("download",{})
    dest=pathlib.Path(os.path.expandvars(download.get("default_directory") or str(home/"Downloads")))
    if not dest.is_absolute() or not dest.is_dir():return "BT04_DOWNLOAD_DIR_UNVERIFIED"
    dirs={dest}
    resultdir=run/"browser-downloads";resultdir.mkdir()
    write(run/"task-binding.json",{"cdp_target_id":target.get("id"),"initial_url":target.get("url"),"download_directory":str(dest),"existing_profile":True,"cold_profile":False})
    def candidates():
        found={}
        for d in dirs:
            try:
                for f in d.iterdir():
                    if f.is_file() and not f.is_symlink() and f.suffix.lower() in (".srt",".zip"):
                        found[str(f.resolve())]=(f.stat().st_size,f.stat().st_mtime_ns)
            except OSError:pass
        return found
    def cue_count(f):
        try:
            if f.suffix.lower()==".srt":blobs=[f.read_bytes()]
            else:
                with zipfile.ZipFile(f) as z:
                    blobs=[z.read(i) for i in z.infolist()[:100] if i.filename.lower().endswith(".srt") and 0<i.file_size<=2000000 and not i.flag_bits&1]
            return max((len(re.findall(rb"(?m)^\d{2}:\d{2}:\d{2}[,.]\d{3}\s+-->\s+\d{2}:\d{2}:\d{2}[,.]\d{3}",data)) for data in blobs),default=0)
        except (OSError,ValueError,RuntimeError,zipfile.BadZipFile):return 0
    downloads=run/"downloads";downloads.mkdir()
    before=candidates()
    # Resolve only the owner-selected release by normalized fingerprint against live TorrServer.
    sys.path.insert(0,str(owner/"app/poc/p2-sub-discovery"))
    from owner_torrserver_readonly import OwnerLocalTorrServer,OwnerTorrServerReader,_local_post
    policy=read(owner/"p3-p4-policy.json")
    cfg=OwnerLocalTorrServer(policy["profile_id"],policy["torrserver_port"])
    listing=json.loads(_local_post(cfg.url,b'{"action":"list"}',6.0))
    if not isinstance(listing,list) or len(listing)>256:return "BT04_FIXTURE_LIST_INVALID"
    def norm(x):return re.sub(r"[^a-z0-9]","",str(x).casefold())
    target="0c57a7ebb1d8c09b29b6642d48af57701ca4479e6d6d9f63fa8ae3c26a615b5e"
    def match(x):return hashlib.sha256(norm(x).encode()).hexdigest()==target
    found={}
    for t in listing:
        if not isinstance(t,dict):continue
        tor=t.get("hash")
        if not isinstance(tor,str) or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}",tor):continue
        files=t.get("file_stats")
        if not files:
            try:files=json.loads(t.get("data","{}"))["TorrServer"]["Files"]
            except (TypeError,ValueError,KeyError):continue
        if not isinstance(files,list) or len(files)>4096:continue
        for x in files:
            if not isinstance(x,dict):continue
            name=str(x.get("path","")).replace("\\","/").rsplit("/",1)[-1]
            idx=x.get("id")
            if type(idx) is not int or not 0<=idx<4096 or not re.search(r"\.(mkv|mp4|avi|m4v|ts|m2ts)$",name,re.I):continue
            if not (match(pathlib.PurePosixPath(name).stem) or match(t.get("title",""))):continue
            if type(x.get("length")) is int and x["length"]>100000000:found[(tor,idx)]=(name,str(t.get("title","")))
    if len(found)!=1:return f"BT04_FIXTURE_MATCHES{len(found)}"
    (tor,idx),(name,listed_title)=next(iter(found.items()))
    actual=OwnerTorrServerReader(cfg)(cfg.profile_id,tor,idx)
    if actual.path.replace("\\","/").rsplit("/",1)[-1]!=name:return "BT04_FIXTURE_DRIFT"
    release=pathlib.PurePosixPath(name).stem if match(pathlib.PurePosixPath(name).stem) else listed_title
    m=re.search(r"(?<!\d)(19\d{2}|20\d{2})(?!\d)",release)
    if not m:return "BT04_FIXTURE_YEAR_UNKNOWN"
    title=re.sub(r"[._() -]+"," ",release[:m.start()]).strip()
    if not title:return "BT04_FIXTURE_TITLE_UNKNOWN"
    preflight_source="17b7acb8d5ffbf0dfeb74961bf75d57c9d5cc716"
    spool=pathlib.Path(os.environ["ProgramData"])/"TorrentTVVietsub"/"LaptopHostOps"
    preflight=[]
    for f in (spool/"History").glob("receipt-*.json"):
        r=read(f)
        if r.get("source_commit")==preflight_source and r.get("result")=="SUCCESS" and re.fullmatch("[a-f0-9]{32}",str(r.get("nonce",""))):
            preflight.append(r["nonce"])
    if len(preflight)!=1:return "BT18_HOLD_PREFLIGHT_RECEIPT"
    fixture=read(run.parent/("bt10-human-fixture-preflight-"+preflight[0])/"BRAIN_HUMAN_FIXTURE.json")
    if not (fixture.get("schema")=="BT10_HUMAN_FIXTURE_V1" and fixture.get("selection_fingerprint")==target and fixture.get("exact_file_verified") is True and fixture.get("hash")==tor and fixture.get("file_index")==idx and fixture.get("filename")==name and fixture.get("size_bytes")==actual.length and fixture.get("english_track_count",0)>=1 and 600<fixture.get("duration_seconds",0)<14400 and 0<fixture.get("fps",0)<240):
        return "BT18_HOLD_FIXTURE_DRIFT"
    video_input={"title":title,"year":int(m.group()),"release":release,"release_origin":"TORRSERVER_VERIFIED","size_bytes":actual.length,"fps":fixture["fps"],"duration":fixture["duration_seconds"],"duration_unit":"seconds","audio_language":"English (track metadata verified)"}
    write(run/"verified-fixture.json",video_input)
    prompt="You are Hydrogen Low, Student Recipe V12.1, independently finding the English subtitle for the exact TorrServer release given below on OpenSubtitles.org via authorized ttv-browser MCP Chrome CDP 9555. No Teacher candidate IDs, answers or download links are provided. Use only list_pages, select_page, navigate_page, take_snapshot, click, fill, press_key, wait_for, evaluate_script; page-scoped calls must pass numeric pageId. Reuse only the authorized task tab, navigate to ordinary https://www.opensubtitles.org/ if needed. Use bounded visible DOM queries from the start; never dump whole DOM or subtitle text. Confirm current visible controls; observed selector hints only: #search_text, #search_submit, #bt-dwl-bt. Use visible search form title+year, select English if available; do not use arbitrary guessed search URLs. One compact read should identify search controls and current filters. Prefer compact evaluate_script reads and scoped ordinary DOM interaction with visible form controls; do not mix snapshot UIDs and CSS selectors. No read_file calls for snapshots; return small visible data directly. Avoid repeated reads. Use numeric pageId. HARD GATE: After search, verify the actual result page URL and visible heading show English-only results; selecting a language before submit does not prove it was applied. If results are mixed, follow the actual visible English filter link. Before ranking, read all relevant English candidate rows across pagination, return compact JSON {url,heading,total_english,count_scope,count_label,has_next,rows:[{href,lang,title,release,fps}]} on each filtered page. total_english is only the count explicitly scoped to the filtered movie results, not the site-wide subtitle counter; include count_scope=filtered_results and count_label from that visible results container if reliably observed, otherwise total_english=null and count_scope=unknown, has_next is actual visible next-page availability; lang is the actual row language or confirmed English-only list context. Do not truncate or guess counts. Only eligible English title/year rows may enter ranking. Treat row language flags flag en / en / eng / English as English only when consistent with the English-only filtered page. Rank evidence of the same cut and timeline ahead of encoder, resolution, bit depth, audio codec and release-name similarity. If the leading distinct release has unknown runtime or cut, inspect the strongest alternative distinct release group before committing; do not inspect redundant SDH variants unless useful. Prefer measured duration and FPS matches over encoding resemblance, and state unknowns. Do not select by a remembered candidate ID. If coverage cannot be established, report uncertainty rather than claim complete scan. Open strongest detail and return compact JSON with url, candidate_id, English title/language evidence, btnVisible, fieldsetText, downloadHref (the actual href of visible ordinary #bt-dwl-bt), and downloaderChecked (boolean if the visible optional downloader checkbox exists, null if absent); read candidate-specific detail box (hint: visible download button's closest fieldset) for title/year/language, release notes including alternative supported releases, FPS, runtime, file type, visible download button and material comments in one query if practical. Check FPS/runtime against measured target metadata; unknown remains unknown. A WEB-DL and WEBRip may share a cut but the label alone proves nothing. Distinguish 24 from 23.976 fps and consider progressive drift. Compare materially different runtimes and cut notes. Avoid repeatedly re-reading already confirmed pages; inspect more candidates only when new evidence could change the choice. Distinguish exact filename/release from explicit compatible release note. Prefer completeness and timeline evidence over download count, file size or cue count alone; non-HI is a tiebreaker. Inspect next candidate only for material ambiguity or quality issue. Bind selected detail ID to the visible ordinary Download control #bt-dwl-bt, not Download (beta), preview, or downloader. If the optional installer/downloader checkbox is checked, use ordinary UI to uncheck it; do not modify site handlers or bypass restrictions. Recheck the selected ID, visible control, href and unchecked/absent downloader in the same final scoped evaluate_script action; if they match, activate that ordinary control once and return JSON {clicked:true,pageUrl,href,id,downloaderChecked}. If mismatched, do not click and report the reason. Stop browser actions after the click. A click does not establish a downloaded file. Do not guess URLs or endpoints, bypass restrictions, login, pay, or use alternate providers. Stop on denial or access block. Host independently verifies filtered-list coverage separately from fresh artifact and candidate-bound ordinary download, records actual tool events and exports BRAIN_RESULT.json and BRAIN_HANDOFF.json. Return DOWNLOAD_INITIATED after successful ordinary download action; only Host verifies file. Do not claim download success on a tool error. No file/shell calls to write reports. Aim for <=8 MCP outcomes and <=75s acquisition as targets only; never sacrifice correct match to speed. Return compact final JSON even on failure: status (DOWNLOAD_INITIATED, NO_PLAUSIBLE_CANDIDATE, ACCESS_BLOCKED, AUTH_REQUIRED, DOWNLOAD_FAILED, TOOL_UNAVAILABLE, UNKNOWN), observed_evidence, release_match (EXACT_METADATA, EVIDENCED_COMPATIBLE, UNKNOWN, CONFLICT), compatibility_uncertainties, actions (actual actions with ordinal, tool, purpose, result, error, decision), reusable_recipe (ordered brief steps without candidate IDs, local paths or subtitle text), recipe_codes (ordered array only from LIST_TASK_TAB, NAVIGATE_PROVIDER, QUERY_TITLE_YEAR, FILTER_ENGLISH, MATCH_RELEASE, CHECK_DETAIL, BIND_CANDIDATE, DOWNLOAD_ONCE, COMPACT_DOM, AVOID_REPEAT_SNAPSHOT, STOP_ON_DENIAL, MARK_UNKNOWN_METADATA, CHECK_TIMELINE, HOST_VERIFY_FILE, FINAL_REPORT), failures, improvements, usage if exposed. Report observations and evidence from this run only. Keep final JSON compact (roughly 1500-2500 characters if feasible); preserve decision and uncertainty. Concise operational decisions only; no hidden reasoning. No translation, TV or production effects. Input metadata: "+json.dumps(video_input,ensure_ascii=True)
    (run/"teacher-prompt.txt").write_text(prompt,encoding="utf-8")
    env["TTV_AGY_PROMPT"]=str(run/"teacher-prompt.txt")
    cmd="$ErrorActionPreference='Stop'; $p=Get-Content -LiteralPath $env:TTV_AGY_PROMPT -Raw; & $env:TTV_AGY_CLI --model $env:TTV_AGY_MODEL --sandbox --settings $env:TTV_SESSION_SETTINGS --output-format stream-json -p $p; exit $LASTEXITCODE"
    start=time.monotonic()
    wall_start=time.time()
    arrivals=[]
    # Record only host-side arrival times. These include child buffering and are
    # not internal model clocks. Keep stderr separate to avoid a pipe deadlock.
    try:
        with (run/"agy-stdout.jsonl").open("w",encoding="utf-8",newline="") as out, (run/"agy-stderr.txt").open("wb") as err, (run/"event-arrivals.jsonl").open("w",encoding="utf-8",newline="") as journal:
            with subprocess.Popen([ps,"-NoProfile","-NonInteractive","-Command",cmd],env=env,cwd=run,stdout=subprocess.PIPE,stderr=err,text=True,encoding="utf-8",errors="replace",bufsize=1) as p:
                for line in p.stdout:
                    arrival=time.monotonic()-start
                    out.write(line);out.flush()
                    try:
                        event=json.loads(line)
                    except ValueError:continue
                    if isinstance(event,dict):
                        arrivals.append(arrival);journal.write(json.dumps(arrival)+"\n");journal.flush()
                p.wait()
        process_end=time.monotonic()-start
    finally:
        override.unlink(missing_ok=True)
    stdout=(run/"agy-stdout.jsonl").read_text(encoding="utf-8",errors="replace") if (run/"agy-stdout.jsonl").is_file() else ""
    stderr=(run/"agy-stderr.txt").read_text(encoding="utf-8",errors="replace") if (run/"agy-stderr.txt").is_file() else ""
    records=[]
    for line in stdout.splitlines():
        try:
            x=json.loads(line)
            if isinstance(x,dict):records.append(x)
        except ValueError:pass
    # Evidence from the actual MCP event schema; no model-generated answer required for download validation.
    tools_seen=[]; outputs=[]; final=[]; first_pages=None; read_calls=0; server_names=set()
    for i,event in enumerate(records):
        step=event.get("step_update")
        if isinstance(step,dict):
            info=step.get("tool_info",{})
            if not isinstance(info,dict):continue
            params=info.get("parameters",{})
            if not isinstance(params,dict):params={}
            name=params.get("ToolName","")
            if step.get("tool_name")=="read_file" and "output" in info:read_calls+=1
            if step.get("tool_name")=="call_mcp_tool":
                for k in ("ServerName","Server","serverName","server"):
                    if isinstance(params.get(k),str):server_names.add(params[k])
                if isinstance(name,str) and name and ("output" in info or "error" in info):
                    tools_seen.append(name)
                    out=info.get("output","")
                    outputs.append({"event":i,"tool":name,"output":out,"error":info.get("error")})
                    if name=="list_pages" and first_pages is None:first_pages=out
        res=event.get("result")
        if event.get("event")=="result" and isinstance(res,dict):
            if isinstance(res.get("response"),str):final.append(res["response"])
    # Require evidence of the preflight tab in the first actual MCP output.
    first=str(first_pages or "")
    pages_seen=re.findall(r"(?m)^\s*\d+:\s*(.+)$",first)
    bound=int(sum(bool(re.search(r"https://"+re.escape(initial_host)+r"(?:/[^\s)]*)?(?:[)\s]|$)",line,re.I)) for line in pages_seen)==1)
    named=int(server_names=={"ttv-browser"})
    # Allow a short passive completion window after the model exits; never click again.
    if any(x.get("tool") in ("click","evaluate_script") for x in outputs):
        for _ in range(12):
            if any(str(f.resolve()) not in before and f.stat().st_mtime>=wall_start-1 for f in dest.iterdir() if f.is_file() and not f.is_symlink() and f.suffix.lower() in (".srt",".zip")):break
            time.sleep(1)
    history=profile/"Default"/"History"
    rows=[];history_ok=0
    if history.is_file():
        try:
            con=sqlite3.connect(history.resolve().as_uri()+"?mode=ro",uri=True,timeout=3)
            con.row_factory=sqlite3.Row
            # Chrome epoch in microseconds. Only downloads begun after this job started.
            cutoff=int((wall_start+11644473600)*1000000)
            for row in con.execute("select id,target_path,state,received_bytes,total_bytes,start_time from downloads where start_time>=? order by id",(cutoff,)):
                item=dict(row)
                item["chain"]=[x[0] for x in con.execute("select url from downloads_url_chains where id=? order by chain_index",(row["id"],))]
                rows.append(item)
            con.close();history_ok=1
        except (OSError,sqlite3.Error):pass
    artifacts=[];physical=[]
    # SubtitleCat links may use filename paths rather than numeric subtitle IDs.
    # Accept only new SRT/ZIP with actual first-party provenance; do not infer release match from download alone.
    def refs(urls):
        result=[]
        for url in urls:
            try:
                u=urllib.parse.urlsplit(str(url).strip("\x00"))
                if u.scheme=="https" and u.hostname in (os_hosts | {"dl.opensubtitles.org"}) and u.path not in ("","/"):
                    result.append(u.path)
            except ValueError:pass
        return list(dict.fromkeys(result))
    def add(f,links,provenance):
        if not links or any(v["filename"]==f.name for v in artifacts):return
        c=cue_count(f)
        if not c:return
        artifacts.append({"filename":f.name,"candidate_refs":links,"bytes":f.stat().st_size,"sha256":sha(f),"cues":c,"provenance":provenance})
    for row in rows:
        if row["state"]!=1 or row["received_bytes"]<=0:continue
        f=pathlib.Path(row["target_path"])
        if not f.is_file() or f.is_symlink() or not f.resolve().is_relative_to(dest.resolve()):continue
        if str(f.resolve()) in before or not 0<f.stat().st_size<=10000000:continue
        # Require at least one first-party provider link in the actual download chain.
        add(f,refs(row["chain"]),"ChromeHistory")
    for f in dest.iterdir():
        if not f.is_file() or f.is_symlink() or f.suffix.lower() not in (".srt",".zip"):continue
        if str(f.resolve()) in before or f.stat().st_mtime<wall_start-1 or not 0<f.stat().st_size<=10000000:continue
        c=cue_count(f)
        if not c:continue
        physical.append({"filename":f.name,"bytes":f.stat().st_size,"cues":c})
        if any(v["filename"]==f.name for v in artifacts):continue
        try:
            with open(str(f)+":Zone.Identifier","r",encoding="utf-8",errors="replace") as z:
                ads=dict(v.split("=",1) for v in z.read(8192).splitlines() if "=" in v)
            # Referrer alone is not download provenance. Require first-party HostUrl.
            add(f,refs([ads.get("HostUrl","")]),"Zone.Identifier")
        except (OSError,ValueError):pass
    for artifact in artifacts:
        src=dest/artifact["filename"]
        if src.is_file() and not src.is_symlink() and sha(src)==artifact["sha256"]:
            shutil.copy2(src,resultdir/src.name)
            artifact["copied_to_job"]=True
    # Separate list evidence from click and actual artifact. Never infer a successful download from a click.
    def filter_gate(outputs,artifacts):
        def url(v):
            if not isinstance(v,str) or not v:return None
            try:u=urllib.parse.urlsplit(urllib.parse.urljoin("https://www.opensubtitles.org/",v))
            except ValueError:return None
            return u if u.scheme=="https" and u.hostname in (os_hosts|{"dl.opensubtitles.org"}) else None
        def sid(v):
            u=url(v)
            m=re.search(r"/(?:subtitles|download/sub|subtitleserve/sub)/(\d+)(?:/|$)",u.path) if u else None
            return m[1] if m else ""
        def lang_en(v):
            return isinstance(v,str) and " ".join(v.casefold().split()) in {"english","en","eng","flag en"}
        def docs(v):
            if isinstance(v,dict):return [v]
            if not isinstance(v,str):return []
            blocks=re.findall(r"(?s)\x60\x60\x60(?:json)?\s*(\{.*?\})\s*\x60\x60\x60",v) or [v.strip()]
            result=[]
            for block in blocks:
                try:x=json.loads(block)
                except (ValueError,TypeError):continue
                if isinstance(x,dict):result.append(x)
            return result
        groups={};details={};clicks=[]
        for out in outputs:
            if out.get("error") or out.get("tool")!="evaluate_script":continue
            for d in docs(out.get("output")):
                u=url(d.get("url"))
                event=out["event"]
                did=sid(d.get("url"))
                if did and d.get("btnVisible") is True and isinstance(d.get("fieldsetText"),str) and d["fieldsetText"] and sid(d.get("downloadHref"))==did:
                    details.setdefault(did,[]).append(event)
                if d.get("clicked") is True:
                    cid=sid(d.get("pageUrl"))
                    if cid and str(d.get("id"))==cid and sid(d.get("href"))==cid and "downloaderChecked" in d and d["downloaderChecked"] in (False,None):
                        clicks.append((cid,event))
                if not u:continue
                heading=str(d.get("heading",""))
                if not re.search(r"(?:^|/)sublanguageid-eng(?:/|$)",u.path) or not re.search(r"\benglish\b",heading,re.I):continue
                total=d.get("total_english"); rows=d.get("rows"); nxt=d.get("has_next")
                if type(nxt) is not bool or not isinstance(rows,list) or not rows:continue
                found={sid(x.get("href")) for x in rows if isinstance(x,dict) and lang_en(x.get("lang"))}-{""}
                if len(found)!=len(rows):continue
                key=re.sub(r"/offset-\d+","",u.path)
                g=groups.setdefault(key,{"ids":set(),"totals":set(),"last":False,"events":[],"bad_count":False})
                g["ids"].update(found);g["last"]|=not nxt;g["events"].append(event)
                if type(total) is int and 0<total<=500 and d.get("count_scope")=="filtered_results" and isinstance(d.get("count_label"),str) and d["count_label"].strip():g["totals"].add(total)
                else:g["bad_count"]=True
        complete=[g for g in groups.values() if not g["bad_count"] and g["totals"]=={len(g["ids"])} and g["last"]]
        list_ok=len(complete)==1
        chosen="";click_ok=False
        if len(clicks)==1:
            chosen,event=clicks[0]
            matching=[g for g in groups.values() if chosen in g["ids"] and any(max(g["events"])<x<event for x in details.get(chosen,[]))]
            click_ok=len(matching)==1
        ids={sid(x) for x in artifacts[0].get("candidate_refs",[])}-{""} if len(artifacts)==1 and artifacts[0].get("copied_to_job") is True else set()
        download_ok=bool(click_ok and ids=={chosen})
        return {"accepted":bool(list_ok and click_ok and download_ok),"reason":"ENGLISH_LIST_AND_DOWNLOAD_BOUND" if list_ok and download_ok else "DOWNLOAD_BOUND_LIST_COVERAGE_HOLD" if download_ok else "DOWNLOAD_UNVERIFIED" if click_ok else "CLICK_UNBOUND" if list_ok else "LIST_COVERAGE_UNVERIFIED","english_list_verified":list_ok,"english_candidates":len(complete[0]["ids"]) if list_ok else 0,"english_rows_observed":len(next(iter(groups.values()))["ids"]) if len(groups)==1 else 0,"ordinary_click_bound":click_ok,"download_verified":download_ok,"detail_candidates":len(details),"release_compatibility_verified":False}
    filter_result=filter_gate(outputs,artifacts)
    write(run/"BRAIN_FILTER_QA.json",filter_result)
    def related(line,artifact):
        norm=urllib.parse.unquote(str(line)).casefold()
        keys=[artifact["filename"]]+[urllib.parse.unquote(x) for x in artifact["candidate_refs"]]
        return any(len(k)>8 and k.casefold() in norm for k in keys)
    titlematch=0
    for item in outputs:
        out=str(item.get("output",""))
        if re.search(r"\b"+r"[ ._-]*".join(re.escape(v) for v in title.split())+r"\b",out,re.I) and re.search(r"\benglish\b|\beng\b",out,re.I) and any(related(out,x) for x in artifacts):
            titlematch=1
    # Capture observed release clues without promoting them to playback-sync proof.
    release_candidates=[]
    for item in outputs:
        out=str(item.get("output",""))
        for line in out.splitlines():
            if norm(title) in norm(line) and re.search(r"web[ ._-]*(?:dl|rip)|bluray|repack",line,re.I):
                release_candidates.append({"event":item["event"],"observed_release_text":line[:2000]})
    # Conservative exact-release evidence: same observed line binds actual downloaded ID and full release.
    exact_re=r"[ ._()\-]*".join(re.escape(v) for v in re.findall(r"[A-Za-z0-9]+",release))
    exact=int(any(re.search(exact_re,line,re.I) and any(related(line,x) for x in artifacts) for item in outputs for line in str(item.get("output","")).splitlines()))
    elapsed=round(time.monotonic()-start)
    if len(arrivals)!=len(records):raise ValueError("stream timing drift")
    # Pair only explicit, stable step identifiers; do not guess from order.
    def step_id(e,st):
        for obj in (st,e):
            for k in ("step_id","stepId","tool_call_id","toolCallId"):
                v=obj.get(k)
                if isinstance(v,str) and 0<len(v)<=256:return v
                if type(v) is int:return str(v)
        return None
    opened={};paired=[];outcome_times=[];first_mcp=None;ambiguous=set()
    for i,e in enumerate(records):
        st=e.get("step_update",{})
        if not isinstance(st,dict) or st.get("tool_name")!="call_mcp_tool":continue
        info=st.get("tool_info",{})
        if not isinstance(info,dict):continue
        if first_mcp is None:first_mcp=arrivals[i]
        ident=step_id(e,st)
        complete="output" in info or "error" in info
        if complete:
            outcome_times.append(arrivals[i])
            if ident is not None and ident in opened and ident not in ambiguous:
                a=opened.pop(ident)
                if arrivals[i]>=a:paired.append((a,arrivals[i]))
                ambiguous.add(ident)
        elif ident is not None and ident not in ambiguous and ident not in opened:
            opened[ident]=arrivals[i]
    intervals=[]
    for a,b in sorted(paired):
        if intervals and a<=intervals[-1][1]:intervals[-1][1]=max(intervals[-1][1],b)
        else:intervals.append([a,b])
    # Time spent in correlated observed MCP spans, not pure browser execution.
    observed=sum(b-a for a,b in intervals)
    first=round(arrivals[0]) if arrivals else -1
    first_tool=round(first_mcp) if first_mcp is not None else -1
    last=round(outcome_times[-1]) if outcome_times else -1
    download=-1
    if len(artifacts)==1:
        f=resultdir/artifacts[0]["filename"]
        if f.is_file() and sha(f)==artifacts[0]["sha256"]:
            d=f.stat().st_mtime-wall_start
            if 0<=d<=elapsed+3:download=round(d)
    write(run/"stream-timing.json",{"schema":"TTV-STREAM-ARRIVAL-V1","event_arrival_seconds":arrivals,"cli_end":process_end,"first_mcp":first_mcp,"mcp_outcome_seconds":outcome_times,"paired_mcp_spans":paired,"paired_mcp_union":observed,"download_mtime_elapsed":download,"elapsed_before_report":elapsed})
    def val(x):return str(x) if x>=0 else "X"
    denied=int(bool(re.search(r"permission check failed|auto-denied|user denied permission|permission denied",stdout+"\n"+stderr,re.I)))
    drift=int([sha(x) for x in paths]!=config_before)
    # A file may be acquired despite a missing final answer or a later tool error.
    access_evidence="\n".join(str(v.get("output","")) for v in outputs)
    challenge=bool(re.search(r"making sure you.re not a bot|/\.within\.website/|anti.bot challenge|captcha",access_evidence,re.I))
    provider_access="ACCESS_BLOCKED" if challenge else "SITE_TAB_OBSERVED"
    selection_evaluation="NOT_TESTED" if challenge else "ENGLISH_LIST_AND_DOWNLOAD_BOUND" if filter_result["accepted"] else "DOWNLOAD_BOUND_LIST_COVERAGE_HOLD" if filter_result["download_verified"] else "FILTER_HOLD"
    report={"source_commit":os.environ.get("TTV_PINNED_SOURCE",""),"model":"gemini-4-hydrogen-low","provider":"OpenSubtitles","provider_access":provider_access,"selection_evaluation":selection_evaluation,"filter_gate":filter_result,"recipe_version":"V12_1_BT18_NEXT","elapsed_seconds":elapsed,"event_count":len(records),"exit":p.returncode if p else None,"final_response":final,"tool_outcomes":outputs,"tool_names":tools_seen,"read_file_calls":read_calls,"first_list_pages":first,"server_names":sorted(server_names),"initial_mcp_task_tab":bool(bound),"cold_profile":False,"server_name_verified":bool(named),"history_read":bool(history_ok),"downloads":rows,"artifacts":artifacts,"physical_files":physical,"observed_release_candidates":release_candidates,"video_input":video_input,"title_language_evidence":bool(titlematch),"exact_release_line_evidence":bool(exact),"release_match_verified":False,"playback_sync_verified":False,"permission_denied":bool(denied),"shared_config_drift":bool(drift),"stderr":stderr}
    write(run/"BRAIN_TEACHER_REPORT.json",report)
    (run/"BRAIN_TEACHER_FULL_RESPONSE.md").write_text("# Hydrogen Low OpenSubtitles Student V12.1 next benchmark\n\n## Final response\n\n"+("\n\n".join(final) or "[No final response recovered]")+"\n\n## Tool outcomes and verified evidence\n\n"+json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
    n=sum(1 for f in artifacts if f["cues"]>0);c=max((f["cues"] for f in artifacts),default=0)
    # Full raw tool calls, parameters and results stay private; Brain receives every event's safe typed projection.
    known={"list_pages","select_page","navigate_page","take_snapshot","click","fill","press_key","wait_for","evaluate_script","read_file","write_file","run_shell_command","execute_command","list_network_requests","call_mcp_tool"}
    trace=[]
    for i,e in enumerate(records):
        st=e.get("step_update") if isinstance(e.get("step_update"),dict) else {}
        info=st.get("tool_info") if isinstance(st.get("tool_info"),dict) else {}
        params=info.get("parameters") if isinstance(info.get("parameters"),dict) else {}
        tool=params.get("ToolName") if st.get("tool_name")=="call_mcp_tool" else st.get("tool_name")
        tool=tool.upper() if isinstance(tool,str) and tool in known else "OTHER"
        kind="RESULT" if e.get("event")=="result" else "ERROR" if any(x not in (None,"",False,[],{}) for x in (info.get("error"),st.get("error"),e.get("error"))) else "OUTPUT" if "output" in info else "CALL" if tool!="OTHER" else "OTHER"
        trace.append(f"{i}:{round(arrivals[i]*1000)}:{tool}:{kind}")
    final_json=None
    for answer in reversed(final):
        for match0 in re.finditer(r"\{",answer):
            try:obj,_=json.JSONDecoder().raw_decode(answer[match0.start():])
            except ValueError:continue
            if isinstance(obj,dict) and isinstance(obj.get("actions"),list) and isinstance(obj.get("reusable_recipe"),list):
                final_json=obj
                break
        if final_json is not None:break
    if final_json is not None:write(run/"TEACHER_RECIPE_PRIVATE.json",final_json)
    nonce=os.environ["TTV_READOUT_NONCE"]
    summary={"schema":"TTV-BT04-TRACE-V1","nonce":nonce,"source":os.environ["TTV_PINNED_SOURCE"],"elapsed":elapsed,"download":download,"cues":c,"artifacts":n,"events":len(records),"final_chars":len("\n".join(final)),"report_ok":int(final_json is not None),"actions":len(final_json["actions"]) if final_json else 0,"recipe_steps":len(final_json["reusable_recipe"]) if final_json else 0,"title_language":titlematch,"exact":exact,"denied":denied,"drift":drift,"trace":trace}
    write(pathlib.Path(os.environ["ProgramData"])/"TorrentTVVietsub"/"LaptopHostOps"/"Receipts"/("bt04-trace-"+nonce+".json"),summary)
    return f"BT18_T{elapsed}F{val(first)}B{val(first_tool)}L{val(last)}D{val(download)}P{round(process_end)}K{len(outcome_times)}J{len(paired)}M{round(observed)}A{n}C{min(c,99999)}G{int(filter_result['accepted'])}E{int(filter_result['english_list_verified'])}B{int(filter_result['ordinary_click_bound'])}"

try:print(probe())
except Exception as e:
    (run/"probe-error.txt").write_text(type(e).__name__+": "+str(e),encoding="utf-8")
    print("BT05_LOCAL_ERROR")
'@
$f=Join-Path $run 'control.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $owner $run $profile 2> (Join-Path $run 'python-stderr.txt'))
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,80}$'){$code=[string]$out[0]}else{$code='TR04A_LOCAL_ERROR'}
}
} finally { Export-BrainReport 'LIVE' $code }
$stable9444=[int](($before9444 -join ',') -ceq (@(Listener 9444) -join ','))
$stable9555=[int](($active9555 -join ',') -ceq (@(Listener 9555) -join ','))
$stableOwner=[int]($ownerState -ceq [string](Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\').State)
$code=$code+'_W'+$stable9444+'B'+$stable9555+'O'+$stableOwner+'S'+$started9555
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
