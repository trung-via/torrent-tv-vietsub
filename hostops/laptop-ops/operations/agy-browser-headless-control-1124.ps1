# One user-authorized logged-in website acquisition via Chrome DevTools MCP on CDP 9555.
# Keep the existing profile and normal website authorization intact.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('agy-cdp9555-mcp-auth-'+$rq.nonce)
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
import sys,pathlib,os,json,re,subprocess,time,urllib.request,hashlib,zipfile,shutil
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
    config=run/".agents"
    config.mkdir()
    (config/"mcp_config.json").write_text(json.dumps({"mcpServers":{"ttv-chrome9555":{"command":"cmd.exe","args":["/d","/c","npx","-y","chrome-devtools-mcp@1.13.0","--browser-url=http://127.0.0.1:9555","--no-usage-statistics","--log-file="+str(run/"mcp-debug.log")],"tools":{name:{"eager":True} for name in ("new_page","list_pages","select_page","navigate_page","take_snapshot","click","fill","press_key","wait_for","close_page")}}}}),encoding="utf-8")
    # Snapshot metadata only for subtitle-shaped files in the dedicated profile's ordinary download location.
    default=pathlib.Path.home()/"Downloads"
    try:
        prefs=run.parent/"CDP9555Profile"/"Default"/"Preferences"
        pref=json.loads(prefs.read_text(encoding="utf-8"))
        d=pathlib.Path(pref.get("download",{}).get("default_directory",str(default)))
        if d.is_absolute() and d.is_dir():default=d
    except Exception:pass
    def candidates():
        try:return {f.name:(f.stat().st_size,f.stat().st_mtime_ns) for f in default.iterdir() if f.is_file() and not f.is_symlink() and f.suffix.lower() in (".srt",".zip")}
        except Exception:return {}
    before=candidates()
    prompt=("Owner has now signed in to OpenSubtitles in the dedicated persistent Chrome 9555 profile. This is a changed authorization condition, so run one normal website acquisition attempt. Use ONLY the workspace ttv-chrome9555 Chrome DevTools MCP (attached to http://127.0.0.1:9555) for website actions, not Playwright, /browser autoConnect, shell browser automation, APIs, other browser profiles or OpenSubs CLI. Use new_page to open https://www.opensubtitles.org/ in a new tab and take_snapshot; then search Spider-Man: Brand New Day (2026), English subtitle, WEB-DL 1080p, selezen release and MovieDalen audio label when applicable. Verify release, timing and language evidence; no guesses. Use the normal website download control once, following actual redirects including dl.opensubtitles.org only if supplied by the site. Do not read cookies, credentials, other tabs or storage, change account settings, solve CAPTCHA, evade denial, modify browser identity, pay or exceed limits. Stop on access restriction, login or download prompt requiring human. Keep original Chrome and existing tabs intact, close only your own new tab. Write RESULT.json in this workspace with status (DOWNLOADED, ACCESS_DENIED, AUTH_REQUIRED, NO_MATCH, DOWNLOAD_FAILED, CDP_FAILED, OTHER), stage (HOME, SEARCH, DETAIL, DOWNLOAD, CDP), observed_http_status (integer or null, never invent), download_host (hostname only or null), release_match (boolean), method, downloaded_filename (basename only, actual new file if known), actual_test. Browser downloads may land in the profile's normal download folder; report the actual filename from the download event or website, not a guess. Do not copy old files or create fabricated SRT. Do not change download settings. HostOps will independently verify any new file. No translation or TV changes. Use only genuine observations.")
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
    # Copy only the newly created exact reported download, never unrelated preexisting files.
    name=rr.get("downloaded_filename")
    after=candidates()
    if status=="DOWNLOADED" and isinstance(name,str) and name==pathlib.Path(name).name and name not in before and name in after and after[name][0]<=10000000:
        src=default/name
        if src.is_file() and not src.is_symlink():shutil.copyfile(src,downloads/name)
    cues=0
    files=0
    for f in downloads.iterdir():
        if f.is_file() and not f.is_symlink() and f.stat().st_size<=10000000 and f.suffix.lower() in (".srt",".zip"):
            files+=1
            try:
                if f.suffix.lower()==".srt":blobs=[f.read_bytes()]
                else:
                    with zipfile.ZipFile(f) as z:
                        blobs=[z.read(i) for i in [x for x in z.infolist() if x.filename.lower().endswith(".srt") and x.file_size<=2000000][:5]]
                for data in blobs:
                    cues=max(cues,len(re.findall(rb"(?m)^\d{2}:\d{2}:\d{2},\d{3}\s+-->\s+\d{2}:\d{2}:\d{2},\d{3}",data)))
            except Exception:pass
    nodes=[]
    def walk(x):
        if isinstance(x,dict):
            nodes.append(x)
            for v in x.values():walk(v)
        elif isinstance(x,list):
            for v in x:walk(v)
    walk([x for x in records if x.get("event") not in ("user","result","assistant")])
    names=[str(v).lower() for x in nodes for k,v in x.items() if k.lower() in ("name","tool_name","toolname","step_type") and isinstance(v,str)]
    mcp=int(any("new_page" in v or "navigate_page" in v or "take_snapshot" in v for v in names))
    print(f"9555MCP_{codes[status]}_{stage}_H{http}_D{dlhost}_M{match}_T{mcp}_F{min(files,9)}_C{min(cues,99999)}_{round(time.monotonic()-start)}S")
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
