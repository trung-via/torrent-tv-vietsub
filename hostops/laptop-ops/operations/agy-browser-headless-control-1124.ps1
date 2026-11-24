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
    (run/"mcp_client.py").write_text("import pathlib,json,re,subprocess,time,threading,queue\ndef classify(value,prefix):\n    t=json.dumps(value,ensure_ascii=False).lower()\n    rules=[(\"ARG\",r\"invalid (?:arguments|params|parameters)|validation|expected number|required|invalid_type\"),(\"PAGE\",r\"no page|page.{0,25}(?:not found|closed)|target closed|no selected\"),(\"A11Y\",r\"accessibility|a11y|snapshot\"),(\"TIME\",r\"timeout|timed out\"),(\"PERM\",r\"permission|not allowed|denied\"),(\"PROTO\",r\"protocol error|session closed\")]\n    for label,pat in rules:\n        if re.search(pat,t):return prefix+\"_\"+label\n    return prefix+\"_OTHER\"\nclass MCP:\n    def __init__(self,work):\n        self.work=work\n        self.q=queue.Queue()\n        self.seq=0\n        self.err=open(work/\"mcp-stderr.txt\",\"w\",encoding=\"utf-8\")\n        self.p=subprocess.Popen([\"cmd.exe\",\"/d\",\"/c\",\"npx\",\"-y\",\"chrome-devtools-mcp@1.13.0\",\"--browser-url=http://127.0.0.1:9555\",\"--no-usage-statistics\"],cwd=work,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=self.err,text=True,encoding=\"utf-8\",errors=\"replace\",bufsize=1)\n        def reader():\n            for line in self.p.stdout:\n                try:\n                    x=json.loads(line)\n                    if isinstance(x,dict):self.q.put(x)\n                except ValueError:pass\n            self.q.put(None)\n        threading.Thread(target=reader,daemon=True).start()\n    def send(self,method,params=None,notification=False,timeout=25):\n        x={\"jsonrpc\":\"2.0\",\"method\":method}\n        if params is not None:x[\"params\"]=params\n        if not notification:\n            self.seq+=1\n            x[\"id\"]=self.seq\n        self.p.stdin.write(json.dumps(x)+\"\\n\")\n        self.p.stdin.flush()\n        if notification:return {}\n        until=time.monotonic()+timeout\n        while True:\n            remain=until-time.monotonic()\n            if remain<=0:raise TimeoutError(method)\n            try:y=self.q.get(timeout=remain)\n            except queue.Empty:raise TimeoutError(method)\n            if y is None:raise EOFError(method)\n            if y.get(\"id\")!=self.seq:continue\n            if \"error\" in y:raise RuntimeError(classify(y[\"error\"],\"RPC\"))\n            r=y.get(\"result\")\n            if not isinstance(r,dict):raise RuntimeError(\"INVALID\")\n            if r.get(\"isError\"):raise RuntimeError(classify(r,\"TOOL\"))\n            if method==\"tools/call\":\n                with (self.work/\"mcp-trace.jsonl\").open(\"a\",encoding=\"utf-8\") as f:f.write(json.dumps({\"tool\":params.get(\"name\"),\"ok\":True})+\"\\n\")\n            return r\n    def call(self,name,args=None,timeout=30):\n        return self.send(\"tools/call\",{\"name\":name,\"arguments\":args or {}},timeout=timeout)\n    def close(self):\n        # Closing stdio disconnects the MCP server; never call browser.close.\n        try:self.p.stdin.close()\n        except Exception:pass\n        try:self.p.wait(timeout=5)\n        except subprocess.TimeoutExpired:\n            self.p.terminate()\n            try:self.p.wait(timeout=5)\n            except subprocess.TimeoutExpired:self.p.kill()\n        self.err.close()\n",encoding="utf-8")
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
    prompt="Owner approved one normal signed-in OpenSubtitles acquisition on the dedicated Chrome 9555. WORKED EXAMPLE FROM INDEPENDENT BRAIN: For Spider-Man: Brand New Day (2026), IMDb tt22084616, an ordinary browser navigation to https://www.opensubtitles.org/en/search/sublanguageid-eng/imdbid-22084616 returned 15 subtitle rows, 11 WEB candidates, zero exact seleZen names. The actual video release metadata suggests WEB-DL 1080p, 145 minutes, 23.976 fps; MovieDalen labels a Russian dub, not an English subtitle requirement. Brain opened candidate 14109322 (PAHE, WEB, English, runtime 145 min, fps not established) and 14104608 (WEB, English, runtime 145 min, 23.976 fps). Prefer 14104608 if your live page reconfirms this metadata; do not blindly trust an example or require identical release group if no conflict in title, cut, fps or duration. This is metadata compatibility, not proven playback synchronization. GENERAL METHOD: identify movie by title/year and IMDb ID; use the normal English-filtered movie catalog; shortlist compatible WEB rows; inspect candidate details; choose one based on source, language, fps, duration and cut evidence; never treat a missing release label as automatic NO_MATCH. Use the provided workspace mcp_client.py unchanged, import MCP, write and execute one concise Python script. Initialize protocolVersion 2025-06-18, capabilities {}, clientInfo name ttv-agy version 1.0; send notifications/initialized, tools/list; inspect schemas. Create exactly one new tab about:blank with unique fragment marker; identify its actual pageId from new_page response or list_pages by exact marker. Use that pageId explicitly for all page-scoped calls, including take_snapshot and click. Use returned element uids and actual schemas. Navigate directly to the verified English IMDb catalog URL above through MCP, open actual candidate link from the result, verify detail, then follow the actual normal website-issued download link on dl.opensubtitles.org if available, using the existing signed-in browser session. Do not construct or guess the URL. A download can make browser navigation report an interruption while Chrome saves a ZIP; check the new download file before concluding failure. Report selected_subtitle_id as a numeric string and the real downloaded filename. The local verifier checks the artifact regardless of your status. Do not repeat a successful download. Do not spend time on broad search or write a long narrative. Use existing authorized browser session only; stop immediately on 401/403/429, login requirement, CAPTCHA, payment or other denial. No bypass, spoofing, direct provider HTTP/API, Playwright, direct CDP navigation, OpenSubs CLI, native AGY MCP configuration, /browser, reading credentials/cookies/storage/unrelated tabs, or repeat provider requests after denial. Only Chrome 9555; never touch 9444. Close only your created tab by its pageId and disconnect MCP without closing Chrome. Write RESULT.json even on failure with status (DOWNLOADED, ACCESS_DENIED, AUTH_REQUIRED, NO_MATCH, DOWNLOAD_FAILED, CDP_FAILED, OTHER), stage (HOME, SEARCH, DETAIL, DOWNLOAD, CDP), observed_http_status integer or null, download_host hostname or null, release_match boolean (true means metadata compatibility, not proven sync), method, downloaded_filename basename or null, actual_test describing observed source, candidate ID, language/fps/runtime and any uncertainty. Report actual new download filename only; HostOps checks file and cues independently. No reuse of preexisting files or fabricated SRT. No payment. No OwnerBridge, translation or TV changes."
    args=[cli,"--model",model,"--sandbox","--mode","auto","--print-timeout","240s","--output-format","stream-json","-p",prompt]
    start=time.monotonic()
    try:
        p=subprocess.run(args,env=env,cwd=run,text=True,encoding="utf-8",errors="replace",capture_output=True,timeout=270,check=False)
    except subprocess.TimeoutExpired as e:
        for name,raw in (("agy-stdout.jsonl",e.stdout),("agy-stderr.txt",e.stderr)):
            if raw is not None:
                (run/name).write_bytes(raw if isinstance(raw,bytes) else raw.encode("utf-8"))
        print("CDP9555_TIMEOUT_RESULT_UNKNOWN");sys.exit(0)
    (run/"agy-stdout.jsonl").write_text(p.stdout,encoding="utf-8")
    (run/"agy-stderr.txt").write_text(p.stderr,encoding="utf-8")
    records=[]
    for line in p.stdout.splitlines():
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
    # Reconcile independently observed filesystem output even if AGY reports failure.
    # This is a fixed Spider-Man benchmark: Brain verified 14104608 metadata.
    # Other IDs must be assessed separately; do not infer playback synchronization.
    reported_status=status
    after=candidates()
    selected_id=str(rr.get("selected_subtitle_id") or "14104608")
    f,cues=verify_new_download(before,after,selected_id) if selected_id=="14104608" and match and status in ("DOWNLOADED","DOWNLOAD_FAILED","UNCLASSIFIED") else (None,0)
    files=0
    if f is not None:
        shutil.copyfile(f,downloads/f.name)
        if cue_count(downloads/f.name)==cues:
            files=1
            status="DOWNLOADED"
            stage="DOWNLOAD"
            dlhost=1
    if files==0 and status=="DOWNLOADED":
        status="DOWNLOAD_FAILED"
    (run/"verified-acquisition.json").write_text(json.dumps({"reported_status":reported_status,"verified_status":status,"candidate_id":selected_id,"files":files,"cues":cues if files else 0,"source_verified":bool(files),"playback_sync_verified":False}),encoding="utf-8")
    if not files:cues=0
    trace=[]
    try:
        for line in (run/"mcp-trace.jsonl").read_text(encoding="utf-8").splitlines():
            x=json.loads(line)
            if isinstance(x,dict) and x.get("ok") is True:trace.append(x.get("tool"))
    except Exception:pass
    print(f"9555TRAIN_{codes[status]}_{stage}_H{http}_D{dlhost}_M{match}_N{int('new_page' in trace)}_S{int('take_snapshot' in trace)}_F{min(files,9)}_C{min(cues,99999)}_{round(time.monotonic()-start)}S")
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
