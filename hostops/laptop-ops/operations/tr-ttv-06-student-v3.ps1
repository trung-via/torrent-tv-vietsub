# TR-TTV.16: V4 unchanged prompt, instrumented stream receipt timings.
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
$run=Join-Path $root ('tr-ttv-18-neon-teacher-v1-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
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
$code='TR18_BROWSER_NOT_VERIFIED'
if([string]$hostTask.Settings.ExecutionTimeLimit -ne 'PT0S'){$code='TR04C_TASK_LIMIT'}
else{
 # Recover only the enrolled dedicated profile when its browser is actually absent.
 # Never kill another process, replace the profile, or rotate endpoints.
 if($active9555.Count -eq 0){
  $roots=@(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object {$_.CommandLine -and $_.CommandLine -notmatch '--type=' -and $_.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0})
  $chrome=Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'
  if($roots.Count -ne 0){$code='TR18_PROFILE_RUNNING_NO_LISTENER'}
  elseif(-not (Test-Path -LiteralPath $profile -PathType Container) -or -not (Test-Path -LiteralPath $chrome -PathType Leaf)){$code='TR18_PROFILE_OR_CHROME_MISSING'}
  else{
   Start-Process -FilePath $chrome -ArgumentList @('--user-data-dir="'+$profile+'"','--remote-debugging-port=9555','--remote-debugging-address=127.0.0.1','--no-first-run','--no-default-browser-check','--new-window','https://www.opensubtitles.org/')
   $started9555=1
   for($i=0;$i -lt 30;$i++){
    Start-Sleep -Milliseconds 500
    $active9555=@(Listener 9555)
    if($active9555.Count -eq 1){break}
   }
   $code='TR18_RESTORE_NO_LISTENER'
  }
 }
 if($active9555.Count -gt 1){$code='TR18_LISTENER_AMBIGUOUS'}
 elseif($active9555.Count -eq 1){
  $p=Get-CimInstance Win32_Process -Filter ("ProcessId="+$active9555[0])
  $ls=@(Get-NetTCPConnection -LocalPort 9555 -State Listen -ErrorAction SilentlyContinue)
  if($p -and $p.Name -eq 'chrome.exe' -and $p.CommandLine -and $p.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0 -and $p.CommandLine -match '(?:^|\s|")--remote-debugging-port=9555(?:\s|"|\z)' -and @($ls|Where-Object {$_.LocalAddress -notin @('127.0.0.1','::1')}).Count -eq 0){
   $verified=$true
  }else{$code='TR18_LISTENER_IDENTITY_MISMATCH'}
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
    env["TTV_AGY_MODEL"]=_validated_antigravity_alias("gemini-4-neon-high","high")
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

    if any(re.search(r"/\.within\.website/|making sure you.re not a bot|captcha|access denied|just a moment|forbidden",t.get("url","")+" "+t.get("title",""),re.I) for t in site):return "TR18_ACCESS_BLOCKED_PRE"
    if len(site)!=1:return "TR18_TASK_TAB_AMBIGUOUS"
    target=site[0]
    u=urllib.parse.urlsplit(target.get("url",""))
    if u.scheme!="https":return "TR18_TASK_TAB_UNVERIFIED"
    initial_host=u.hostname
    # Keep original browser download preferences unchanged; snapshot known download directory.
    prefs=read(profile/"Default"/"Preferences")
    download=prefs.get("download",{})
    dest=pathlib.Path(os.path.expandvars(download.get("default_directory") or str(home/"Downloads")))
    if not dest.is_absolute() or not dest.is_dir():return "TR18_DOWNLOAD_DIR_UNVERIFIED"
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
    # Bind prior reports to exact run source and measured outcomes. Export only typed facts to teacher.
    baseline=[]
    known_tools={"list_pages","select_page","navigate_page","take_snapshot","click","fill","press_key","wait_for","evaluate_script"}
    for prefix,source,provider,elapsed0,cues0 in (
        ("tr-ttv-16-kalki2898ad-subtitlecat-v4-profile-","6e28d723bf95611bb8a4541cd54ea0e1bcf74fdc","SubtitleCat",122,1672),
        ("tr-ttv-17-kalki2898ad-opensubtitles-v4-profile-","bfc80f4cd94c800e92ae3ab63e25227c1e2bb7b6","OpenSubtitles",133,1670)):
        matches=[]
        for folder in run.parent.glob(prefix+"*"):
            p0=folder/"BRAIN_STUDENT_REPORT.json"
            if folder.is_symlink() or p0.is_symlink() or not p0.is_file() or p0.stat().st_size>16777216:continue
            rr=json.loads(p0.read_text(encoding="utf-8-sig"))
            if rr.get("source_commit")==source and rr.get("provider")==provider and rr.get("elapsed_seconds")==elapsed0 and max((a.get("cues",0) for a in rr.get("artifacts",[])),default=0)==cues0:matches.append(rr)
        if len(matches)!=1:return "TR18_BASELINE_NOT_UNIQUE"
        rr=matches[0]
        baseline.append({"provider":provider,"elapsed":elapsed0,"cues":cues0,"tool_sequence":[x if x in known_tools else "OTHER" for x in rr.get("tool_names",[])],"title_language_bound":bool(rr.get("title_language_evidence")),"release_exact":bool(rr.get("exact_release_line_evidence")),"final_present":bool(rr.get("final_response"))})
    write(run/"teacher-baseline.json",baseline)
    prompt="You are the Gemini 4 Neon High Teacher for Torrent TV Vietsub. The objective is to train Gemini 4 Hydrogen Low to independently find and download a correctly matched English subtitle on OpenSubtitles.org using ordinary authorized website actions. You are the trainer, not merely a reviewer. Baselines with the identical release: SubtitleCat V7 took 122 seconds total, download at 109 seconds, 10 browser outcomes, 1672 cues. OpenSubtitles TR17 took 133 seconds total, download at 123 seconds, 9 browser outcomes, 1670 cues. First observed browser tool event at 41/40 seconds respectively. Neither run established title/language binding to the downloaded artifact or release/timeline compatibility. G1 target is first Vietnamese cue on the TV within 120 seconds including translation and delivery; propose a practical acquisition budget and measurable quality gates. Do not claim timing overhead is model reasoning without proof.\n\nPerform the following steps: (1) assess prior observations supplied below, including actual tool sequences, and identify waste, missing evidence, uncertainty, and a discriminating latency experiment. (2) Demonstrate an efficient ordinary OpenSubtitles workflow live in the verified dedicated Chrome CDP 9555 with ttv-browser. Exact demonstration input Kalki.2898.AD.2024.1080p.WEB-DL.ViruseProject, English, displayed size 12.8 GB, FPS/duration/cut/audio unknown. Use list_pages, only existing dedicated OpenSubtitles tab (or navigate existing SubtitleCat task tab to https://www.opensubtitles.org/), no unrelated tabs or other providers. Search and select a candidate yourself, record visible title/year/language/release and candidate reference bound to the selected item, download at most once by the ordinary site action if a plausible EN candidate exists. No guessed endpoints, hidden data, challenge bypass, login or payment actions, no global settings changes. Stop on access restrictions. Do not invent missing release or sync evidence. (3) Derive a reusable Recipe V5 for Hydrogen Low, with concise steps, decision rules, examples abstracted from observations, negative cases, failure handling, and required evidence. Never include the demonstration candidate ID, URL, exact answer, local paths, credentials, or subtitle text in the transferable recipe. (4) Design a student exercise with a blind film input, a grading rubric, and feedback/retry criteria. Teacher should choose method rather than being forced into a fixed sequence. Report precise actions, rationale summaries and observations, failed approaches, demonstrated facts vs proposed improvements, what remains unverified, and how to measure improvement. Do not modify production, TV, Owner, or shared settings. Never label acquisition as playback sync. No arbitrary benchmark deadline.\n\nReturn a detailed JSON object, preferably as the final response, with fields status (CANDIDATE_DOWNLOADED, NO_PLAUSIBLE_CANDIDATE, ACCESS_BLOCKED, AUTH_REQUIRED, DOWNLOAD_FAILED, TOOL_UNAVAILABLE, UNKNOWN), release_match (EXACT_METADATA, EVIDENCED_COMPATIBLE, UNKNOWN, CONFLICT), observed_evidence, diagnosis, demonstration_steps, recipe_v5 (array of concise reusable instructions), student_exercise, grading_rubric, latency_experiment, acquisition_budget_seconds (integer), limitations, and usage if known. Also include report_codes (array chosen only from QUERY_TITLE_YEAR, FILTER_ENGLISH, MATCH_RELEASE, CHECK_DETAIL, BIND_CANDIDATE, DOWNLOAD_ONCE, COMPACT_DOM, AVOID_REPEAT_SNAPSHOT, STOP_ON_DENIAL, MARK_UNKNOWN_METADATA, CHECK_TIMELINE, MEASURE_STARTUP, MEASURE_TOOL_LATENCY, BLIND_STUDENT_TEST, HOST_VERIFY_FILE). Codes are a privacy-safe summary of your own actual recommendations, not mandatory selections. Preserve full detailed final response locally. The host will independently measure time and verify downloads."+"\nPrior observed traces: "+json.dumps(baseline,ensure_ascii=True)
    (run/"teacher-prompt.txt").write_text(prompt,encoding="utf-8")
    env["TTV_AGY_PROMPT"]=str(run/"teacher-prompt.txt")
    cmd="$ErrorActionPreference='Stop'; $p=Get-Content -LiteralPath $env:TTV_AGY_PROMPT -Raw; & $env:TTV_AGY_CLI --model $env:TTV_AGY_MODEL --sandbox --settings $env:TTV_SESSION_SETTINGS --output-format stream-json -p $p; exit $LASTEXITCODE"
    start=time.monotonic()
    wall_start=time.time()
    arrivals=[]
    # Record only host-side arrival times. These include child buffering and are
    # not internal model clocks. Keep stderr separate to avoid a pipe deadlock.
    try:
        with (run/"agy-stdout.jsonl").open("w",encoding="utf-8",newline="") as out, (run/"agy-stderr.txt").open("wb") as err:
            with subprocess.Popen([ps,"-NoProfile","-NonInteractive","-Command",cmd],env=env,cwd=run,stdout=subprocess.PIPE,stderr=err,text=True,encoding="utf-8",errors="replace",bufsize=1) as p:
                for line in p.stdout:
                    arrival=time.monotonic()-start
                    out.write(line)
                    try:
                        event=json.loads(line)
                    except ValueError:continue
                    if isinstance(event,dict):arrivals.append(arrival)
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
    # Only observed OpenSubtitles first-party website/download links.
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
    def related(line,artifact):
        norm=urllib.parse.unquote(str(line)).casefold()
        keys=[artifact["filename"]]+[urllib.parse.unquote(x) for x in artifact["candidate_refs"]]
        return any(len(k)>8 and k.casefold() in norm for k in keys)
    titlematch=0
    for item in outputs:
        out=str(item.get("output",""))
        if re.search(r"\bkalki[ ._-]*2898[ ._-]*ad\b",out,re.I) and re.search(r"\benglish\b|\beng\b",out,re.I) and any(related(out,x) for x in artifacts):
            titlematch=1
    # Capture observed release clues without promoting them to playback-sync proof.
    release_candidates=[]
    for item in outputs:
        out=str(item.get("output",""))
        for line in out.splitlines():
            if re.search(r"kalki[ ._-]*2898[ ._-]*ad\b",line,re.I) and re.search(r"web[ ._-]*dl|viruseproject",line,re.I):
                release_candidates.append({"event":item["event"],"observed_release_text":line[:2000]})
    # Conservative exact-release evidence: same observed line binds actual downloaded ID and full release.
    exact_re=r"kalki[ ._-]*2898[ ._-]*ad[ ._-]+2024[ ._-]+1080p[ ._-]+web[ ._-]*dl[ ._-]+viruseproject\b"
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
    selection_evaluation="NOT_TESTED" if challenge else "RELEASE_METADATA_UNVERIFIED"
    report={"source_commit":os.environ.get("TTV_PINNED_SOURCE",""),"model":"gemini-4-neon-high","provider":"OpenSubtitles","provider_access":provider_access,"selection_evaluation":selection_evaluation,"recipe_version":"TEACHER_V1","elapsed_seconds":elapsed,"event_count":len(records),"exit":p.returncode if p else None,"final_response":final,"tool_outcomes":outputs,"tool_names":tools_seen,"read_file_calls":read_calls,"first_list_pages":first,"server_names":sorted(server_names),"initial_mcp_task_tab":bool(bound),"cold_profile":False,"server_name_verified":bool(named),"history_read":bool(history_ok),"downloads":rows,"artifacts":artifacts,"physical_files":physical,"observed_release_candidates":release_candidates,"video_input":{"title":"Kalki 2898 AD","year":2024,"release":"Kalki.2898.AD.2024.1080p.WEB-DL.ViruseProject","release_origin":"OWNER_SUPPLIED","display_size":"12.8 GB","fps":None,"duration":None},"title_language_evidence":bool(titlematch),"exact_release_line_evidence":bool(exact),"release_match_verified":False,"playback_sync_verified":False,"permission_denied":bool(denied),"shared_config_drift":bool(drift),"stderr":stderr}
    write(run/"BRAIN_TEACHER_REPORT.json",report)
    (run/"BRAIN_TEACHER_FULL_RESPONSE.md").write_text("# Neon High Teacher demonstration and training V5\n\n## Final response\n\n"+("\n\n".join(final) or "[No final response recovered]")+"\n\n## Tool outcomes and verified evidence\n\n"+json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
    n=sum(1 for f in artifacts if f["cues"]>0);c=max((f["cues"] for f in artifacts),default=0)
    # Typed allowlist projection only. Keep original text and raw browser events private.
    answer="\n".join(final)
    def label(key,allowed):
        found=[a for a in allowed if re.search(r"(?im)\b"+re.escape(key)+r"[\s*\"':=]+[\"']?"+re.escape(a)+r"\b",answer)]
        return found[0] if len(found)==1 else "NOT_REPORTED"
    nonce=os.environ["TTV_READOUT_NONCE"]
    if not re.fullmatch(r"[a-f0-9]{32}",nonce):raise ValueError("bad nonce")
    # Parse final JSON without copying untrusted text into workflow logs.
    teacher={}
    for response in reversed(final):
        for match in re.finditer(r"\{",response):
            try:
                obj,_=json.JSONDecoder().raw_decode(response[match.start():])
            except ValueError:continue
            if isinstance(obj,dict) and isinstance(obj.get("recipe_v5"),list):
                teacher=obj;break
        if teacher:break
    allowed_codes={"QUERY_TITLE_YEAR","FILTER_ENGLISH","MATCH_RELEASE","CHECK_DETAIL","BIND_CANDIDATE","DOWNLOAD_ONCE","COMPACT_DOM","AVOID_REPEAT_SNAPSHOT","STOP_ON_DENIAL","MARK_UNKNOWN_METADATA","CHECK_TIMELINE","MEASURE_STARTUP","MEASURE_TOOL_LATENCY","BLIND_STUDENT_TEST","HOST_VERIFY_FILE"}
    raw_codes=teacher.get("report_codes",[])
    codes=sorted({x for x in raw_codes if isinstance(x,str) and x in allowed_codes}) if isinstance(raw_codes,list) else []
    raw_recipe=teacher.get("recipe_v5",[])
    recipe=[x for x in raw_recipe if isinstance(x,str) and 0<len(x)<=1500][:30]
    # Persist teacher-authored instructions for a later separate student job; no automatic injection yet.
    if recipe:write(run/"TEACHER_RECIPE_V5_PRIVATE.json",{"source":report["source_commit"],"teacher":"gemini-4-neon-high","recipe":recipe})
    section_names=("diagnosis","demonstration_steps","student_exercise","grading_rubric","latency_experiment","limitations","observed_evidence")
    sections=sum(bool(teacher.get(k)) for k in section_names)
    budget=teacher.get("acquisition_budget_seconds")
    budget=budget if type(budget) is int and 1<=budget<=120 else -1
    safe={"schema":"TTV-AGY-BRAIN-READOUT-V1","nonce":nonce,"source":report["source_commit"],"provider":"OpenSubtitles","model":"gemini-4-neon-high","recipe":"TEACHER_V1","elapsed":elapsed,"download_seconds":download,"tools":len(outcome_times),"cues":c,"artifacts":n,"final_present":bool(answer.strip()),"final_status":label("status",("CANDIDATE_DOWNLOADED","NO_PLAUSIBLE_CANDIDATE","ACCESS_BLOCKED","AUTH_REQUIRED","DOWNLOAD_FAILED","TOOL_UNAVAILABLE","UNKNOWN")),"final_release":label("release_match",("EXACT_METADATA","EVIDENCED_COMPATIBLE","UNKNOWN","CONFLICT")),"title_language":bool(titlematch),"exact_release":bool(exact),"release_verified":False,"sync_verified":False,"permission_denied":bool(denied),"config_drift":bool(drift),"provider_access":provider_access,"teacher_json":bool(teacher),"teacher_recipe_steps":len(recipe),"teacher_report_sections":sections,"teacher_budget":budget,"teacher_codes":codes,"baseline_count":len(baseline)}
    write(pathlib.Path(os.environ["ProgramData"])/"TorrentTVVietsub"/"LaptopHostOps"/"Receipts"/("agy-brain-readout-"+nonce+".json"),safe)
    return f"TR18_T{elapsed}F{val(first)}B{val(first_tool)}L{val(last)}D{val(download)}P{round(process_end)}K{len(outcome_times)}J{len(paired)}M{round(observed)}A{n}C{min(c,99999)}"

try:print(probe())
except Exception as e:
    (run/"probe-error.txt").write_text(type(e).__name__+": "+str(e),encoding="utf-8")
    print("TR04A_LOCAL_ERROR")
'@
$f=Join-Path $run 'control.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $owner $run $profile 2> (Join-Path $run 'python-stderr.txt'))
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,65}$'){$code=[string]$out[0]}else{$code='TR04A_LOCAL_ERROR'}
}
$stable9444=[int](($before9444 -join ',') -ceq (@(Listener 9444) -join ','))
$stable9555=[int](($active9555 -join ',') -ceq (@(Listener 9555) -join ','))
$stableOwner=[int]($ownerState -ceq [string](Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\').State)
$code=$code+'_W'+$stable9444+'B'+$stable9555+'O'+$stableOwner+'S'+$started9555
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
