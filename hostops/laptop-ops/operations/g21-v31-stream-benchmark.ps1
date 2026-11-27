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
$run=Join-Path $root ('g21-v31-stream-'+$rq.nonce)
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
    # Real official publisher metadata; no download or play.
    url="https://www.sunpictures.in/?sunpict_movies=jailer2"
    with opener.open("http://127.0.0.1:9555/json/list",timeout=3) as f:tabs=json.load(f)
    site=[t for t in tabs if t.get("type")=="page" and t.get("url","").split("#")[0]==url]
    if len(site)>1:return "G21_V31_TASK_TAB_AMBIGUOUS"
    if not site:
        with opener.open(urllib.request.Request("http://127.0.0.1:9555/json/new?"+url,method="PUT"),timeout=5) as f:target=json.load(f)
    else:target=site[0]
    if not target.get("id"):return "G21_V31_TASK_TAB_UNVERIFIED"
    if "--input-format" not in helptext or "stream-json" not in helptext:return "G21_V31_STREAM_UNDOCUMENTED"
    prompt="""Read-only benchmark for Jailer 2 on official Sun Pictures public page https://www.sunpictures.in/?sunpict_movies=jailer2 only, via ttv-browser MCP 9555. List pages, select exact publisher page, read visible film title and one credited person using compact DOM extraction. Do not visit unrelated tabs, sign in, play, download, or bypass restrictions. Stop if blocked. Return only JSON {"status":"MATCH_FOUND|ACCESS_BLOCKED|UNKNOWN","title":"...","credited_person":"..."}. Use actual visible evidence, unknown fields null. Finish turn immediately."""
    warm_prompt="New independent measurement: repeat the exact preceding task using current visible page evidence and at least one fresh MCP read. Do not use remembered page content as evidence. Same output JSON. Finish immediately."
    cmd="& $env:TTV_AGY_CLI --model $env:TTV_AGY_MODEL --sandbox --settings $env:TTV_SESSION_SETTINGS --print= --input-format stream-json --output-format stream-json; exit $LASTEXITCODE"
    import queue,threading
    q=queue.Queue()
    def reader(pipe):
        try:
            for line in pipe:q.put((time.monotonic(),line))
        finally:q.put((time.monotonic(),None))
    report=[];state="UNKNOWN";proc_start=time.monotonic();session_ids=[]
    with (run/"agy-stderr.txt").open("w",encoding="utf-8") as ef,(run/"agy-stdout.jsonl").open("w",encoding="utf-8") as rf,(run/"event-arrivals.jsonl").open("w",encoding="utf-8") as tf:
        p=subprocess.Popen([ps,"-NoProfile","-NonInteractive","-Command",cmd],env=env,cwd=run,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=ef,text=True,encoding="utf-8",errors="replace",bufsize=1)
        threading.Thread(target=reader,args=(p.stdout,),daemon=True).start()
        try:
            for i,question in enumerate((prompt,warm_prompt),1):
                sent=time.monotonic();first=None;last=None;calls=0;errors=0;answer={};sid=None;final_ms=None;usage={}
                message={"event":"user","message":{"content":[{"type":"text","text":question}]}}
                p.stdin.write(json.dumps(message)+"\n");p.stdin.flush()
                while time.monotonic()-sent<110:
                    try:at,line=q.get(timeout=.2)
                    except queue.Empty:
                        if p.poll() is not None:break
                        continue
                    if line is None:break
                    ms=max(0,round((at-sent)*1000));rf.write(line);rf.flush()
                    try:e=json.loads(line)
                    except ValueError:continue
                    if not isinstance(e,dict):continue
                    typ=e.get("event")
                    tf.write(json.dumps({"turn":i,"elapsed_ms":ms,"event":typ})+"\n");tf.flush()
                    st=e.get("step_update")
                    if isinstance(st,dict) and st.get("tool_name")=="call_mcp_tool":
                        if first is None:first=ms
                        last=ms
                        info=st.get("tool_info")
                        if isinstance(info,dict) and ("output" in info or info.get("error")):
                            calls+=1;errors+=int(bool(info.get("error") or st.get("error")))
                    r=e.get("result")
                    if typ=="result" and isinstance(r,dict):
                        final_ms=ms;sid=r.get("conversation_id")
                        usage=r.get("usage",{}) if isinstance(r.get("usage"),dict) else {}
                        resp=r.get("response","")
                        if isinstance(resp,str):
                            for m in re.finditer(r"\{",resp):
                                try:v,_=json.JSONDecoder().raw_decode(resp[m.start():])
                                except ValueError:continue
                                if isinstance(v,dict) and v.get("status") in ("MATCH_FOUND","ACCESS_BLOCKED","UNKNOWN"):
                                    answer=v;break
                        break
                status=answer.get("status","UNKNOWN")
                title=answer.get("title")
                exact=isinstance(title,str) and bool(re.search(r"\bjailer\s*(?:2|two)\b",title,re.I))
                credited=isinstance(answer.get("credited_person"),str) and bool(answer["credited_person"].strip())
                row={"turn":i,"first_ms":first,"last_ms":last,"final_ms":final_ms,"calls":calls,"errors":errors,"status":status,"title_match":exact,"credited_person_reported":credited,"usage":{k:v for k,v in usage.items() if k in ("input_tokens","output_tokens","thinking_tokens","cache_read_tokens","total_tokens") and type(v) is int},"pid":p.pid}
                report.append(row);session_ids.append(sid if isinstance(sid,str) else None)
                write(run/"BRAIN_RESULT.json",{"turns":report,"same_process":True,"conversation_id_match":len(session_ids)==2 and bool(session_ids[0]) and session_ids[0]==session_ids[1]})
                if status!="MATCH_FOUND" or not exact or calls<1 or final_ms is None:break
            try:p.stdin.close()
            except OSError:pass
            try:rc=p.wait(timeout=10);state="EXITED" if rc==0 else "CLI_FAILED"
            except subprocess.TimeoutExpired:state="EXIT_TIMEOUT"
        finally:
            if p.poll() is None:
                subprocess.run(["taskkill.exe","/PID",str(p.pid),"/T","/F"],capture_output=True,timeout=10,check=False)
                try:p.wait(timeout=10)
                except subprocess.TimeoutExpired:state="CLEANUP_UNVERIFIED"
    if config_before!=[sha(p) for p in paths]:return "G21_V31_CONFIG_CHANGED"
    same=len(session_ids)==2 and bool(session_ids[0]) and session_ids[0]==session_ids[1]
    write(run/"BRAIN_HANDOFF.json",{"turns":report,"process_state":state,"same_process":True,"conversation_id_match":same})
    if len(report)!=2:return "G21_V31_COLD_HOLD_"+report[0]["status"]+"_M"+str(report[0]["calls"])+"_T"+str(report[0]["final_ms"] or 0)
    a,b=report
    if b["status"]!="MATCH_FOUND" or not b["title_match"] or b["calls"]<1 or b["final_ms"] is None:return "G21_V31_WARM_HOLD_"+b["status"]+"_M"+str(b["calls"])
    return "G21_V31_STREAM_C"+str(a["first_ms"] or 0)+"T"+str(a["final_ms"] or 0)+"M"+str(a["calls"])+"_W"+str(b["first_ms"] or 0)+"T"+str(b["final_ms"] or 0)+"M"+str(b["calls"])+"_S"+str(int(same))+"_P"+state

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
