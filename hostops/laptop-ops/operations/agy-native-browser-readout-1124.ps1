# TR-TTV.04a: Owner-approved, isolated Chrome 9555 environment repair/probe.
# Do not edit global settings, touch production, or access a website.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('tr-ttv-04a-smoke2-'+$rq.nonce)
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
import sys,pathlib,os,json,re,subprocess,hashlib,shutil,urllib.request
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
    # Grant only the read-only smoke tool in this session.
    allowed=perms.setdefault("allow",[])
    if "mcp(ttv-browser/list_pages)" not in allowed:allowed.append("mcp(ttv-browser/list_pages)")
    if config.get("agentMode")=="auto":config.pop("agentMode")
    override=run/"session-settings.json"
    write(override,config)
    # Avoid retaining unrelated configuration outside the private run; never upload.
    env["TTV_SESSION_SETTINGS"]=str(override)
    env["TTV_AGY_MODEL"]=_validated_antigravity_alias("gemini-4-neon-high","high")
    prompt="Owner-authorized isolated environment smoke. Call only native MCP ttv-browser/list_pages once, using Chrome 9555. Do not call other tools, navigate, download, read any page, modify settings, or access Chrome 9444. Report exact tool result status only, or stop if denied."
    env["TTV_AGY_SMOKE_PROMPT"]=prompt
    cmd="& $env:TTV_AGY_CLI --model $env:TTV_AGY_MODEL --sandbox --settings $env:TTV_SESSION_SETTINGS --print-timeout 120s --output-format stream-json -p $env:TTV_AGY_SMOKE_PROMPT; exit $LASTEXITCODE"
    try:
        p=subprocess.run([ps,"-NoProfile","-NonInteractive","-Command",cmd],env=env,cwd=run,capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=145)
    except subprocess.TimeoutExpired:return "TR04A_SMOKE_TIMEOUT"
    finally:
        # The full copied settings can contain unrelated private data; remove only our copy.
        override.unlink(missing_ok=True)
    (run/"agy-stdout.jsonl").write_text(p.stdout,encoding="utf-8")
    (run/"agy-stderr.txt").write_text(p.stderr,encoding="utf-8")
    if [sha(x) for x in paths]!=before:return "TR04A_GLOBAL_CONFIG_DRIFT"
    raw=p.stdout+"\n"+p.stderr
    if "non-absolute file path" in raw:return "TR04A_SANDBOX_STILL_FAIL"
    if re.search(r"permission check failed|auto-denied|user denied permission",raw,re.I):return "TR04A_MCP_STILL_DENIED"
    if "not available for this account" in raw:return "TR04A_AUTO_STILL_ACTIVE"
    # Only structured tool metadata may establish tool execution; never model prose.
    events=[]
    for line in p.stdout.splitlines():
        try:
            e=json.loads(line)
            if isinstance(e,dict):events.append(e)
        except ValueError:pass
    def nodes(v):
        if isinstance(v,dict):
            yield v
            for k,x in v.items():
                if k.lower() not in ("prompt","input","arguments","thinking","reasoning","thought","instructions","message","text","content"):yield from nodes(x)
        elif isinstance(v,list):
            for x in v:yield from nodes(x)
    def token(s):return re.sub(r"[^a-z0-9]","",s.lower()) if isinstance(s,str) else ""
    target={"ttvbrowsertlistpages","ttvbrowserlistpages","mcpttvbrowserlistpages"}
    seen=0;verified=0
    for e in events:
        for n in nodes(e):
            names=[token(n.get(k)) for k in ("name","tool","tool_name","toolName","functionName")]
            server=token(n.get("server",n.get("serverName","")))
            matched=any(v in target for v in names) or (server=="ttvbrowser" and "listpages" in names)
            if not matched:continue
            seen+=1
            types={token(n.get(k)) for k in ("event","type","kind","status","state","phase")}
            is_result=bool(types & {"toolresult","toolresponse","mcpresult","toolcompleted","completed","success","succeeded"})
            explicit_success=n.get("ok") is True or n.get("success") is True or bool(types & {"success","succeeded"}) or (n.get("isError") is False and ("result" in n or "output" in n))
            if is_result and explicit_success and not n.get("error") and n.get("isError") is not True:verified+=1
    timeout=int(bool(re.search(r"print.timeout|response timeout|deadline exceeded|timed out",raw,re.I)))
    write(run/"smoke-summary.json",{"exit":p.returncode,"event_types":[e.get("event",e.get("type","")) for e in events],"global_config_unchanged":True,"auto_flag_removed":True,"tool_metadata_matches":seen,"structured_success":verified,"timeout_text":bool(timeout)})
    return "TR04B_E%d_N%d_M%d_V%d_T%d"%(max(0,min(255,p.returncode)),min(len(events),99),min(seen,99),min(verified,99),timeout)

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
