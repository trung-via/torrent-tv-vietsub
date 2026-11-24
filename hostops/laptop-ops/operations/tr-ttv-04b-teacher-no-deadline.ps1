# TR-TTV.05b: Owner-approved blind acquisition, new Chrome profile 9557.
# Never edit shared settings or touch Owner production.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$env:TTV_PINNED_SOURCE=[string]$rq.source_commit
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('tr-ttv-05b-student-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
function Listener([int]$port){
  @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique)
}
$before9444=@(Listener 9444)
$before9555=@(Listener 9555)
$task=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'
$ownerState=[string]$task.State
$hostTask=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-Laptop-HostOps' -TaskPath '\'
$profile=Join-Path $run 'ChromeBlindProfile'
$downloadDir=Join-Path $run 'browser-downloads'
$active9557=@(Listener 9557)
$started9557=0
$verified=$false
$code='TR04C_PORT_BUSY'
if([string]$hostTask.Settings.ExecutionTimeLimit -ne 'PT0S'){$code='TR04C_TASK_LIMIT'}
elseif($active9557.Count -eq 0){
 $chrome=@(
   (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
   (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
 )|Where-Object {Test-Path -LiteralPath $_ -PathType Leaf}|Select-Object -First 1
 if($chrome){
  if((Test-Path -LiteralPath $profile) -or (Test-Path -LiteralPath $downloadDir)){throw 'BLIND_PROFILE_NOT_FRESH'}
  New-Item -ItemType Directory -Path (Join-Path $profile 'Default') -ErrorAction Stop|Out-Null
  New-Item -ItemType Directory -Path $downloadDir -ErrorAction Stop|Out-Null
  $prefs=@{download=@{default_directory=$downloadDir;prompt_for_download=$false;directory_upgrade=$true};browser=@{check_default_browser=$false}}
  [IO.File]::WriteAllText((Join-Path $profile 'Default\Preferences'),($prefs|ConvertTo-Json -Depth 4 -Compress),[Text.UTF8Encoding]::new($false))
  $profileArg='--user-data-dir="'+$profile+'"'
  Start-Process -FilePath $chrome -ArgumentList @($profileArg,'--remote-debugging-port=9557','--remote-debugging-address=127.0.0.1','--no-first-run','--no-default-browser-check','about:blank')|Out-Null
  $started9557=1
  for($i=0;$i -lt 30;$i++){
   Start-Sleep -Milliseconds 500
   $active9557=@(Listener 9557)
   if($active9557.Count -gt 0){break}
  }
  $code='TR04C_NO_LISTENER'
  if($active9557.Count -eq 1){
   $p=Get-CimInstance Win32_Process -Filter ("ProcessId="+$active9557[0])
   $listeners=@(Get-NetTCPConnection -LocalPort 9557 -State Listen -ErrorAction SilentlyContinue)
   if($p -and $p.Name -eq 'chrome.exe' -and $p.CommandLine -match '(?:^|\s|")--remote-debugging-port=9557(?:\s|"|\z)' -and $p.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0 -and @($listeners|Where-Object {$_.LocalAddress -notin @('127.0.0.1','::1')}).Count -eq 0){$verified=$true}
   else{$code='TR04C_PROFILE_MISMATCH'}
  }
 }else{$code='TR04C_CHROME_MISSING'}
}
if($verified){
$py=@'
import sys,pathlib,os,json,re,subprocess,hashlib,shutil,urllib.request,urllib.parse,time,zipfile,sqlite3
owner,run=map(pathlib.Path,sys.argv[1:])
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
    if "ttv-student-9557" in servers:return "TR04A_GLOBAL_TTV_CONFLICT"
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
    write(agents/"mcp_config.json",{"mcpServers":{"ttv-student-9557":{"command":"cmd.exe","args":["/d","/c","npx","-y","chrome-devtools-mcp@1.14.0","--browser-url=http://127.0.0.1:9557","--no-usage-statistics"]}}})
    # Confirm loopback Chrome without reading tabs or visiting a website.
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open("http://127.0.0.1:9557/json/version",timeout=3) as f:version=json.load(f)
    if not str(version.get("Browser","")).startswith("Chrome/") or not str(version.get("webSocketDebuggerUrl","")).startswith("ws://127.0.0.1:9557/"):return "TR04A_ENDPOINT_UNVERIFIED"
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
            if isinstance(rule,str) and (rule.startswith("mcp(ttv-student-9557") or rule=="mcp(*)"):return "TR04A_EXISTING_RESTRICTION"
    # Explicit tool grants limited to this benchmark and native 9555 server.
    tools=("list_pages","new_page","select_page","navigate_page","take_snapshot","click","fill","press_key","wait_for","close_page","evaluate_script")
    for k in ("deny","ask"):
        if any(isinstance(v,str) and (v.startswith("mcp(ttv-student-9557") or v=="mcp(*)") for v in perms.get(k,[])):return "TR04B_EXISTING_RESTRICTION"
    allowed=perms.setdefault("allow",[])
    for tool in tools:
        rule="mcp(ttv-student-9557/"+tool+")"
        if rule not in allowed:allowed.append(rule)
    if config.get("agentMode")=="auto":config.pop("agentMode")
    override=run/"session-settings.json"
    write(override,config)
    env["TTV_SESSION_SETTINGS"]=str(override)
    env["TTV_AGY_MODEL"]=_validated_antigravity_alias("gemini-4-hydrogen-low","low")
    # The new dedicated profile has an initially empty download directory.
    with opener.open("http://127.0.0.1:9557/json/list",timeout=3) as f:tabs=json.load(f)
    pages=[t for t in tabs if t.get("type")=="page"]
    if len(pages)!=1 or pages[0].get("url")!="about:blank":return "TR04C_NOT_BLANK"
    dirs={run/"browser-downloads"}
    if any((run/"browser-downloads").iterdir()):return "TR04C_DOWNLOAD_DIR_DIRTY"
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
    def verify_new_download(before,after,selected_id):
        # Only accept one newly created artifact, not pre-existing or overwritten names.
        # Chrome's origin metadata must bind the download to the normal issued link
        # and candidate; no guess at a provider URL and no model-only success.
        good=[]
        for key,(size,mtime) in after.items():
            if key in before or not 0<size<=10000000:continue
            f=pathlib.Path(key)
            try:
                with open(str(f)+":Zone.Identifier","r",encoding="utf-8",errors="replace") as stream:
                    fields=dict(x.split("=",1) for x in stream.read(8192).splitlines() if "=" in x)
                u=urllib.parse.urlsplit(fields.get("HostUrl",""))
                ref=fields.get("ReferrerUrl","")
                if u.scheme!="https" or u.hostname!="dl.opensubtitles.org":continue
                if not re.search(r"(?<!\d)"+re.escape(selected_id)+r"(?!\d)",u.path+" "+u.query+" "+ref):continue
                cues=cue_count(f)
                if cues:good.append((f,cues))
            except (OSError,ValueError):pass
        return good[0] if len(good)==1 else (None,0)
    downloads=run/"downloads";downloads.mkdir()
    before=candidates()
    prompt="You are the English subtitle acquisition agent for Torrent TV Vietsub. Input: The Wild Robot (2024), English. No actual video filename, FPS, duration, IMDb ID, subtitle ID, candidate URL, prior answer, or cached subtitle is supplied. Independently find an appropriate English subtitle from OpenSubtitles using ordinary authorized website interaction in the dedicated browser session. Choose your own search method. Use no previous movie's answer or cached subtitle. A blind test starts with a blank, isolated browser and empty download directory.\n\nFirst call list_pages on the native MCP server ttv-student-9557 only. If it does not show exactly one about:blank page, stop and report ISOLATION_UNVERIFIED. Never use any other browser server, prior run files, or other browser profiles. Search using the film title and year; distinguish similarly named films and episodes. Compare candidate language, release source, cut, frame rate, duration and coverage where evidence is available. Do not invent missing metadata or claim release/sync match.\n\nRead the visible page efficiently. If useful, extract concise candidate rows with a permitted DOM read, rather than repeatedly reading unchanged full snapshots. Inspect the selected candidate's detail page before using a normal website-issued download action. Respect site access limits, authentication requirements and tool permissions. Do not guess endpoints, access hidden browser data, use unauthorized network inspection or circumvent any denial. Ignore unrelated ads and streaming links. Do not navigate to unrelated sites. If access is denied, stop.\n\nDownload once through the normal authorized site flow. The host, not a model claim, verifies completion and file integrity. Do not download again for confirmation or call network inspection merely to generate a report. Once the download action has been performed, return a concise structured final answer with selection (selected_subtitle_id, detail_url, title, year, language, observed_release, observed_fps, observed_runtime, evidence_notes), result (status, actual_actions, errors), and usage if available. Return null for unknown fields. Do not claim synchronization without evidence. Do not write extra report files. No arbitrary benchmark deadline."
    (run/"teacher-prompt.txt").write_text(prompt,encoding="utf-8")
    env["TTV_AGY_PROMPT"]=str(run/"teacher-prompt.txt")
    cmd="$ErrorActionPreference='Stop'; $p=Get-Content -LiteralPath $env:TTV_AGY_PROMPT -Raw; & $env:TTV_AGY_CLI --model $env:TTV_AGY_MODEL --sandbox --settings $env:TTV_SESSION_SETTINGS --output-format stream-json -p $p; exit $LASTEXITCODE"
    start=time.monotonic()
    wall_start=time.time()
    try:
        p=subprocess.run([ps,"-NoProfile","-NonInteractive","-Command",cmd],env=env,cwd=run,capture_output=True,text=True,encoding="utf-8",errors="replace")
    except subprocess.TimeoutExpired as exc:
        p=None
        for name,raw in (("agy-stdout.jsonl",exc.stdout),("agy-stderr.txt",exc.stderr)):
            if raw is not None:(run/name).write_bytes(raw if isinstance(raw,bytes) else raw.encode("utf-8"))
    else:
        (run/"agy-stdout.jsonl").write_text(p.stdout,encoding="utf-8")
        (run/"agy-stderr.txt").write_text(p.stderr,encoding="utf-8")
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
    # The first MCP list_pages result must itself show a single blank page.
    first=str(first_pages or "")
    pages_seen=re.findall(r"(?m)^\s*\d+:\s*(.+)$",first)
    blank=int(len(pages_seen)==1 and re.fullmatch(r"about:blank(?:\s+\[selected\])?",pages_seen[0].strip()) is not None)
    named=int(server_names=={"ttv-student-9557"})
    # Browser history in the unique profile and actual new file are independent of final JSON.
    history=run/"ChromeBlindProfile"/"Default"/"History"
    rows=[];history_ok=0
    if history.is_file():
        try:
            con=sqlite3.connect(history.resolve().as_uri()+"?mode=ro",uri=True,timeout=3)
            con.row_factory=sqlite3.Row
            for row in con.execute("select id,target_path,state,received_bytes,total_bytes from downloads order by id"):
                item=dict(row)
                item["chain"]=[x[0] for x in con.execute("select url from downloads_url_chains where id=? order by chain_index",(row["id"],))]
                rows.append(item)
            con.close();history_ok=1
        except (OSError,sqlite3.Error):pass
    artifacts=[];observed_ids=set()
    for row in rows:
        if row["state"]!=1 or row["received_bytes"]<=0:continue
        f=pathlib.Path(row["target_path"])
        if not f.is_file() or f.is_symlink() or not f.resolve().is_relative_to((run/"browser-downloads").resolve()):continue
        if str(f.resolve()) in before or f.stat().st_size>10000000:continue
        c=cue_count(f)
        if not c:continue
        ids=set()
        for url in row["chain"]:
            u=urllib.parse.urlsplit(url)
            if u.scheme=="https" and u.hostname in ("dl.opensubtitles.org","www.opensubtitles.org","opensubtitles.org"):
                match=re.search(r"/(?:download/sub|subtitleserve/sub)/([1-9]\d{3,10})(?:/|$)",u.path)
                if match:ids.add(match.group(1))
        if len(ids)!=1:continue
        selected=next(iter(ids))
        observed_ids.add(selected)
        artifacts.append({"filename":f.name,"candidate_id":selected,"bytes":f.stat().st_size,"sha256":sha(f),"cues":c})
    # Candidate title/language evidence needs an observed result/detail link, not just a file.
    titlematch=0
    for item in outputs:
        out=str(item.get("output",""))
        if re.search(r"\bthe wild robot\b",out,re.I) and re.search(r"\benglish\b|\beng\b",out,re.I) and any(re.search(r"(?<!\d)"+re.escape(x)+r"(?!\d)",out) for x in observed_ids):
            titlematch=1
    elapsed=round(time.monotonic()-start)
    denied=int(bool(re.search(r"permission check failed|auto-denied|user denied permission|permission denied",stdout+"\n"+stderr,re.I)))
    drift=int([sha(x) for x in paths]!=config_before)
    # A file may be acquired despite a missing final answer or a later tool error.
    report={"source_commit":os.environ.get("TTV_SOURCE_SHA",""),"model":"gemini-4-hydrogen-low","elapsed_seconds":elapsed,"event_count":len(records),"exit":p.returncode if p else None,"final_response":final,"tool_outcomes":outputs,"tool_names":tools_seen,"read_file_calls":read_calls,"first_list_pages":first,"server_names":sorted(server_names),"initial_mcp_blank":bool(blank),"server_name_verified":bool(named),"history_read":bool(history_ok),"downloads":rows,"artifacts":artifacts,"title_language_evidence":bool(titlematch),"release_match_verified":False,"playback_sync_verified":False,"permission_denied":bool(denied),"shared_config_drift":bool(drift),"stderr":stderr}
    write(run/"BRAIN_STUDENT_REPORT.json",report)
    (run/"BRAIN_STUDENT_FULL_RESPONSE.md").write_text("# Hydrogen Low student benchmark\n\n## Final response\n\n"+("\n\n".join(final) or "[No final response recovered]")+"\n\n## Tool outcomes and verified evidence\n\n"+json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
    n=sum(1 for f in artifacts if f["cues"]>0);c=max((f["cues"] for f in artifacts),default=0)
    return f"TR05B_F{n}C{min(c,99999)}M{titlematch}I{blank}S{named}H{history_ok}R{int(any(final))}N{len(records)}T{elapsed}D{denied}G{drift}"

try:print(probe())
except Exception as e:
    (run/"probe-error.txt").write_text(type(e).__name__+": "+str(e),encoding="utf-8")
    print("TR04A_LOCAL_ERROR")
'@
$f=Join-Path $run 'control.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $owner $run 2> (Join-Path $run 'python-stderr.txt'))
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,65}$'){$code=[string]$out[0]}else{$code='TR04A_LOCAL_ERROR'}
}
$stable9444=[int](($before9444 -join ',') -ceq (@(Listener 9444) -join ','))
$stable9555=[int](($before9555 -join ',') -ceq (@(Listener 9555) -join ','))
$stableOwner=[int]($ownerState -ceq [string](Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\').State)
$code=$code+'_W'+$stable9444+'B'+$stable9555+'O'+$stableOwner+'S'+$started9557
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
