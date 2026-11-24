# Independent stdio MCP protocol test using a local fixture only.
# No external website access or changes to the existing Chrome profile.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('mcp-cdp9555-stdio-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='CDP9555_NOT_READY'
$profile=Join-Path $root 'CDP9555Profile'
function ListenPid([int]$port){
 @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique)
}
$before9444=@(ListenPid 9444)
$existing=@(ListenPid 9555)
$started=$false
if($existing.Count -eq 0){
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
 $py=@'
import sys,pathlib,os,json,re,subprocess,time,urllib.request,http.server,threading,secrets,queue
owner,run=map(pathlib.Path,sys.argv[1:])
class MCP:
    def __init__(self,work):
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
            if "error" in y:raise RuntimeError("RPC_ERROR")
            r=y.get("result")
            if not isinstance(r,dict) or r.get("isError"):raise RuntimeError("TOOL_ERROR")
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
def main():
    flags={k:0 for k in ("init","list","new","snapshot","hit","close")}
    stage="ENDPOINT"
    outcome="FAIL"
    client=None
    srv=None
    fixture=None
    page_id=None
    visits=[]
    start=time.monotonic()
    try:
        opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open("http://127.0.0.1:9555/json/version",timeout=3) as resp:v=json.load(resp)
        if not str(v.get("Browser","")).startswith("Chrome/") or not str(v.get("webSocketDebuggerUrl","")).startswith("ws://127.0.0.1:9555/"):raise RuntimeError("ENDPOINT")
        marker="TTV_MCP_"+secrets.token_hex(16)
        route="/"+secrets.token_hex(16)
        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self,*args):pass
            def do_GET(self):
                if self.path!=route:self.send_error(404);return
                visits.append(self.headers.get("User-Agent",""))
                body=("<html><title>TTV local MCP</title><h1>"+marker+"</h1></html>").encode()
                self.send_response(200);self.send_header("Content-Type","text/html");self.send_header("Content-Length",str(len(body)));self.end_headers();self.wfile.write(body)
        srv=http.server.ThreadingHTTPServer(("127.0.0.1",0),Handler)
        threading.Thread(target=srv.serve_forever,daemon=True).start()
        fixture=f"http://127.0.0.1:{srv.server_port}{route}"
        stage="SPAWN"
        client=MCP(run)
        stage="INIT"
        init=client.send("initialize",{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"ttv-local-smoke","version":"1.0"}},timeout=50)
        if not init.get("protocolVersion") or not init.get("serverInfo"):raise RuntimeError("INIT_INVALID")
        flags["init"]=1
        client.send("notifications/initialized",notification=True)
        stage="LIST"
        tools=client.send("tools/list")
        schemas={x["name"]:x.get("inputSchema",{}) for x in tools.get("tools",[]) if isinstance(x,dict) and isinstance(x.get("name"),str)}
        for name in ("new_page","take_snapshot","close_page"):
            if name not in schemas:raise RuntimeError("TOOL_MISSING")
        flags["list"]=1
        stage="NEW"
        result=client.call("new_page",{"url":fixture},timeout=40)
        flags["new"]=1
        # Only match the exact newly created fixture URL, never record existing tabs.
        def identify(r):
            for item in r.get("content",[]):
                if not isinstance(item,dict) or item.get("type")!="text":continue
                for line in item.get("text","").splitlines():
                    match=re.match(r"^\s*(\d+)\s*:\s*"+re.escape(fixture)+r"(?:\s|$)",line)
                    if match:return int(match.group(1))
            return None
        page_id=identify(result)
        if page_id is None and "list_pages" in schemas:
            page_id=identify(client.call("list_pages"))
        stage="SNAP"
        result=client.call("take_snapshot")
        flags["snapshot"]=int(any(marker in x.get("text","") for x in result.get("content",[]) if isinstance(x,dict) and x.get("type")=="text"))
        flags["hit"]=int(any("Chrome/" in ua for ua in visits))
        if flags["snapshot"] and flags["hit"]:outcome="PASS"
        else:outcome="MISMATCH"
        stage="DONE"
    except TimeoutError:outcome="TIMEOUT"
    except EOFError:outcome="EOF"
    except Exception as e:
        outcome=str(e) if str(e) in ("RPC_ERROR","TOOL_ERROR","TOOL_MISSING","INIT_INVALID","ENDPOINT") else "LOCALERR"
    finally:
        if client:
            if page_id is not None:
                try:client.call("close_page",{"pageId":page_id},timeout=10);flags["close"]=1
                except Exception:pass
            client.close()
        if srv:srv.shutdown();srv.server_close()
        flags["hit"]=int(any("Chrome/" in ua for ua in visits))
        (run/"RESULT.json").write_text(json.dumps({"outcome":outcome,"stage":stage,**flags,"elapsed_s":round(time.monotonic()-start)}),encoding="utf-8")
        print(f"MCPSTD_{outcome}_{stage}_I{flags['init']}_L{flags['list']}_N{flags['new']}_S{flags['snapshot']}_H{flags['hit']}_C{flags['close']}")
if __name__=="__main__":main()
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
