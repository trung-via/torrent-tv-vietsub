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
$run=Join-Path $root ('g21-r6-mcp-'+$rq.nonce)
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
    # R6 uses the original Student environment and two public metadata fixtures.
    fixtures=(("BIG_BUCK_BUNNY","Big Buck Bunny","https://studio.blender.org/projects/big-buck-bunny/","Frankie the squirrel"),("SINTEL","Sintel","https://studio.blender.org/projects/sintel/","baby dragon"))
    owned=[];rows=[]
    def norm(v):return re.sub(r"\s+"," ",str(v)).strip().casefold()
    def prompt(f):
        return ('Read-only Student V2 metadata benchmark. Independent task '+f[0]+'. Use ttv-browser MCP 9555 only to list pages, select the exact publisher page '+f[2]+', and read its visible title and synopsis in a compact fresh DOM extraction. Use numeric pageId. Return only JSON {"status":"MATCH_FOUND|ACCESS_BLOCKED|UNKNOWN","title":"...","evidence":"..."}. Evidence must be an exact short phrase from the visible synopsis, not memory. Aim 3-5 calls, correctness first. Do not inspect unrelated tabs, sign in, play, download, extract links, acquire media, or bypass restrictions. Stop on denial. Finish immediately.')
    def decode(s):
        for m in re.finditer(r"\{",s):
            try:v,_=json.JSONDecoder().raw_decode(s[m.start():])
            except ValueError:continue
            if isinstance(v,dict) and v.get("status") in ("MATCH_FOUND","ACCESS_BLOCKED","UNKNOWN"):return v
        return {}
    def launch(label,tasks,persistent):
        d=run/label;d.mkdir()
        cmd="$ErrorActionPreference='Stop'; $p=Get-Content -LiteralPath $env:TTV_AGY_PROMPT -Raw; & $env:TTV_AGY_CLI --model $env:TTV_AGY_MODEL --sandbox --settings $env:TTV_SESSION_SETTINGS --output-format stream-json -p $p; exit $LASTEXITCODE"
        if persistent:cmd="& $env:TTV_AGY_CLI --model $env:TTV_AGY_MODEL --sandbox --settings $env:TTV_SESSION_SETTINGS --print= --input-format stream-json --output-format stream-json; exit $LASTEXITCODE"
        else:
            (d/"prompt.txt").write_text(prompt(tasks[0]),encoding="utf-8")
            env["TTV_AGY_PROMPT"]=str(d/"prompt.txt")
        events=queue.Queue()
        def reader(pipe):
            try:
                for line in pipe:events.put((time.monotonic(),line))
            finally:events.put((time.monotonic(),None))
        start=time.monotonic();state="UNKNOWN";results=[];ids=[]
        with (d/"stderr.txt").open("w",encoding="utf-8") as ef,(d/"stdout.jsonl").open("w",encoding="utf-8") as rf,(d/"arrivals.jsonl").open("w",encoding="utf-8") as tf:
            p=subprocess.Popen([ps,"-NoProfile","-NonInteractive","-Command",cmd],env=env,cwd=run,stdin=subprocess.PIPE if persistent else subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=ef,text=True,encoding="utf-8",errors="replace",bufsize=1)
            threading.Thread(target=reader,args=(p.stdout,),daemon=True).start()
            try:
                for i,f in enumerate(tasks,1):
                    code,title,url,anchor=f
                    sent=time.monotonic() if persistent else start
                    if persistent:
                        p.stdin.write(json.dumps({"event":"user","message":{"content":[{"type":"text","text":prompt(f)}]}})+"\n");p.stdin.flush()
                    first=None;final=None;outs=0;errs=0;answer={};sid=None;fresh=[];allout=[];other=0;denial=False
                    while time.monotonic()-sent<100:
                        try:at,line=events.get(timeout=.2)
                        except queue.Empty:
                            if p.poll() is not None:break
                            continue
                        if line is None:break
                        t=max(0,round((at-sent)*1000));rf.write(line);rf.flush()
                        try:e=json.loads(line)
                        except ValueError:continue
                        if not isinstance(e,dict):continue
                        tf.write(json.dumps({"turn":i,"elapsed_ms":t,"event":e.get("event")})+"\n");tf.flush()
                        st=e.get("step_update")
                        if isinstance(st,dict) and st.get("tool_name"):
                            if st.get("tool_name")!="call_mcp_tool":other+=1;break
                            if first is None:first=t
                            info=st.get("tool_info") or {}
                            if isinstance(info,dict):
                                if info.get("error") or st.get("error"):errs+=1
                                if "output" in info:
                                    outs+=1
                                    out=info["output"]
                                    raw=json.dumps(out,ensure_ascii=True) if not isinstance(out,str) else out
                                    allout.append(raw)
                                    if re.search(r"(?i)\b(?:access denied|verify you are human|403 forbidden|captcha required)\b",raw):denial=True;break
                                    if norm(anchor) in norm(raw):fresh.append(raw)
                        r=e.get("result")
                        if e.get("event")=="result" and isinstance(r,dict):
                            final=t;sid=r.get("conversation_id")
                            resp=r.get("response","")
                            if isinstance(resp,str):answer=decode(resp)
                            break
                    ev=answer.get("evidence");status=answer.get("status","UNKNOWN")
                    titleok=norm(answer.get("title",""))==norm(title)
                    sourceok=any(url in x for x in allout)
                    evok=isinstance(ev,str) and 8<=len(ev)<=180 and any(norm(ev) in norm(x) for x in fresh)
                    passed=status=="MATCH_FOUND" and titleok and sourceok and evok and bool(fresh) and not other and not denial and final is not None
                    row={"mode":label,"fixture":code,"first":first,"final":final,"outcomes":outs,"errors":errs,"status":status,"title":titleok,"source":sourceok,"fresh":evok,"pass":passed,"other_tools":other,"denial":denial}
                    rows.append(row);results.append(row);ids.append(sid if isinstance(sid,str) and sid else None)
                    write(run/"r6-metrics.json",rows)
                    if not passed or (persistent and (not ids[-1] or ids[-1]!=ids[0])):break
                if persistent:
                    try:p.stdin.close()
                    except OSError:pass
                try:state="EXITED" if p.wait(timeout=10)==0 else "CLI_FAILED"
                except subprocess.TimeoutExpired:state="EXIT_TIMEOUT"
            finally:
                if p.poll() is None:
                    subprocess.run(["taskkill.exe","/PID",str(p.pid),"/T","/F"],capture_output=True,timeout=10,check=False)
                    try:p.wait(timeout=10)
                    except subprocess.TimeoutExpired:state="CLEANUP_UNVERIFIED"
        same=bool(len(ids)==2 and all(ids) and ids[0]==ids[1]) if persistent else True
        for r in results:r["process"]=state;r["same"]=same
        return len(results)==len(tasks) and all(r["pass"] for r in results) and state=="EXITED" and same
    ok=False;closed=0
    try:
        for code,title,url,anchor in fixtures:
            with opener.open(urllib.request.Request("http://127.0.0.1:9555/json/new?"+url,method="PUT"),timeout=5) as f:t=json.load(f)
            if not t.get("id"):raise ValueError("FIXTURE_TAB_UNVERIFIED")
            owned.append(t["id"])
        ok=launch("COLD_A",[fixtures[0]],False)
        if ok:ok=launch("COLD_B",[fixtures[1]],False)
        if ok:ok=launch("PERSISTENT",fixtures,True)
    finally:
        for tid in owned:
            try:
                with opener.open("http://127.0.0.1:9555/json/close/"+urllib.parse.quote(tid,safe=""),timeout=3):closed+=1
            except Exception:pass
    unchanged=config_before==[sha(p) for p in paths]
    lines=[]
    for i,r in enumerate(rows,1):
        def pos(x):return str(x) if x is not None else "UNKNOWN"
        lines.append(f"G21_FULL_R2_A{i}=MODE:{r['mode']},FIXTURE:{r['fixture']},STATUS:{r['status']},FIRST_MCP_MS:{pos(r['first'])},FINAL_MS:{pos(r['final'])},OUTCOMES:{r['outcomes']},ERRORS:{r['errors']},TITLE:{int(r['title'])},SOURCE:{int(r['source'])},FRESH:{int(r['fresh'])},PASS:{int(r['pass'])},PROCESS:{r.get('process','UNKNOWN')},SAME:{int(r.get('same',False))}")
    lines.append(f"G21_FULL_R2_SUMMARY=ROWS:{len(rows)},GLOBAL_UNCHANGED:{int(unchanged)},OWNED_TABS_CLOSED:{closed},PASS:{int(ok and unchanged and closed==len(owned))}")
    nonce=os.environ["TTV_READOUT_NONCE"]
    spool=pathlib.Path(os.environ["ProgramData"])/"TorrentTVVietsub"/"LaptopHostOps"/"Receipts"
    write(spool/("g21-full-report-"+nonce+".json"),{"schema":"G21_TRAINING_FULL_REPORT_V1","nonce":nonce,"lines":lines})
    return "G21_R6_MCP_READY" if ok and unchanged and len(rows)==4 and closed==len(owned) else "G21_R6_MCP_HOLD"
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
