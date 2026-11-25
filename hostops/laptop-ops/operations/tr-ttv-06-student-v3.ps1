# TR-TTV.10: controlled V4 Student acquisition on OpenSubtitles.
# Never edit shared settings or touch Owner production.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$env:TTV_PINNED_SOURCE=[string]$rq.source_commit
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('tr-ttv-10-ironman2-opensubtitles-v4-'+$rq.nonce)
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
$code='TR10V4_BROWSER_NOT_VERIFIED'
if([string]$hostTask.Settings.ExecutionTimeLimit -ne 'PT0S'){$code='TR04C_TASK_LIMIT'}
else{
 # Recover only the enrolled dedicated profile when its browser is actually absent.
 # Never kill another process, replace the profile, or rotate endpoints.
 if($active9555.Count -eq 0){
  $roots=@(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object {$_.CommandLine -and $_.CommandLine -notmatch '--type=' -and $_.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0})
  $chrome=Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'
  if($roots.Count -ne 0){$code='TR10V4_PROFILE_RUNNING_NO_LISTENER'}
  elseif(-not (Test-Path -LiteralPath $profile -PathType Container) -or -not (Test-Path -LiteralPath $chrome -PathType Leaf)){$code='TR10V4_PROFILE_OR_CHROME_MISSING'}
  else{
   Start-Process -FilePath $chrome -ArgumentList @('--user-data-dir="'+$profile+'"','--remote-debugging-port=9555','--remote-debugging-address=127.0.0.1','--no-first-run','--no-default-browser-check','--new-window','https://www.opensubtitles.org/en')
   $started9555=1
   for($i=0;$i -lt 30;$i++){
    Start-Sleep -Milliseconds 500
    $active9555=@(Listener 9555)
    if($active9555.Count -eq 1){break}
   }
   $code='TR10V4_RESTORE_NO_LISTENER'
  }
 }
 if($active9555.Count -gt 1){$code='TR10V4_LISTENER_AMBIGUOUS'}
 elseif($active9555.Count -eq 1){
  $p=Get-CimInstance Win32_Process -Filter ("ProcessId="+$active9555[0])
  $ls=@(Get-NetTCPConnection -LocalPort 9555 -State Listen -ErrorAction SilentlyContinue)
  if($p -and $p.Name -eq 'chrome.exe' -and $p.CommandLine -and $p.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0 -and $p.CommandLine -match '(?:^|\s|")--remote-debugging-port=9555(?:\s|"|\z)' -and @($ls|Where-Object {$_.LocalAddress -notin @('127.0.0.1','::1')}).Count -eq 0){
   $verified=$true
  }else{$code='TR10V4_LISTENER_IDENTITY_MISMATCH'}
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
    site=[t for t in pages if urllib.parse.urlsplit(t.get("url","")).hostname in ("www.opensubtitles.org","opensubtitles.org")]
    if not site:
        # One ordinary provider homepage only; no navigation away from a challenge.
        req=urllib.request.Request("http://127.0.0.1:9555/json/new?https://www.opensubtitles.org/en",method="PUT")
        with opener.open(req,timeout=5) as f:new=json.load(f)
        for _ in range(20):
            time.sleep(.5)
            with opener.open("http://127.0.0.1:9555/json/list",timeout=3) as f:tabs=json.load(f)
            site=[t for t in tabs if t.get("type")=="page" and t.get("id")==new.get("id") and urllib.parse.urlsplit(t.get("url","")).hostname in ("www.opensubtitles.org","opensubtitles.org")]
            if site:break

    if any(re.search(r"/\.within\.website/|making sure you.re not a bot|captcha|access denied|just a moment|forbidden",t.get("url","")+" "+t.get("title",""),re.I) for t in site):return "TR10V4_ACCESS_BLOCKED_PRE"
    if len(site)!=1:return "TR10V4_TASK_TAB_AMBIGUOUS"
    target=site[0]
    u=urllib.parse.urlsplit(target.get("url",""))
    if u.scheme!="https" or not re.search(r"subtitles",target.get("title",""),re.I):return "TR10V4_TASK_TAB_UNVERIFIED"
    # Keep original browser download preferences unchanged; snapshot known download directory.
    prefs=read(profile/"Default"/"Preferences")
    download=prefs.get("download",{})
    dest=pathlib.Path(os.path.expandvars(download.get("default_directory") or str(home/"Downloads")))
    if not dest.is_absolute() or not dest.is_dir():return "TR10V4_DOWNLOAD_DIR_UNVERIFIED"
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
    prompt="You are the English subtitle acquisition Student for Torrent TV Vietsub, Recipe V4. Owner-supplied exact target release: Iron Man 2 2010 REPACK 1080p BluRay x264-nikt0. Film Iron Man 2 (2010), English. Treat REPACK, BluRay, 1080p, x264 and nikt0 as release evidence, not a generic title-only request. Video FPS, duration, byte size and file extension are unknown. No IMDb ID, subtitle ID, candidate URL, previous answer or cached subtitle is provided. Independently find an appropriate English subtitle using ordinary authorized OpenSubtitles website interaction, choosing your own method. Use only the existing dedicated Chrome CDP 9555 and authorized ttv-browser MCP. First list_pages, use the one existing ordinary OpenSubtitles tab and its numeric pageId. Do not modify other tabs, endpoints, profiles, settings or download preferences. If challenge, denial, login or payment blocks ordinary access, stop and report; never bypass or retry via another route.\n\nChoose the search method yourself. Prefer the exact nikt0 REPACK release, but a different release group is not inherently incompatible. Compare the actual candidate film, language, year and available release, cut and timing metadata. Do not reject a plausible candidate just because exact release or timing evidence is missing. Select the best plausible English candidate for this film and download it once using the ordinary authorized website action, even when compatibility is still unknown, so the host can independently validate it. Do not download a known wrong film, year, language, cut or incompatible timing. If no plausible candidate exists, report NO_PLAUSIBLE_CANDIDATE with the observed reason. Inspect the selected candidate detail; bind the evidence to that candidate and report uncertainty. Use concise visible DOM reads when useful; stop acquisition after the download. Never guess endpoints, inspect hidden data or bypass restrictions. Do not invent video FPS or duration. A downloaded candidate is quarantined for QA, not approved for translation or TV. Playback sync is UNVERIFIED until separately tested.\n\nReturn concise structured result even on failure: status (CANDIDATE_DOWNLOADED, NO_PLAUSIBLE_CANDIDATE, ACCESS_BLOCKED, AUTH_REQUIRED, DOWNLOAD_FAILED, TOOL_UNAVAILABLE or UNKNOWN), observed title/year/language, selected candidate reference discovered this run, exact observed release names or null, candidate FPS/duration or null, video FPS/duration null, compatibility evidence and uncertainties, release_match=EXACT_METADATA or EVIDENCED_COMPATIBLE or UNKNOWN or CONFLICT, playback_sync=UNVERIFIED, actual actions, errors and usage if available. Distinguish site access from no match. No extra report files, no arbitrary benchmark deadline."
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
    # Require evidence of the preflight tab in the first actual MCP output.
    first=str(first_pages or "")
    pages_seen=re.findall(r"(?m)^\s*\d+:\s*(.+)$",first)
    bound=int(sum(bool(re.search(r"https://(?:www\.)?opensubtitles\.org(?:/[^\s)]*)?(?:[)\s]|$)",line,re.I)) for line in pages_seen)==1)
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
    artifacts=[];observed_ids=set()
    for row in rows:
        if row["state"]!=1 or row["received_bytes"]<=0:continue
        f=pathlib.Path(row["target_path"])
        if not f.is_file() or f.is_symlink() or not f.resolve().is_relative_to(dest.resolve()):continue
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
    # Independently inspect new files in the initially empty dedicated download directory.
    # ADS provenance is supplementary when Chrome's live History is unavailable.
    physical=[]
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
            u=urllib.parse.urlsplit(ads.get("HostUrl","").strip("\x00"))
            match=re.search(r"/(?:download/sub|subtitleserve/sub)/([1-9]\d{3,10})(?:/|$)",u.path)
            if u.scheme=="https" and u.hostname in ("dl.opensubtitles.org","www.opensubtitles.org","opensubtitles.org") and match:
                sid=match.group(1);observed_ids.add(sid)
                artifacts.append({"filename":f.name,"candidate_id":sid,"bytes":f.stat().st_size,"sha256":sha(f),"cues":c,"provenance":"Zone.Identifier"})
        except (OSError,ValueError):pass
    # Do not export or copy a prior file. Preserve independently verified new artifacts only.
    for artifact in artifacts:
        src=dest/artifact["filename"]
        if src.is_file() and not src.is_symlink() and sha(src)==artifact["sha256"]:
            shutil.copy2(src,resultdir/src.name)
            artifact["copied_to_job"]=True
    # Candidate title/language evidence needs an observed result/detail link, not just a file.
    titlematch=0
    for item in outputs:
        out=str(item.get("output",""))
        if re.search(r"\biron[ ._-]*man[ ._-]*2\b",out,re.I) and re.search(r"\benglish\b|\beng\b",out,re.I) and any(re.search(r"(?<!\d)"+re.escape(x)+r"(?!\d)",out) for x in observed_ids):
            titlematch=1
    # Capture observed release clues without promoting them to playback-sync proof.
    release_candidates=[]
    for item in outputs:
        out=str(item.get("output",""))
        for line in out.splitlines():
            if re.search(r"iron[ ._-]*man[ ._-]*2\b",line,re.I) and re.search(r"bluray|blu.ray|repack|nikt0",line,re.I):
                release_candidates.append({"event":item["event"],"observed_release_text":line[:2000]})
    # Conservative exact-release evidence: same observed line binds actual downloaded ID and full release.
    exact_re=r"iron[ ._-]*man[ ._-]*2[ ._-]+2010[ ._-]+repack[ ._-]+1080p[ ._-]+blu[ ._-]*ray[ ._-]+x264[ ._-]+nikt0\b"
    exact=int(any(re.search(exact_re,line,re.I) and any(re.search(r"(?<!\d)"+re.escape(x)+r"(?!\d)",line) for x in observed_ids) for item in outputs for line in str(item.get("output","")).splitlines()))
    elapsed=round(time.monotonic()-start)
    denied=int(bool(re.search(r"permission check failed|auto-denied|user denied permission|permission denied",stdout+"\n"+stderr,re.I)))
    drift=int([sha(x) for x in paths]!=config_before)
    # A file may be acquired despite a missing final answer or a later tool error.
    access_evidence="\n".join(str(v.get("output","")) for v in outputs)
    challenge=bool(re.search(r"making sure you.re not a bot|/\.within\.website/|anti.bot challenge|captcha",access_evidence,re.I))
    provider_access="ACCESS_BLOCKED" if challenge else "SITE_TAB_OBSERVED"
    selection_evaluation="NOT_TESTED" if challenge else "RELEASE_METADATA_UNVERIFIED"
    report={"source_commit":os.environ.get("TTV_PINNED_SOURCE",""),"model":"gemini-4-hydrogen-low","provider_access":provider_access,"selection_evaluation":selection_evaluation,"provider":"OpenSubtitles","recipe_version":"V4","elapsed_seconds":elapsed,"event_count":len(records),"exit":p.returncode if p else None,"final_response":final,"tool_outcomes":outputs,"tool_names":tools_seen,"read_file_calls":read_calls,"first_list_pages":first,"server_names":sorted(server_names),"initial_mcp_task_tab":bool(bound),"cold_profile":False,"server_name_verified":bool(named),"history_read":bool(history_ok),"downloads":rows,"artifacts":artifacts,"physical_files":physical,"observed_release_candidates":release_candidates,"video_input":{"title":"Iron Man 2","year":2010,"release":"Iron Man 2 2010 REPACK 1080p BluRay x264-nikt0","release_origin":"OWNER_SUPPLIED","fps":None,"duration":None},"title_language_evidence":bool(titlematch),"exact_release_line_evidence":bool(exact),"release_match_verified":False,"playback_sync_verified":False,"permission_denied":bool(denied),"shared_config_drift":bool(drift),"stderr":stderr}
    write(run/"BRAIN_STUDENT_REPORT.json",report)
    (run/"BRAIN_STUDENT_FULL_RESPONSE.md").write_text("# Hydrogen Low OpenSubtitles Student V4 benchmark\n\n## Final response\n\n"+("\n\n".join(final) or "[No final response recovered]")+"\n\n## Tool outcomes and verified evidence\n\n"+json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
    n=sum(1 for f in artifacts if f["cues"]>0);c=max((f["cues"] for f in artifacts),default=0)
    return f"TR10V4_A{int(challenge)}P{len(physical)}F{n}C{min(c,99999)}M{titlematch}E{exact}I{bound}S{named}H{history_ok}R{int(any(final))}N{len(records)}T{elapsed}D{denied}G{drift}"

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
