Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$profile=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest\CDP9555Profile'
$chrome=Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'
function Listeners([int]$port){@(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)}
function Roots {@(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object {$_.CommandLine -and $_.CommandLine -notmatch '--type=' -and $_.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0})}
function Ready {
 $ls=@(Listeners 9555)
 if($ls.Count -eq 0){return $false}
 $ids=@($ls.OwningProcess | Sort-Object -Unique)
 if($ids.Count -ne 1 -or @($ls | Where-Object {$_.LocalAddress -notin @('127.0.0.1','::1')}).Count){throw 'G21_CDP_PORT_IDENTITY_CONFLICT'}
 $r=@(Roots)
 if($r.Count -ne 1 -or $r[0].ProcessId -ne $ids[0] -or $r[0].CommandLine -notmatch '--remote-debugging-port=9555(?:\s|"|$)'){throw 'G21_CDP_PROFILE_CONFLICT'}
 try{$v=Invoke-RestMethod -Uri 'http://127.0.0.1:9555/json/version' -NoProxy -TimeoutSec 3; return ($v.Browser -match '^Chrome/' -and $v.webSocketDebuggerUrl -match '^ws://127\.0\.0\.1:9555/')}catch{return $false}
}
$active=@(Get-CimInstance Win32_Process | Where-Object {$_.ProcessId -ne $PID -and $_.CommandLine -and ($_.Name -match '^agy(?:\.exe)?$' -or ($_.Name -match '^(node|python|pythonw)\.exe$' -and $_.CommandLine -match 'chrome-devtools-mcp|--browser-url=http://127\.0\.0\.1:9555'))})
if($active.Count){throw 'G21_ACTIVE_BROWSER_CONSUMER'}
$pending=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\subtitle-trials\.native-v13\browser.pending'
if(Test-Path -LiteralPath $pending){throw 'G21_EXISTING_G1_BROWSER_CLAIM'}
$before9444=@(Listeners 9444 | ForEach-Object OwningProcess | Sort-Object -Unique) -join ','
if(-not (Ready)){throw 'G21_EXISTING_CDP_NOT_READY'}
$after9444=@(Listeners 9444 | ForEach-Object OwningProcess | Sort-Object -Unique) -join ','
if($before9444 -cne $after9444){throw 'G21_OTHER_CDP_CHANGED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('g21-student-v2-metadata-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop | Out-Null
$env:TTV_PINNED_SOURCE=[string]$rq.source_commit
$env:TTV_READOUT_NONCE=[string]$rq.nonce
$py=@'
import sys,pathlib,os,json,re,subprocess,hashlib,shutil,urllib.request,urllib.parse,time,threading,queue
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
    # New task page, existing dedicated browser; no browsing of unrelated tabs.
    with opener.open("http://127.0.0.1:9555/json/list",timeout=3) as f:tabs=json.load(f)
    site=[t for t in tabs if t.get("type")=="page" and urllib.parse.urlsplit(t.get("url","")).hostname in ("ext.to","www.ext.to")]
    if len(site)>1:return "G21_STUDENT_TASK_TAB_AMBIGUOUS"
    if not site:
        with opener.open(urllib.request.Request("http://127.0.0.1:9555/json/new?https://ext.to/",method="PUT"),timeout=5) as f:target=json.load(f)
    else:target=site[0]
    if not target.get("id"):return "G21_STUDENT_TASK_TAB_UNVERIFIED"
    # Public title metadata only, no release lookup or acquisition.
    prompt="""You are Hydrogen Low, G2.1 Student Recipe V2. Use only the existing ttv-browser MCP 9555 EXT.TO task page to check whether publicly visible catalog title and year metadata for Wicker (2026) is present. Read only title and year; do not collect release rows, seeds, size, filenames, identifiers, download options, links or magnets. No download, add, playback, login, challenge solving, bypass, other sources, shell or private tabs. Stop on access restrictions or ambiguous challenges; no retries. Return compact JSON with status (MATCH_FOUND,NO_MATCH,ACCESS_BLOCKED,TOOL_UNAVAILABLE,UNKNOWN), candidates (title/year only), recipe_codes (LIST_TASK_TAB,QUERY_TITLE_YEAR,STOP_ON_DENIAL,MARK_UNKNOWN_METADATA,FINAL_REPORT), observations (title/year or reason only). Do not guess or continue after final result."""
    (run/"student-prompt.txt").write_text(prompt,encoding="utf-8")
    env["TTV_AGY_PROMPT"]=str(run/"student-prompt.txt")
    cmd="$ErrorActionPreference='Stop'; $p=Get-Content -LiteralPath $env:TTV_AGY_PROMPT -Raw; & $env:TTV_AGY_CLI --model $env:TTV_AGY_MODEL --sandbox --settings $env:TTV_SESSION_SETTINGS --output-format stream-json -p $p; exit $LASTEXITCODE"
    start=time.monotonic()
    events=queue.Queue()
    def reader(pipe):
        try:
            for line in pipe:events.put((time.monotonic(),line))
        finally:events.put((time.monotonic(),None))
    final_time=None; first_mcp=None; last_mcp=None; eof=False
    lines=[]; rc=-1; process_state="TIMEOUT"
    with (run/"agy-stderr.txt").open("w",encoding="utf-8") as ef, (run/"agy-stdout.jsonl").open("w",encoding="utf-8") as rf, (run/"event-arrivals.jsonl").open("w",encoding="utf-8") as tf:
        p=subprocess.Popen([ps,"-NoProfile","-NonInteractive","-Command",cmd],env=env,cwd=run,stdout=subprocess.PIPE,stderr=ef,text=True,encoding="utf-8",errors="replace",bufsize=1)
        threading.Thread(target=reader,args=(p.stdout,),daemon=True).start()
        def ingest(at,line):
            nonlocal final_time,first_mcp,last_mcp,eof
            if line is None:eof=True;return
            lines.append(line);rf.write(line);rf.flush()
            ms=round((at-start)*1000)
            tf.write(json.dumps({"ordinal":len(lines),"elapsed_ms":ms})+"\n");tf.flush()
            try:e=json.loads(line)
            except ValueError:return
            if not isinstance(e,dict):return
            st=e.get("step_update")
            if isinstance(st,dict) and st.get("tool_name")=="call_mcp_tool":
                if first_mcp is None:first_mcp=ms
                last_mcp=ms
            r=e.get("result")
            if final_time is None and e.get("event")=="result" and isinstance(r,dict) and isinstance(r.get("response"),str):
                for m in re.finditer(r"\{",r["response"]):
                    try:v,_=json.JSONDecoder().raw_decode(r["response"][m.start():])
                    except ValueError:continue
                    if isinstance(v,dict) and v.get("status") in ("MATCH_FOUND","NO_MATCH","ACCESS_BLOCKED","TOOL_UNAVAILABLE","UNKNOWN") and isinstance(v.get("candidates"),list) and isinstance(v.get("recipe_codes"),list):
                        final_time=ms;write(run/"BRAIN_RESULT_EARLY.json",v);break
        while True:
            try:ingest(*events.get(timeout=.2))
            except queue.Empty:pass
            if p.poll() is not None and eof:rc=p.returncode;process_state="EXITED";break
            now=time.monotonic()-start
            # Preserve a validated final event; bound only this owned CLI process tree.
            if now>=120 or (final_time is not None and now>=final_time/1000+8):
                process_state="FINAL_EXIT_TIMEOUT" if final_time is not None else "TIMEOUT"
                if p.poll() is None:
                    subprocess.run(["taskkill.exe","/PID",str(p.pid),"/T","/F"],capture_output=True,timeout=10,check=False)
                try:p.wait(timeout=10)
                except subprocess.TimeoutExpired:process_state="CLEANUP_UNVERIFIED"
                while True:
                    try:ingest(*events.get_nowait())
                    except queue.Empty:break
                break
        if process_state=="EXITED" and rc!=0:process_state="CLI_FAILED"
    raw="".join(lines)
    err=(run/"agy-stderr.txt").read_text(encoding="utf-8",errors="replace")
    records=[]
    for line in raw.splitlines():
        try:
            e=json.loads(line)
            if isinstance(e,dict):records.append(e)
        except ValueError:pass
    outcomes=0; answers=[]; errors=0
    for e in records:
        st=e.get("step_update") or {}
        if isinstance(st,dict) and st.get("tool_name")=="call_mcp_tool":
            info=st.get("tool_info") or {}
            if isinstance(info,dict):
                if "output" in info:outcomes+=1
                if info.get("error") or st.get("error"):errors+=1
        result=e.get("result")
        if e.get("event")=="result" and isinstance(result,dict) and isinstance(result.get("response"),str):answers.append(result["response"])
    final={}
    for answer in reversed(answers):
        for m in re.finditer(r"\{",answer):
            try:obj,_=json.JSONDecoder().raw_decode(answer[m.start():])
            except ValueError:continue
            if isinstance(obj,dict) and "status" in obj and isinstance(obj.get("recipe_codes"),list):final=obj;break
        if final:break
    codes={"LIST_TASK_TAB","QUERY_TITLE_YEAR","READ_VISIBLE_RESULTS","FILTER_EXACT_TITLE","RANK_SIZE_SEEDS","READ_DETAIL_IF_NEEDED","STOP_ON_DENIAL","MARK_UNKNOWN_METADATA","FINAL_REPORT"}
    recipe=[x for x in final.get("recipe_codes",[]) if isinstance(x,str) and x in codes][:12]
    status=final.get("status","UNKNOWN")
    if status not in ("MATCH_FOUND","NO_MATCH","ACCESS_BLOCKED","TOOL_UNAVAILABLE","UNKNOWN"):status="UNKNOWN"
    model_status=status
    if not outcomes:status="MCP_UNVERIFIED"
    elif not final:status=process_state if process_state!="EXITED" else "UNKNOWN"
    elif process_state=="CLEANUP_UNVERIFIED":status="CLEANUP_UNVERIFIED"
    if config_before!=[sha(p) for p in paths]:status="CONFIG_CHANGED"
    elapsed=round(time.monotonic()-start,3)
    report={"schema":"G21_BRAIN_STUDENT_V2","model":"gemini-4-hydrogen-low","status":status,"model_status":model_status,"process_state":process_state,"final_ms":final_time,"first_mcp_ms":first_mcp,"last_mcp_ms":last_mcp,"elapsed_seconds":elapsed,"mcp_outcomes":outcomes,"mcp_errors":errors,"candidate_count":len(final.get("candidates",[])) if isinstance(final.get("candidates"),list) else 0,"recipe_codes":recipe,"source_commit":os.environ.get("TTV_PINNED_SOURCE","")}
    write(run/"BRAIN_RESULT.json",{"metrics":report,"model_final":final})
    write(run/"BRAIN_HANDOFF.json",report)
    nonce=os.environ["TTV_READOUT_NONCE"]
    spool=pathlib.Path(os.environ["ProgramData"])/"TorrentTVVietsub"/"LaptopHostOps"/"Receipts"
    write(spool/("g21-student-v2-"+nonce+".json"),report)
    return "G21_STUDENT_"+status+"_P"+process_state+"_M"+str(outcomes)+"_C"+str(report["candidate_count"])+"_F"+str(final_time if final_time is not None else 0)+"_T"+str(round(elapsed*1000))
try: print(probe())
except Exception as e:
    (run/"probe-error.txt").write_text(type(e).__name__+":"+str(e),encoding="utf-8")
    print("G21_STUDENT_LOCAL_ERROR")
'@
$f=Join-Path $run 'student.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $owner $run $profile 2> (Join-Path $run 'python-stderr.txt'))
$code=if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){[string]$out[0]}else{'G21_STUDENT_LOCAL_ERROR'}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
