# Brain-owned catalog search using normal Chrome website, no AGY or download.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('brain-cdp9555-catalog-'+$rq.nonce)
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
 $py=@'
import sys,pathlib,os,json,re,subprocess,time,urllib.request,http.server,threading,secrets,queue
owner,run=map(pathlib.Path,sys.argv[1:])
def classify(value,prefix):
    t=json.dumps(value,ensure_ascii=False).lower()
    rules=[("ARG",r"invalid (?:arguments|params|parameters)|validation|expected number|required|invalid_type"),("PAGE",r"no page|page.{0,25}(?:not found|closed)|target closed|no selected"),("A11Y",r"accessibility|a11y|snapshot"),("TIME",r"timeout|timed out"),("PERM",r"permission|not allowed|denied"),("PROTO",r"protocol error|session closed")]
    for label,pat in rules:
        if re.search(pat,t):return prefix+"_"+label
    return prefix+"_OTHER"
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
            if "error" in y:raise RuntimeError(classify(y["error"],"RPC"))
            r=y.get("result")
            if not isinstance(r,dict):raise RuntimeError("INVALID")
            if r.get("isError"):raise RuntimeError(classify(r,"TOOL"))
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
    client=None
    page_id=None
    code="BRAIN_SEARCH_UNKNOWN"
    marker="about:blank#TTV_BRAIN_"+secrets.token_hex(12)
    def ident(r):
        def walk(v):
            if isinstance(v,dict):
                if v.get("url")==marker:
                    for k in ("id","pageId","page_id"):
                        n=v.get(k)
                        if isinstance(n,int) or isinstance(n,str) and n.isdecimal():return int(n)
                for x in v.values():
                    n=walk(x)
                    if n is not None:return n
            elif isinstance(v,list):
                for x in v:
                    n=walk(x)
                    if n is not None:return n
        n=walk(r.get("structuredContent",{}))
        if n is not None:return n
        for item in r.get("content",[]):
            for line in item.get("text","").splitlines():
                m=re.match(r"^\s*(?:[-*]\s*)?(\d+)\s*:\s*(.*)$",line)
                if m and marker in m.group(2):return int(m.group(1))
    def txt(r):return "\n".join(x.get("text","") for x in r.get("content",[]) if isinstance(x,dict))
    try:
        client=MCP(run)
        client.send("initialize",{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"ttv-brain-catalog","version":"1.0"}},timeout=50)
        client.send("notifications/initialized",notification=True)
        schemas={x["name"]:x.get("inputSchema",{}) for x in client.send("tools/list").get("tools",[]) if isinstance(x,dict)}
        page_id=ident(client.call("new_page",{"url":marker},timeout=25))
        if page_id is None:page_id=ident(client.call("list_pages"))
        if page_id is None:raise RuntimeError("NO_ID")
        def call(name,args):
            schema=schemas[name]
            if "pageId" in schema.get("properties",{}):args={"pageId":page_id,**args}
            return client.call(name,args)
        # Normal public catalog URL, English filter and exact IMDb identity.
        url="https://www.opensubtitles.org/en/search/sublanguageid-eng/imdbid-22084616"
        call("navigate_page",{"url":url})
        snap=txt(call("take_snapshot",{}))
        if re.search(r"access denied|verify you are human|checking your browser|captcha|429 too many|403 forbidden|401 unauthorized",snap,re.I):
            code="BRAIN_SEARCH_ACCESS_STOP"
        else:
            fn="""() => JSON.stringify({host:location.hostname,path:location.pathname,title:document.title,rows:[...document.querySelectorAll('tr')].flatMap(r=>{let a=[...r.querySelectorAll('a[href]')].map(a=>a.href).filter(u=>/^https:\\/\\/(?:www\\.)?opensubtitles\\.org\\/en\\/subtitles\\/\\d+/i.test(u));return a.length?[{urls:a,text:r.innerText.slice(0,1200)}]:[]}).slice(0,100)})"""
            raw=txt(call("evaluate_script",{"function":fn}))
            (run/"catalog-private.txt").write_text(raw,encoding="utf-8")
            # MCP output usually wraps a JSON result in a fenced block, sometimes double encoded.
            data=None
            for candidate in [raw]+re.findall(r"(?s)\x60\x60\x60(?:json)?\s*(.*?)\s*\x60\x60\x60",raw):
                try:
                    obj=json.loads(candidate)
                    if isinstance(obj,str):obj=json.loads(obj)
                    if isinstance(obj,dict) and "rows" in obj:data=obj;break
                except (ValueError,TypeError):pass
            if not data:
                code="BRAIN_SEARCH_PARSE_HOLD"
            elif data.get("host") not in ("www.opensubtitles.org","opensubtitles.org"):
                code="BRAIN_SEARCH_HOST_HOLD"
            else:
                rows=data["rows"]
                web=[x for x in rows if re.search(r"\bWEB[- .]?(?:DL|Rip)\b|\bAMZN\b|\bETHEL\b",x["text"],re.I)]
                exact=[x for x in web if re.search(r"selezen",x["text"],re.I)]
                selected=(exact or web)
                ids=[]
                for x in selected:
                    for u in x["urls"]:
                        m=re.search(r"/en/subtitles/(\d+)",u)
                        if m and m.group(1) not in ids:ids.append(m.group(1))
                code=f"BRAIN_SEARCH_R{min(len(rows),99)}_W{min(len(web),99)}_E{min(len(exact),99)}_ID"+("_".join(ids[:2]) if ids else "NONE")
    except TimeoutError:code="BRAIN_SEARCH_TIMEOUT"
    except Exception as e:
        code="BRAIN_SEARCH_"+(str(e) if re.fullmatch(r"(?:RPC|TOOL)_[A-Z]+|NO_ID",str(e)) else "LOCALERR")
    finally:
        if client:
            if page_id is not None:
                try:client.call("close_page",{"pageId":page_id},timeout=10)
                except Exception:pass
            client.close()
        print(code)
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
