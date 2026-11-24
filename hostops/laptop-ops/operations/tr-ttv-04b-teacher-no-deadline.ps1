# TR-TTV.04b: one Owner-approved teacher benchmark, isolated Chrome 9555.
# Never edit shared settings or touch Owner production.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$env:TTV_PINNED_SOURCE=[string]$rq.source_commit
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('tr-ttv-04b-nodeadline-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
function Listener([int]$port){
  @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique)
}
$before9444=@(Listener 9444)
$before9555=@(Listener 9555)
$task=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'
$ownerState=[string]$task.State
$profile=Join-Path $root 'CDP9555Profile'
$active9555=@($before9555)
$started9555=0
$verified=$false
$code='TR04A_9555_NO_LISTENER'
if($active9555.Count -eq 0){
 $chrome=@(
   (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
   (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
 )|Where-Object {Test-Path -LiteralPath $_ -PathType Leaf}|Select-Object -First 1
 if($chrome){
  New-Item -ItemType Directory -Path $profile -Force|Out-Null
  $profileArg='--user-data-dir="'+$profile+'"'
  Start-Process -FilePath $chrome -ArgumentList @($profileArg,'--remote-debugging-port=9555','--remote-debugging-address=127.0.0.1','--no-first-run','about:blank')|Out-Null
  $started9555=1
  for($i=0;$i -lt 20;$i++){
   Start-Sleep -Milliseconds 500
   $active9555=@(Listener 9555)
   if($active9555.Count -gt 0){break}
  }
 }else{$code='TR04A_9555_CHROME_NOT_FOUND'}
}
if($active9555.Count -gt 1){$code='TR04A_9555_MULTIPLE_PID'}
if($active9555.Count -eq 1){
 $p=Get-CimInstance Win32_Process -Filter ("ProcessId="+$active9555[0])
 $listeners=@(Get-NetTCPConnection -LocalPort 9555 -State Listen -ErrorAction SilentlyContinue)
 if(-not $p -or $p.Name -ne 'chrome.exe'){$code='TR04A_9555_NOT_CHROME'}
 elseif(-not $p.CommandLine -or $p.CommandLine -notmatch '(?:^|\s|")--remote-debugging-port=9555(?:\s|"|$)'){$code='TR04A_9555_PORT_FLAG_MISMATCH'}
 elseif($p.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -lt 0){$code='TR04A_9555_PROFILE_MISMATCH'}
 elseif(@($listeners|Where-Object {$_.LocalAddress -notin @('127.0.0.1','::1')}).Count -ne 0){$code='TR04A_9555_NONLOOPBACK'}
 else{$verified=$true}
}
if($verified){
$py=@'
import sys,pathlib,os,json,re,subprocess,hashlib,shutil,urllib.request,urllib.parse,time,zipfile
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
    before=[sha(p) for p in paths]
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
    tools=("list_pages","new_page","select_page","navigate_page","take_snapshot","click","fill","press_key","wait_for","close_page","evaluate_script")
    for k in ("deny","ask"):
        if any(isinstance(v,str) and (v.startswith("mcp(ttv-browser") or v=="mcp(*)") for v in perms.get(k,[])):return "TR04B_EXISTING_RESTRICTION"
    allowed=perms.setdefault("allow",[])
    for tool in tools:
        rule="mcp(ttv-browser/"+tool+")"
        if rule not in allowed:allowed.append(rule)
    # No broad file permission change: exact output files in the isolated run only.
    for name in ("SELECTION.json","RESULT.json","TEACHER_RECIPE.json"):
        rule="write_file("+(run/name).as_posix()+")"
        if rule not in allowed:allowed.append(rule)
    if config.get("agentMode")=="auto":config.pop("agentMode")
    override=run/"session-settings.json"
    write(override,config)
    env["TTV_SESSION_SETTINGS"]=str(override)
    env["TTV_AGY_MODEL"]=_validated_antigravity_alias("gemini-4-neon-high","high")
    # Snapshot metadata only for subtitle-shaped files in the dedicated profile's ordinary download location.
    default=pathlib.Path.home()/"Downloads"
    try:
        prefs=run.parent/"CDP9555Profile"/"Default"/"Preferences"
        pref=json.loads(prefs.read_text(encoding="utf-8"))
        d=pathlib.Path(pref.get("download",{}).get("default_directory",str(default)))
        if d.is_absolute() and d.is_dir():default=d
    except Exception:pass
    dirs={default,pathlib.Path.home()/"Downloads"}
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER,r"Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders") as k:
            d=pathlib.Path(os.path.expandvars(winreg.QueryValueEx(k,"{374DE290-123F-4565-9164-39C4925E467B}")[0]))
            if d.is_absolute() and d.is_dir():dirs.add(d)
    except OSError:pass
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
    prompt="Teacher benchmark, Spider-Man: Brand New Day (2026), IMDb tt22084616, WEB-DL 1080p seleZen, expected 23.976 fps and approx 145 min. No subtitle ID supplied. Use only native MCP server ttv-browser configured for the dedicated Chrome 9555; never call wake-browser or any other browser server, shell-based browser helper, or access ChatGPT tabs or 9444. If ttv-browser is unavailable or denied, stop with CDP_FAILED and explain the exact error. Create one own tab, identify its page id and use that id for all page tools; close only your own tab. Use evaluate_script only to read the rendered DOM of your own OpenSubtitles tab (visible title, text, release metadata and website-issued link). Never use it to send requests, access cookies, tokens, browser storage, hidden credentials, other tabs, or bypass site restrictions. Find English subtitle via ordinary OpenSubtitles.org browsing, inspect actual candidate detail for title/year/language/source/cut/fps/runtime and select compatible evidence. If the evidence does not establish a compatible release, stop NO_MATCH. Do not invent a release or metadata. No hard-coded subtitle ID. Before clicking save SELECTION.json with selected_subtitle_id, detail_url, title exactly Spider-Man: Brand New Day, year 2026, language English, release_match boolean (metadata only), actual_test, observed_release, observed_fps, observed_runtime, evidence_notes. Follow actual website-issued dl.opensubtitles.org download link, once only. No direct API/HTTP, guessed URL, credentials, or bypass. Stop on login, CAPTCHA, denial, 401/403/429/payment. Save RESULT.json with status (DOWNLOADED, ACCESS_DENIED, AUTH_REQUIRED, NO_MATCH, DOWNLOAD_FAILED, CDP_FAILED, OTHER), stage, observed_http_status, download_host, selected_subtitle_id, release_match, downloaded_filename, actual_test; save TEACHER_RECIPE.json with actual native MCP tools, reproducible search/selection steps, decision rules, errors and timing, no answer ID in reusable steps. Use normal authorized tools and keep sandbox. For the JSON files use only the normal file-writing tool, only the three named paths inside your working directory. If denied, stop, do not try another tool. Return a final answer including status, observed evidence, actual tool calls and outcomes, timing, errors, and the reusable recipe. Do not include private page contents, tokens or credentials. Do not change MCP settings. No translation or production changes. Report honestly."
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
    results=[x.get("result") for x in records if x.get("event")=="result"]
    result=results[0] if len(results)==1 and isinstance(results[0],dict) else {}
    rr={}
    try:
        rr=json.loads((run/"RESULT.json").read_text(encoding="utf-8-sig"))
        if not isinstance(rr,dict):rr={}
    except Exception:pass
    allowed={"DOWNLOADED","ACCESS_DENIED","AUTH_REQUIRED","NO_MATCH","DOWNLOAD_FAILED","CDP_FAILED","OTHER"}
    status=rr.get("status","")
    if not isinstance(status,str) or status not in allowed:status="UNCLASSIFIED"
    # Compact fixed labels to stay within the existing receipt length limit.
    codes={"DOWNLOADED":"DL","ACCESS_DENIED":"DENY","AUTH_REQUIRED":"AUTH","NO_MATCH":"NOMATCH","DOWNLOAD_FAILED":"DLFAIL","CDP_FAILED":"CDPFAIL","OTHER":"OTHER","UNCLASSIFIED":"UNK"}
    stage=rr.get("stage")
    stage=stage if stage in ("HOME","SEARCH","DETAIL","DOWNLOAD","CDP") else "NA"
    http=str(rr.get("observed_http_status"))
    http=http if http in ("200","401","403","429","503","404","302") else "NA"
    host=rr.get("download_host")
    dlhost=int(isinstance(host,str) and host.lower()=="dl.opensubtitles.org")
    match=int(rr.get("release_match") is True)
    # Dynamic selection, never default to a previous movie's subtitle ID.
    reported_status=status
    selection={}
    try:
        selection=json.loads((run/"SELECTION.json").read_text(encoding="utf-8-sig"))
        if not isinstance(selection,dict):selection={}
    except (OSError,ValueError):pass
    selected_id=str(selection.get("selected_subtitle_id") or rr.get("selected_subtitle_id") or "")
    detail=urllib.parse.urlsplit(str(selection.get("detail_url","")))
    detail_match=bool(re.fullmatch(r"[1-9]\d{3,10}",selected_id) and detail.scheme=="https" and detail.hostname in ("www.opensubtitles.org","opensubtitles.org") and re.match(r"/en/subtitles/"+re.escape(selected_id)+r"(?:/|$)",detail.path))
    film_match=bool(str(selection.get("title","")).strip().casefold()=="spider-man: brand new day" and str(selection.get("year"))=="2026" and str(selection.get("language","")).casefold() in ("english","en","eng"))
    selection_match=bool(detail_match and film_match and selection.get("release_match") is True)
    match=int(selection_match)
    selected_at=-1
    if selection_match:
        selected_at=max(0,round((run/"SELECTION.json").stat().st_mtime-wall_start))
    after=candidates()
    blocked=status in ("ACCESS_DENIED","AUTH_REQUIRED") or http in ("401","403","429")
    f,cues=verify_new_download(before,after,selected_id) if selection_match and not blocked else (None,0)
    files=0; acquired_at=-1
    if f is not None:
        shutil.copyfile(f,downloads/f.name)
        if cue_count(downloads/f.name)==cues:
            files=1;status="DOWNLOADED";stage="DOWNLOAD";dlhost=1
            acquired_at=max(0,round(f.stat().st_mtime-wall_start))
    if not files:
        cues=0
        if status=="DOWNLOADED":status="DOWNLOAD_FAILED"
    (run/"verified-acquisition.json").write_text(json.dumps({"reported_status":reported_status,"verified_status":status,"candidate_id":selected_id,"selection_seconds":selected_at,"file_mtime_seconds":acquired_at,"files":files,"cues":cues,"source_verified":bool(files),"playback_sync_verified":False,"cli_timed_out":p is None}),encoding="utf-8")
    elapsed=round(time.monotonic()-start)
    recipe=read(run/"TEACHER_RECIPE.json") if (run/"TEACHER_RECIPE.json").is_file() else {}
    # Preserve the final and tool-output record locally; omit reasoning and private browser payloads from public receipts.
    excluded={"prompt","input","arguments","thinking","reasoning","thought","signature","instructions","system","user","env","credentials"}
    def walk(v,trail=()):
        if isinstance(v,dict):
            for k,x in v.items():
                if k.lower() not in excluded:yield from walk(x,trail+(k,))
        elif isinstance(v,list):
            for i,x in enumerate(v):yield from walk(x,trail+(str(i),))
        elif isinstance(v,str):yield trail,v
    final=[]
    tool_evidence=[]
    for i,event in enumerate(records):
        kind=event.get("event",event.get("type",""))
        for trail,v in walk(event):
            last=re.sub(r"[^a-z0-9]","",(trail[-1] if trail else "").lower())
            if kind=="result" and last in {"text","response","final","finalresponse","message","output","content","result"}:final.append(v)
            if kind=="step_update" and last in {"name","tool","toolname","title","status","type","error","output","result","tooloutput","toolresult","text","message"} and re.search(r"ttv.browser|list_pages|new_page|navigate_page|take_snapshot|click|download|permission|timeout",v,re.I):tool_evidence.append({"event":i,"field":trail,"value":v})
    report={"source_commit":os.environ.get("TTV_SOURCE_SHA",""),"model":"gemini-4-neon-high","elapsed_seconds":elapsed,"exit":p.returncode if p else None,"final_response":final,"tool_evidence":tool_evidence,"stderr":stderr,"selection":selection,"reported_result":rr,"teacher_recipe":recipe,"verified_acquisition":read(run/"verified-acquisition.json"),"event_count":len(records)}
    write(run/"BRAIN_TEACHER_REPORT.json",report)
    (run/"BRAIN_TEACHER_FULL_RESPONSE.md").write_text("# Teacher benchmark TR-TTV.04b\n\n## Final response\n"+("\n\n".join(final) or "[No final response recovered]")+"\n\n## Tool evidence and result\n\n"+json.dumps({k:v for k,v in report.items() if k!="final_response"},ensure_ascii=False,indent=2),encoding="utf-8")
    drift=int([sha(x) for x in paths]!=before)
    errtext=stdout+"\n"+stderr
    if re.search(r"permission check failed|auto-denied|user denied permission|permission denied",errtext,re.I):status="CDP_FAILED"
    # A physical file proves acquisition only, not exact playback sync or full recipe quality.
    return f"TR04T_{codes[status]}_M{match}F{files}C{min(cues,99999)}R{int(bool(recipe))}N{min(len(records),999)}T{elapsed}X{int(p is None)}G{drift}"

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
$stable9555=[int](($active9555 -join ',') -ceq (@(Listener 9555) -join ','))
$stableOwner=[int]($ownerState -ceq [string](Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\').State)
$code=$code+'_W'+$stable9444+'B'+$stable9555+'O'+$stableOwner+'S'+$started9555
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
