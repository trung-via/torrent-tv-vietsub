# User-authorized one-shot test on existing Chrome CDP 9444; preserve all existing tabs.
# No profile changes, credentials access, access-control circumvention, or paid services.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('agy-cdp9444-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='CDP9444_NOT_READY'
$listeners=@(Get-NetTCPConnection -LocalPort 9444 -State Listen -ErrorAction SilentlyContinue)
$pids=@($listeners | Select-Object -ExpandProperty OwningProcess -Unique)
$verified=$false
if($pids.Count -eq 1){
 $proc=Get-CimInstance Win32_Process -Filter ("ProcessId="+$pids[0])
 if($proc -and $proc.Name -eq 'chrome.exe' -and $proc.CommandLine -match '(?:^|\s)--remote-debugging-port=9444(?:\s|$)' -and $proc.CommandLine -match '--user-data-dir='){$verified=$true}
}
if($verified){
 $py=@'
import sys,pathlib,os,json,re,subprocess,time,zipfile,urllib.request
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
        with opener.open("http://127.0.0.1:9444/json/version",timeout=3) as resp:
            version=json.load(resp)
        if not str(version.get("Browser","")).startswith("Chrome/") or not str(version.get("webSocketDebuggerUrl","")).startswith("ws://127.0.0.1:9444/"):
            print("CDP9444_ENDPOINT_UNVERIFIED");sys.exit(0)
    except Exception:
        print("CDP9444_ENDPOINT_UNREACHABLE");sys.exit(0)
    prompt=("Owner explicitly authorizes a one-shot ordinary OpenSubtitles website test in the existing Chrome profile served at http://127.0.0.1:9444. You are the AGY executor. Connect to that existing local Chrome endpoint using a supported mechanism of your choice, e.g. Playwright connect_over_cdp. Do not use another browser/profile, restart Chrome, change settings or install globally. Create exactly one new tab in the existing profile and operate ONLY on that new tab. Do not read, inspect, navigate, interact with or close preexisting tabs, including ChatGPT/WakeHub. Never inspect, export or disclose cookies, credentials, local storage, other browsing history or personal data. Normal website use with the existing signed-in session if any is authorized; do not enter credentials, modify accounts, or work around access restrictions. Visit https://www.opensubtitles.org/ normally. If the website permits it, search for English subtitles for Spider-Man: Brand New Day (2026), WEB-DL 1080p, selezen release and MovieDalen audio label when applicable. Verify actual release metadata; if no matching release, report no match. If a legitimate matching subtitle is available, use the normal download control once and save actual SRT or ZIP into downloads/ under this workspace. Do not use OpenSubs CLI, REST API, paid services or any mechanism to evade HTTP 403, CAPTCHA, login, access controls, or quotas. Stop on restriction. Leave all existing tabs and the Chrome process intact, close only your own new tab when finished and disconnect without browser.close. Write RESULT.json with status (DOWNLOADED, ACCESS_DENIED, AUTH_REQUIRED, NO_MATCH, CDP_FAILED, DOWNLOAD_FAILED, OTHER), observed_http_status, method, release_match (boolean), actual_test. Write no secrets or private profile data. No translation, TV changes or OwnerBridge changes. Use real observations only.")
    args=[cli,"--model",model,"--sandbox","--mode","auto","--print-timeout","240s","--output-format","stream-json","-p",prompt]
    start=time.monotonic()
    try:
        p=subprocess.run(args,env=env,cwd=run,text=True,encoding="utf-8",errors="replace",capture_output=True,timeout=270,check=False)
    except subprocess.TimeoutExpired as e:
        for name,raw in (("agy-stdout.jsonl",e.stdout),("agy-stderr.txt",e.stderr)):
            if raw is not None:
                (run/name).write_bytes(raw if isinstance(raw,bytes) else raw.encode("utf-8"))
        print("CDP9444_TIMEOUT_RESULT_UNKNOWN");sys.exit(0)
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
    allowed={"DOWNLOADED","ACCESS_DENIED","AUTH_REQUIRED","NO_MATCH","CDP_FAILED","DOWNLOAD_FAILED","OTHER"}
    status=rr.get("status","")
    if not isinstance(status,str) or status not in allowed:status="UNCLASSIFIED"
    http=rr.get("observed_http_status")
    http=str(http) if str(http) in ("200","401","403","429","503") else "NA"
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
    print(f"CDP9444_{status}_HTTP{http}_MATCH{match}_FILES{min(files,99)}_CUES{min(cues,99999)}_{round(time.monotonic()-start)}S")
except Exception:print("MCP_HEADLESS_LOCAL_ERROR")
'@
 $f=Join-Path $run 'control.py'
 [IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
 $out=@(& py -3 -I -B $f $owner $run 2> (Join-Path $run 'python-stderr.txt'))
 if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}else{$code='MCP_HEADLESS_LOCAL_ERROR'}
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
