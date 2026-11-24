# One normal website acquisition test on the established dedicated CDP 9555 profile.
# Respect provider authorization; no CLI/API, alternate identity, or access-control circumvention.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('agy-cdp9555-live-'+$rq.nonce)
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
import sys,pathlib,os,json,re,subprocess,time,urllib.request,hashlib,zipfile,urllib.parse
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
    prompt=("You are the AGY executor for Torrent TV. The dedicated persistent Chrome CDP 9555 has passed a local browser and download test. Connect ONLY to http://127.0.0.1:9555, preferably using Playwright. Open a new tab and use the ordinary website at https://www.opensubtitles.org/. Do not change browser identity, headers, profile, cookies or proxy to evade previous denials. Stop at HTTP 401/403/429, login requirement, CAPTCHA or any other access restriction and report the stage. If the site permits ordinary access, search for English subtitles for Spider-Man: Brand New Day (2026), WEB-DL 1080p, selezen release and MovieDalen audio label if applicable. Verify release and timing evidence; do not substitute or invent a match. Use the website's actual download control or link, following normal redirects (including dl.opensubtitles.org only if the website supplies it); never guess download URLs, bypass restrictions, use OpenSubs CLI or REST API, or pay. Save at most one actual matching SRT/ZIP in downloads/. Use actual browser navigation responses and download event as evidence. Record RESULT.json with status (DOWNLOADED, ACCESS_DENIED, AUTH_REQUIRED, NO_MATCH, DOWNLOAD_FAILED, CDP_FAILED, OTHER), stage (HOME, SEARCH, DETAIL, DOWNLOAD, CDP), observed_http_status (integer or null), download_host (hostname only, or null), release_match (boolean), method, and actual_test. No credentials or private browser data in report. Do not touch 9444, existing tabs, global settings or OwnerBridge. Close only your own new tab and disconnect without closing Chrome. No translation or TV changes. Do not make another request after any denial. Report actual observations only.")
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
    print(f"9555_{codes[status]}_{stage}_H{http}_D{dlhost}_M{match}_F{min(files,9)}_C{min(cues,99999)}_{round(time.monotonic()-start)}S")
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
