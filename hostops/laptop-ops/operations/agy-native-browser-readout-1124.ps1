# AGY acquisition using the independently validated stdio MCP client and explicit pageId.
# Keep the existing profile and normal website authorization intact.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('agy-path-audit-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='CDP9555_NOT_READY'
$profile=Join-Path $root 'CDP9555Profile'
function ListenPid([int]$port){
 @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique)
}
$before9444=@(ListenPid 9444)
$existing=@(ListenPid 9555)
$started=$false
if($false -and $existing.Count -eq 0){
 $chrome=@(
   (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
   (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
 )|Where-Object {Test-Path -LiteralPath $_ -PathType Leaf}|Select-Object -First 1
 if($chrome){
  New-Item -ItemType Directory -Path $profile -Force|Out-Null
  $profileArg='--user-data-dir="'+$profile+'"'
  Start-Process -FilePath $chrome -ArgumentList @($profileArg,'--remote-debugging-port=9555','--remote-debugging-address=127.0.0.1','--no-first-run','about:blank')|Out-Null
  $started=$true
  for($i=0;$i -lt 20;$i++){
   Start-Sleep -Milliseconds 500
   $existing=@(ListenPid 9555)
   if($existing.Count -gt 0){break}
  }
 }else{$code='CDP9555_CHROME_NOT_FOUND'}
}
$verified=$false
if($existing.Count -eq 1){
 $proc=Get-CimInstance Win32_Process -Filter ("ProcessId="+$existing[0])
 $listeners=@(Get-NetTCPConnection -LocalPort 9555 -State Listen -ErrorAction SilentlyContinue)
 if($proc -and $proc.Name -eq 'chrome.exe' -and $proc.CommandLine -match '(?:^|\s)--remote-debugging-port=9555(?:\s|$)' -and $proc.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0 -and @($listeners|Where-Object {$_.LocalAddress -notin @('127.0.0.1','::1')}).Count -eq 0){$verified=$true}else{$code='CDP9555_PORT_OR_PROFILE_CONFLICT'}
}elseif($existing.Count -gt 1){$code='CDP9555_PORT_OR_PROFILE_CONFLICT'}
if($verified){
 $client=@'
import pathlib,json,re,subprocess,time,threading,queue
def classify(value,prefix):
    t=json.dumps(value,ensure_ascii=False).lower()
    rules=[("ARG",r"invalid (?:arguments|params|parameters)|validation|expected number|required|invalid_type"),("PAGE",r"no page|page.{0,25}(?:not found|closed)|target closed|no selected"),("A11Y",r"accessibility|a11y|snapshot"),("TIME",r"timeout|timed out"),("PERM",r"permission|not allowed|denied"),("PROTO",r"protocol error|session closed")]
    for label,pat in rules:
        if re.search(pat,t):return prefix+"_"+label
    return prefix+"_OTHER"
class MCP:
    def __init__(self,work):
        self.work=work
        self.q=queue.Queue()
        self.seq=0
        self.err=open(work/"mcp-stderr.txt","w",encoding="utf-8")
        self.p=subprocess.Popen(["cmd.exe","/d","/c","npx","-y","chrome-devtools-mcp@1.13.0","--browser-url=http://127.0.0.1:9555","--no-usage-statistics"],cwd=work,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=self.err,text=True,encoding="utf-8",errors="replace",bufsize=1)
        def reader():
            for line in self.p.stdout:
                try:
                    x=json.loads(line)
                    if isinstance(x,dict):self.q.put(x)
                except ValueError:pass
            self.q.put(None)
        threading.Thread(target=reader,daemon=True).start()
    def send(self,method,params=None,notification=False,timeout=25):
        x={"jsonrpc":"2.0","method":method}
        if params is not None:x["params"]=params
        if not notification:
            self.seq+=1
            x["id"]=self.seq
        self.p.stdin.write(json.dumps(x)+"\n")
        self.p.stdin.flush()
        if notification:return {}
        until=time.monotonic()+timeout
        while True:
            remain=until-time.monotonic()
            if remain<=0:raise TimeoutError(method)
            try:y=self.q.get(timeout=remain)
            except queue.Empty:raise TimeoutError(method)
            if y is None:raise EOFError(method)
            if y.get("id")!=self.seq:continue
            if "error" in y:raise RuntimeError(classify(y["error"],"RPC"))
            r=y.get("result")
            if not isinstance(r,dict):raise RuntimeError("INVALID")
            if r.get("isError"):raise RuntimeError(classify(r,"TOOL"))
            if method=="tools/call":
                with (self.work/"mcp-trace.jsonl").open("a",encoding="utf-8") as f:f.write(json.dumps({"tool":params.get("name"),"ok":True,"ts":time.time()})+"\n")
            return r
    def call(self,name,args=None,timeout=30):
        return self.send("tools/call",{"name":name,"arguments":args or {}},timeout=timeout)
    def close(self):
        # Closing stdio disconnects the MCP server; never call browser.close.
        try:self.p.stdin.close()
        except Exception:pass
        try:self.p.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.p.terminate()
            try:self.p.wait(timeout=5)
            except subprocess.TimeoutExpired:self.p.kill()
        self.err.close()

class Browser:
    """One isolated tab; the agent chooses the search and download approach."""
    def __init__(self,work):
        import secrets
        self.m=MCP(work); self.page_id=None
        try:
            self.m.send("initialize",{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"ttv-agy","version":"1.0"}})
            self.m.send("notifications/initialized",notification=True)
            self.schemas={x["name"]:x["inputSchema"] for x in self.m.send("tools/list")["tools"]}
            marker="about:blank#TTV_"+secrets.token_hex(12)
            def identify(r):
                def walk(v):
                    if isinstance(v,dict):
                        if v.get("url")==marker:
                            for k in ("id","pageId","page_id"):
                                x=v.get(k)
                                if isinstance(x,int) and not isinstance(x,bool):return x
                                if isinstance(x,str) and x.isdecimal():return int(x)
                        for x in v.values():
                            n=walk(x)
                            if n is not None:return n
                    elif isinstance(v,list):
                        for x in v:
                            n=walk(x)
                            if n is not None:return n
                n=walk(r.get("structuredContent",{}))
                if n is not None:return n
                for line in self.text(r).splitlines():
                    m=re.match(r"^\s*(?:[-*]\s*)?(\d+)\s*:\s*(.*)$",line)
                    if m and marker in m.group(2):return int(m.group(1))
            self.page_id=identify(self.m.call("new_page",{"url":marker},timeout=25))
            if self.page_id is None:self.page_id=identify(self.m.call("list_pages"))
            if self.page_id is None:raise RuntimeError("NO_PAGE_ID")
        except Exception:
            self.close();raise
    @staticmethod
    def text(r):return "\n".join(x.get("text","") for x in r.get("content",[]) if isinstance(x,dict))
    def call(self,name,args=None,timeout=15):
        args=dict(args or {})
        if name not in ("navigate_page","take_snapshot","click","fill","fill_form","type_text","press_key","evaluate_script","list_network_requests","get_network_request"):raise ValueError("TOOL_SCOPE")
        if "pageId" in self.schemas[name].get("properties",{}):args["pageId"]=self.page_id
        else:raise ValueError("PAGE_SCOPE_REQUIRED")
        return self.m.call(name,args,timeout=timeout)
    def close(self):
        if self.page_id is not None:
            try:self.m.call("close_page",{"pageId":self.page_id},timeout=8)
            except Exception:pass
            self.page_id=None
        self.m.close()
    def __enter__(self):return self
    def __exit__(self,*args):self.close()
'@
 [IO.File]::WriteAllText((Join-Path $run 'mcp_client.py'),$client,[Text.UTF8Encoding]::new($false))
 $probe=@'
import sys,pathlib,json,time,threading,http.server,secrets
run=pathlib.Path(__file__).resolve().parent
sys.path.insert(0,str(run))
from mcp_client import Browser
marker="TTV_LOCAL_"+secrets.token_hex(12)
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def do_GET(self):
        body=("<html><title>Local smoke</title><h1>"+marker+"</h1></html>").encode()
        self.send_response(200);self.send_header("Content-Type","text/html");self.send_header("Content-Length",str(len(body)));self.end_headers();self.wfile.write(body)
srv=http.server.ThreadingHTTPServer(("127.0.0.1",0),Handler)
threading.Thread(target=srv.serve_forever,daemon=True).start()
stage="OPEN";n=0;v=0;p=0;c=0
t=time.monotonic()
try:
    with Browser(run) as b:
        n=int(b.page_id is not None)
        stage="NAV"
        b.call("navigate_page",{"url":f"http://127.0.0.1:{srv.server_port}/"})
        v=1
        stage="SNAP"
        p=int(marker in b.text(b.call("take_snapshot")))
        stage="DONE"
    trace=[json.loads(l) for l in (run/"mcp-trace.jsonl").read_text().splitlines()]
    c=int(any(x.get("tool")=="close_page" and x.get("ok") for x in trace))
except Exception as e:
    stage=stage+"_"+(str(e) if str(e) in ("NO_PAGE_ID","PAGE_SCOPE_REQUIRED","TOOL_SCOPE","TOOL_ARG","RPC_ARG") else type(e).__name__.upper())
finally:srv.shutdown();srv.server_close()
(run/"PROBE_RESULT.json").write_text(json.dumps({"n":n,"v":v,"p":p,"c":c,"stage":stage,"seconds":round(time.monotonic()-t)}),encoding="utf-8")
print(f"HELPER_{'PASS' if n and v and p and c else 'FAIL'}_{stage}_N{n}V{v}P{p}C{c}_T{round(time.monotonic()-t)}")
'@
 [IO.File]::WriteAllText((Join-Path $run 'helper_probe.py'),$probe,[Text.UTF8Encoding]::new($false))
 $py=@'
import sys,pathlib,os,json,re
owner,run=map(pathlib.Path,sys.argv[1:])
def read(p):
    try:
        if p.is_file() and p.stat().st_size<=4194304:return p.read_text(encoding="utf-8-sig",errors="replace")
    except OSError:pass
    return ""
history=pathlib.Path(os.environ["ProgramData"])/"TorrentTVVietsub"/"LaptopHostOps"/"History"
old=[]
for f in history.glob("receipt-*.json"):
    try:
        q=json.loads(read(f))
        if q.get("source_commit")=="edc92c5fe50bdd5cc6da8fa9fd82b5325c795ec6" and q.get("operation")=="agy-native-browser-readout-1124" and q.get("result")=="SUCCESS" and re.fullmatch(r"[a-f0-9]{32}",q.get("nonce","")):old.append(q["nonce"])
    except (ValueError,TypeError):pass
if len(old)!=1:
    print("AGYPATH_PRIOR_HOLD");sys.exit(0)
p=run.parent/("agy-helper-local-"+old[0])
events=[]
for line in read(p/"agy-stdout.jsonl").splitlines():
    try:
        x=json.loads(line)
        if isinstance(x,dict):events.append(x)
    except ValueError:pass
# Inspect nested output, excluding the user prompt and instructions.
texts=[]; kinds=set(); calls=0; replies=0
def walk(x,depth=0):
    global calls,replies
    if depth>12:return
    if isinstance(x,dict):
        if str(x.get("role","")).lower() in ("user","system","developer"):return
        if str(x.get("event","")).lower() in ("user","system","init","session_start"):return
        for k,v in x.items():
            if k.lower() in ("event","type"):
                if isinstance(v,str):
                    kinds.add(v.lower())
                    if v.lower() in ("tool_use","tool_call","tool_start","tool_request","function_call"):calls+=1
                    if v.lower() in ("tool_result","tool_error","tool_end","tool_response","function_response"):replies+=1
            if k.lower() not in ("prompt","system_prompt","instructions","input","arguments","command"):walk(v,depth+1)
    elif isinstance(x,list):
        for v in x:walk(v,depth+1)
    elif isinstance(x,str):texts.append(x)
for e in events:walk(e)
log=read(p/"agy-stderr.txt")+"\n"+read(p/"mcp-stderr.txt")+"\n"+"\n".join(texts)
flags={
 "REL":r"relative paths?.{0,120}(?:not supported|not allowed|invalid|absolute|required)|(?:invalid|unsupported).{0,70}relative paths?|sandbox.{0,80}relative path",
 "DENY":r"permission denied|access denied|sandbox.{0,80}(?:denied|blocked)|approval required|not permitted|not authorized|requires approval",
 "SHELL":r"not recognized as (?:an internal|the name)|command not found|cannot find the path|unexpected token|no such file",
 "PY":r"Traceback \(most recent call last\)|ModuleNotFoundError|SyntaxError|NameError|ImportError",
 "TIME":r"timed out|deadline exceeded|timeout exceeded|execution timeout",
 "REFUSE":r"(?:cannot|unable to|can.t|could not).{0,90}(?:run|execute|shell|command)|(?:no|not have).{0,70}(?:shell|execution|terminal).{0,50}(?:tool|access|permission)",
 "QUOTA":r"resource.exhausted|quota.exceeded|rate.limit.exceeded|usage limit|capacity exhausted",
}
hit={k:int(bool(re.search(v,log,re.I|re.S))) for k,v in flags.items()}
print("AGYPATH_AUDIT_"+''.join(k[0]+str(hit[k]) for k in flags)+"_C"+str(min(calls,99))+"_R"+str(min(replies,99))+"_E"+str(min(len(events),99)))
'@
 $f=Join-Path $run 'control.py'
 [IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
 $out=@(& py -3 -I -B $f $owner $run 2> (Join-Path $run 'python-stderr.txt'))
 if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,65}$'){$code=[string]$out[0]}else{$code='MCP_HEADLESS_LOCAL_ERROR'}
}
$after9444=@(ListenPid 9444)
$stable=if(($before9444 -join ',') -ceq ($after9444 -join ',')){1}else{0}
$code=$code+'_P9555'+[int]$verified+'_START'+[int]$started+'_P9444STABLE'+$stable
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
