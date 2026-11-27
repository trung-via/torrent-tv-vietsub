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
$before9444=@(Listeners 9444 | ForEach-Object OwningProcess | Sort-Object -Unique) -join ','
$action='REUSED'
if(-not (Ready)){
 if(-not (Test-Path -LiteralPath $profile -PathType Container) -or -not (Test-Path -LiteralPath $chrome -PathType Leaf)){throw 'G21_EXISTING_PROFILE_OR_CHROME_MISSING'}
 $r=@(Roots)
 if($r.Count -gt 1){throw 'G21_PROFILE_NOT_UNIQUE'}
 if($r.Count -eq 1){
  $busy=@(Get-CimInstance Win32_Process | Where-Object {$_.ProcessId -ne $PID -and $_.CommandLine -and ($_.Name -match '^agy(?:\.exe)?$' -or ($_.Name -match '^(node|python|pythonw)\.exe$' -and $_.CommandLine -match 'chrome-devtools-mcp|--browser-url=http://127\.0\.0\.1:9555'))})
  if($busy.Count){throw 'G21_ACTIVE_BROWSER_CONSUMER'}
  $proc=Get-Process -Id $r[0].ProcessId -ErrorAction Stop
  if(-not $proc.CloseMainWindow()){throw 'G21_GRACEFUL_CLOSE_UNAVAILABLE'}
  if(-not $proc.WaitForExit(10000)){throw 'G21_GRACEFUL_CLOSE_TIMEOUT'}
  $action='RESTARTED'
 }else{$action='STARTED'}
 if(@(Listeners 9555).Count -ne 0 -or @(Roots).Count -ne 0){throw 'G21_RECOVERY_PRECONDITION_CHANGED'}
 Start-Process -FilePath $chrome -ArgumentList @('--user-data-dir="'+$profile+'"','--remote-debugging-port=9555','--remote-debugging-address=127.0.0.1','--no-first-run','--no-default-browser-check','--new-window','about:blank')
 $ok=$false
 for($i=0;$i -lt 20;$i++){Start-Sleep -Milliseconds 500;if(Ready){$ok=$true;break}}
 if(-not $ok){throw 'G21_CDP_RECOVERY_NOT_READY'}
}
if(-not (Ready)){throw 'G21_CDP_FINAL_NOT_READY'}
$after9444=@(Listeners 9444 | ForEach-Object OwningProcess | Sort-Object -Unique) -join ','
if($before9444 -cne $after9444){throw 'G21_OTHER_CDP_CHANGED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('g21-v31-resume-'+$rq.nonce)
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
    # Public publisher metadata only; dedicated task tab.
    url="https://www.primevideo.com/detail/0M0MP41XNWVO29LL977I63Z58J"
    with opener.open("http://127.0.0.1:9555/json/list",timeout=3) as f:tabs=json.load(f)
    site=[t for t in tabs if t.get("type")=="page" and t.get("url","").split("?")[0]==url]
    if len(site)>1:return "G21_V31_TASK_TAB_AMBIGUOUS"
    if not site:
        with opener.open(urllib.request.Request("http://127.0.0.1:9555/json/new?"+url,method="PUT"),timeout=5) as f:target=json.load(f)
    else:target=site[0]
    if not target.get("id"):return "G21_V31_TASK_TAB_UNVERIFIED"
    # Require explicit session argument. Never resume a global most-recent chat.
    resume_help=next((line for line in helptext.splitlines() if re.search(r"--resume(?:\s|=)",line)), "")
    explicit=bool(re.search(r"--resume(?:\s+|=)(?:[<\[][^>\]]+[>\]]|(?:SESSION|ID|session|id)\b)",resume_help))
    if not explicit:return "G21_V31_EXPLICIT_RESUME_UNDOCUMENTED"
    prompt="""Read-only public metadata benchmark for Jailer 2 (2026). Use only ttv-browser MCP 9555 and the Prime Video public detail page with ID 0M0MP41XNWVO29LL977I63Z58J. List pages, select that page, and read visible title, year and runtime using a compact DOM read. Do not sign in, play, download, add, open other tabs or bypass any restriction. Stop if blocked. Return only compact JSON {"status":"MATCH_FOUND|ACCESS_BLOCKED|UNKNOWN","title":"...","year":2026,"runtime":"..."} with unknown fields null. For every request, read current page; do not rely on conversation history. End immediately."""
    (run/"student-prompt.txt").write_text(prompt,encoding="utf-8")
    env["TTV_AGY_PROMPT"]=str(run/"student-prompt.txt")
    def phase(label,sid=None):
        import queue,threading
        env2=dict(env)
        cmd="$ErrorActionPreference='Stop'; $p=Get-Content -LiteralPath $env:TTV_AGY_PROMPT -Raw; & $env:TTV_AGY_CLI --model $env:TTV_AGY_MODEL --sandbox --settings $env:TTV_SESSION_SETTINGS --output-format stream-json"
        if sid:
            env2["TTV_RESUME_SESSION"]=sid
            cmd+=" --resume $env:TTV_RESUME_SESSION"
        cmd+=" -p $p; exit $LASTEXITCODE"
        start=time.monotonic();q=queue.Queue()
        first=None;last=None;final_ms=None;session=None;outcomes=0;errors=0;answer={};eof=False;state="TIMEOUT";rc=None
        def reader(pipe):
            try:
                for line in pipe:q.put((time.monotonic(),line))
            finally:q.put((time.monotonic(),None))
        with (run/(label+"-stderr.txt")).open("w",encoding="utf-8") as ef,(run/(label+"-stdout.jsonl")).open("w",encoding="utf-8") as rf,(run/(label+"-timing.jsonl")).open("w",encoding="utf-8") as tf:
            p=subprocess.Popen([ps,"-NoProfile","-NonInteractive","-Command",cmd],env=env2,cwd=run,stdout=subprocess.PIPE,stderr=ef,text=True,encoding="utf-8",errors="replace",bufsize=1)
            threading.Thread(target=reader,args=(p.stdout,),daemon=True).start()
            def ingest(at,line):
                nonlocal first,last,final_ms,session,outcomes,errors,answer,eof
                if line is None:eof=True;return
                ms=round((at-start)*1000);rf.write(line);rf.flush()
                try:e=json.loads(line)
                except ValueError:return
                if not isinstance(e,dict):return
                tf.write(json.dumps({"ms":ms,"event":str(e.get("event",""))[:40]})+"\n");tf.flush()
                # Bind only session IDs emitted in structured lifecycle events.
                if e.get("event") in ("init","session_start","session","result"):
                    for obj in (e,e.get("init"),e.get("session"),e.get("result")):
                        if not isinstance(obj,dict):continue
                        for k in ("session_id","sessionId"):
                            v=obj.get(k)
                            if isinstance(v,str) and re.fullmatch(r"[A-Za-z0-9_-]{8,128}",v):session=v
                st=e.get("step_update")
                if isinstance(st,dict) and st.get("tool_name")=="call_mcp_tool":
                    if first is None:first=ms
                    last=ms
                    info=st.get("tool_info")
                    if isinstance(info,dict) and ("output" in info or info.get("error")):
                        outcomes+=1;errors+=int(bool(info.get("error") or st.get("error")))
                r=e.get("result")
                if e.get("event")=="result" and isinstance(r,dict) and isinstance(r.get("response"),str):
                    for m in re.finditer(r"\{",r["response"]):
                        try:v,_=json.JSONDecoder().raw_decode(r["response"][m.start():])
                        except ValueError:continue
                        if isinstance(v,dict) and v.get("status") in ("MATCH_FOUND","ACCESS_BLOCKED","UNKNOWN"):
                            answer=v;final_ms=ms;write(run/(label+"-result.json"),v);break
            while True:
                try:ingest(*q.get(timeout=.2))
                except queue.Empty:pass
                if p.poll() is not None and eof:
                    rc=p.returncode;state="EXITED" if rc==0 else "CLI_FAILED";break
                now=time.monotonic()-start
                if now>=110 or (final_ms is not None and now>=final_ms/1000+8):
                    state="FINAL_EXIT_TIMEOUT" if final_ms is not None else "TIMEOUT"
                    if p.poll() is None:subprocess.run(["taskkill.exe","/PID",str(p.pid),"/T","/F"],capture_output=True,timeout=10,check=False)
                    try:p.wait(timeout=10)
                    except subprocess.TimeoutExpired:state="CLEANUP_UNVERIFIED"
                    while True:
                        try:ingest(*q.get_nowait())
                        except queue.Empty:break
                    break
        total=round((time.monotonic()-start)*1000)
        title=answer.get("title");year=answer.get("year");runtime=answer.get("runtime")
        status=answer.get("status","UNKNOWN")
        exact=isinstance(title,str) and bool(re.fullmatch(r"\s*Jailer\s*2\s*",title,re.I)) and str(year)=="2026"
        report={"state":state,"status":status,"exact":exact,"runtime_reported":isinstance(runtime,str) and bool(runtime),"first_ms":first,"last_ms":last,"final_ms":final_ms,"total_ms":total,"outcomes":outcomes,"errors":errors,"session_present":bool(session),"session_matches":bool(sid and session==sid)}
        write(run/(label+"-metrics.json"),report)
        return report,session
    cold,sid=phase("cold")
    if cold["state"]!="EXITED" or cold["status"]!="MATCH_FOUND" or not cold["exact"] or cold["outcomes"]<1:
        return "G21_V31_COLD_HOLD_"+cold["state"]+"_"+cold["status"]
    if not sid:return "G21_V31_SESSION_ID_MISSING_F"+str(cold["first_ms"] or 0)+"_T"+str(cold["total_ms"])
    warm,returned=phase("resume",sid)
    if config_before!=[sha(p) for p in paths]:return "G21_V31_CONFIG_CHANGED"
    write(run/"BRAIN_RESULT.json",{"cold":cold,"resume":warm})
    if warm["state"]!="EXITED" or warm["status"]!="MATCH_FOUND" or not warm["exact"] or warm["outcomes"]<1:
        return "G21_V31_RESUME_HOLD_"+warm["state"]+"_"+warm["status"]
    return "G21_V31_C"+str(cold["first_ms"] or 0)+"T"+str(cold["total_ms"])+"M"+str(cold["outcomes"])+"_R"+str(warm["first_ms"] or 0)+"T"+str(warm["total_ms"])+"M"+str(warm["outcomes"])+"_S"+str(int(warm["session_matches"]))

try: print(probe())
except Exception as e:
    (run/"probe-error.txt").write_text(type(e).__name__+":"+str(e),encoding="utf-8")
    print("G21_V31_LOCAL_ERROR")
'@
$f=Join-Path $run 'student.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $owner $run $profile 2> (Join-Path $run 'python-stderr.txt'))
$code=if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){[string]$out[0]}else{'G21_V31_LOCAL_ERROR'}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
