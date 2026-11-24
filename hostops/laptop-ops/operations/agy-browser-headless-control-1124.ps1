# AGY acquisition using the independently validated stdio MCP client and explicit pageId.
# Keep the existing profile and normal website authorization intact.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('agy-cdp9555-mcp-stdio-'+$rq.nonce)
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
import sys,pathlib,os,json,re,subprocess,time,urllib.request,urllib.parse,hashlib,zipfile,shutil
owner,run=map(pathlib.Path,sys.argv[1:])
sys.path[:0]=[str(owner/"app/poc/p2-aisub")]
from translator_gateway import preflight_antigravity,_validated_antigravity_alias
try:
    cli=preflight_antigravity()
    model=_validated_antigravity_alias("gemini-4-hydrogen-low","low")
    env=dict(os.environ)
    for k in ("GEMINI_API_KEY","GOOGLE_API_KEY","GOOGLE_GEMINI_BASE_URL","AGY_ADC_AUTH","GOOGLE_CLOUD_PROJECT","GOOGLE_CLOUD_QUOTA_PROJECT"):env.pop(k,None)
    downloads=run/"downloads"
    downloads.mkdir()
    try:
        opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open("http://127.0.0.1:9555/json/version",timeout=3) as resp:
            version=json.load(resp)
        if not str(version.get("Browser","")).startswith("Chrome/") or not str(version.get("webSocketDebuggerUrl","")).startswith("ws://127.0.0.1:9555/"):
            print("CDP9555_ENDPOINT_UNVERIFIED");sys.exit(0)
    except Exception:
        print("CDP9555_ENDPOINT_UNREACHABLE");sys.exit(0)
    (run/"mcp_client.py").write_text("import pathlib,json,re,subprocess,time,threading,queue\ndef classify(value,prefix):\n    t=json.dumps(value,ensure_ascii=False).lower()\n    rules=[(\"ARG\",r\"invalid (?:arguments|params|parameters)|validation|expected number|required|invalid_type\"),(\"PAGE\",r\"no page|page.{0,25}(?:not found|closed)|target closed|no selected\"),(\"A11Y\",r\"accessibility|a11y|snapshot\"),(\"TIME\",r\"timeout|timed out\"),(\"PERM\",r\"permission|not allowed|denied\"),(\"PROTO\",r\"protocol error|session closed\")]\n    for label,pat in rules:\n        if re.search(pat,t):return prefix+\"_\"+label\n    return prefix+\"_OTHER\"\nclass MCP:\n    def __init__(self,work):\n        self.work=work\n        self.q=queue.Queue()\n        self.seq=0\n        self.err=open(work/\"mcp-stderr.txt\",\"w\",encoding=\"utf-8\")\n        self.p=subprocess.Popen([\"cmd.exe\",\"/d\",\"/c\",\"npx\",\"-y\",\"chrome-devtools-mcp@1.13.0\",\"--browser-url=http://127.0.0.1:9555\",\"--no-usage-statistics\"],cwd=work,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=self.err,text=True,encoding=\"utf-8\",errors=\"replace\",bufsize=1)\n        def reader():\n            for line in self.p.stdout:\n                try:\n                    x=json.loads(line)\n                    if isinstance(x,dict):self.q.put(x)\n                except ValueError:pass\n            self.q.put(None)\n        threading.Thread(target=reader,daemon=True).start()\n    def send(self,method,params=None,notification=False,timeout=25):\n        x={\"jsonrpc\":\"2.0\",\"method\":method}\n        if params is not None:x[\"params\"]=params\n        if not notification:\n            self.seq+=1\n            x[\"id\"]=self.seq\n        self.p.stdin.write(json.dumps(x)+\"\\n\")\n        self.p.stdin.flush()\n        if notification:return {}\n        until=time.monotonic()+timeout\n        while True:\n            remain=until-time.monotonic()\n            if remain<=0:raise TimeoutError(method)\n            try:y=self.q.get(timeout=remain)\n            except queue.Empty:raise TimeoutError(method)\n            if y is None:raise EOFError(method)\n            if y.get(\"id\")!=self.seq:continue\n            if \"error\" in y:raise RuntimeError(classify(y[\"error\"],\"RPC\"))\n            r=y.get(\"result\")\n            if not isinstance(r,dict):raise RuntimeError(\"INVALID\")\n            if r.get(\"isError\"):raise RuntimeError(classify(r,\"TOOL\"))\n            if method==\"tools/call\":\n                with (self.work/\"mcp-trace.jsonl\").open(\"a\",encoding=\"utf-8\") as f:f.write(json.dumps({\"tool\":params.get(\"name\"),\"ok\":True,\"ts\":time.time()})+\"\\n\")\n            return r\n    def call(self,name,args=None,timeout=30):\n        return self.send(\"tools/call\",{\"name\":name,\"arguments\":args or {}},timeout=timeout)\n    def close(self):\n        # Closing stdio disconnects the MCP server; never call browser.close.\n        try:self.p.stdin.close()\n        except Exception:pass\n        try:self.p.wait(timeout=5)\n        except subprocess.TimeoutExpired:\n            self.p.terminate()\n            try:self.p.wait(timeout=5)\n            except subprocess.TimeoutExpired:self.p.kill()\n        self.err.close()\n\nclass Browser:\n    \"\"\"One isolated tab; the agent chooses the search and download approach.\"\"\"\n    def __init__(self,work):\n        import secrets\n        self.m=MCP(work); self.page_id=None\n        try:\n            self.m.send(\"initialize\",{\"protocolVersion\":\"2025-06-18\",\"capabilities\":{},\"clientInfo\":{\"name\":\"ttv-agy\",\"version\":\"1.0\"}})\n            self.m.send(\"notifications/initialized\",notification=True)\n            self.schemas={x[\"name\"]:x[\"inputSchema\"] for x in self.m.send(\"tools/list\")[\"tools\"]}\n            marker=\"about:blank#TTV_\"+secrets.token_hex(12)\n            def identify(r):\n                def walk(v):\n                    if isinstance(v,dict):\n                        if v.get(\"url\")==marker:\n                            for k in (\"id\",\"pageId\",\"page_id\"):\n                                x=v.get(k)\n                                if isinstance(x,int) and not isinstance(x,bool):return x\n                                if isinstance(x,str) and x.isdecimal():return int(x)\n                        for x in v.values():\n                            n=walk(x)\n                            if n is not None:return n\n                    elif isinstance(v,list):\n                        for x in v:\n                            n=walk(x)\n                            if n is not None:return n\n                n=walk(r.get(\"structuredContent\",{}))\n                if n is not None:return n\n                for line in self.text(r).splitlines():\n                    m=re.match(r\"^\\s*(?:[-*]\\s*)?(\\d+)\\s*:\\s*(.*)$\",line)\n                    if m and marker in m.group(2):return int(m.group(1))\n            self.page_id=identify(self.m.call(\"new_page\",{\"url\":marker},timeout=25))\n            if self.page_id is None:self.page_id=identify(self.m.call(\"list_pages\"))\n            if self.page_id is None:raise RuntimeError(\"NO_PAGE_ID\")\n        except Exception:\n            self.close();raise\n    @staticmethod\n    def text(r):return \"\\n\".join(x.get(\"text\",\"\") for x in r.get(\"content\",[]) if isinstance(x,dict))\n    def call(self,name,args=None,timeout=15):\n        args=dict(args or {})\n        if name not in (\"navigate_page\",\"take_snapshot\",\"click\",\"fill\",\"fill_form\",\"type_text\",\"press_key\",\"evaluate_script\",\"list_network_requests\",\"get_network_request\"):raise ValueError(\"TOOL_SCOPE\")\n        if \"pageId\" in self.schemas[name].get(\"properties\",{}):args[\"pageId\"]=self.page_id\n        else:raise ValueError(\"PAGE_SCOPE_REQUIRED\")\n        return self.m.call(name,args,timeout=timeout)\n    def close(self):\n        if self.page_id is not None:\n            try:self.m.call(\"close_page\",{\"pageId\":self.page_id},timeout=8)\n            except Exception:pass\n            self.page_id=None\n        self.m.close()\n    def __enter__(self):return self\n    def __exit__(self,*args):self.close()\n",encoding="utf-8")
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
    before=candidates()
    prompt="One authorized English subtitle acquisition benchmark for a different movie: The Odyssey (2026), BDRip-HEVC 1080p, Jaskier is a dub label. No subtitle ID is supplied. Use only ordinary OpenSubtitles.org browsing in existing Chrome 9555. A ready Python helper is in mcp_client.py: from mcp_client import Browser; with Browser(pathlib.Path.cwd()) as b: use b.call(name,args), b.text(result), b.schemas. Use one Python execution, one tab. First identify the correct title/year/IMDb and filter English; the ordinary catalog pattern /en/search/sublanguageid-eng/imdbid-<digits> works once the IMDb is known. Inspect actual detail; prefer matching BluRay cut/source/FPS/runtime; identical release group/codec wording is not required. Do not accept WEB if cut/timing conflicts. Before clicking download, save SELECTION.json with selected_subtitle_id (digits from real detail URL), detail_url, title, year, language, release_match (boolean for metadata, not playback sync), actual_test (brief evidence). Follow the website-issued normal download link on dl.opensubtitles.org; do not invent URLs. Navigation interruption can still mean a successful ZIP download. Do not click twice. Stop on denial/login/CAPTCHA/401/403/429/payment; no bypass or direct API/HTTP, no credentials, no unrelated tabs, no 9444. Write RESULT.json with status (DOWNLOADED, DOWNLOAD_FAILED, NO_MATCH, ACCESS_DENIED, AUTH_REQUIRED, CDP_FAILED, OTHER), stage, observed_http_status, download_host, selected_subtitle_id, release_match, downloaded_filename if known and brief actual_test. The host independently verifies new ZIP/SRT. Minimize reasoning and tool calls; aim for 60 seconds. No translation or production changes."
    args=[cli,"--model",model,"--sandbox","--mode","auto","--print-timeout","240s","--output-format","stream-json","-p",prompt]
    start=time.monotonic()
    wall_start=time.time()
    try:
        p=subprocess.run(args,env=env,cwd=run,text=True,encoding="utf-8",errors="replace",capture_output=True,timeout=270,check=False)
    except subprocess.TimeoutExpired as e:
        # Reconcile a completed physical download even when AGY timed out.
        p=None
        for name,raw in (("agy-stdout.jsonl",e.stdout),("agy-stderr.txt",e.stderr)):
            if raw is not None:(run/name).write_bytes(raw if isinstance(raw,bytes) else raw.encode("utf-8"))
    else:
        (run/"agy-stdout.jsonl").write_text(p.stdout,encoding="utf-8")
        (run/"agy-stderr.txt").write_text(p.stderr,encoding="utf-8")
    stdout=(run/"agy-stdout.jsonl").read_text(encoding="utf-8",errors="replace") if (run/"agy-stdout.jsonl").is_file() else ""
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
    film_match=bool(str(selection.get("title","")).strip().casefold()=="the odyssey" and str(selection.get("year"))=="2026" and str(selection.get("language","")).casefold() in ("english","en","eng"))
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
    trace=[]
    try:
        for line in (run/"mcp-trace.jsonl").read_text(encoding="utf-8").splitlines():
            x=json.loads(line)
            if isinstance(x,dict) and x.get("ok") is True:trace.append(x.get("tool"))
    except Exception:pass
    print(f"GEN2_{codes[status]}_M{match}_F{files}_C{min(cues,99999)}_S{max(selected_at,0)}_D{max(acquired_at-selected_at,0) if files and selected_at>=0 else 0}_T{round(time.monotonic()-start)}_X{int(p is None)}")
except Exception:print("MCP_HEADLESS_LOCAL_ERROR")
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
