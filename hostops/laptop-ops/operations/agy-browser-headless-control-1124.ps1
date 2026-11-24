# Dedicated Torrent TV Chrome CDP 9555 startup and local AGY browser fixture.
# No external provider requests or modifications to the 9444 profile.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('agy-cdp9555-'+$rq.nonce)
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
import sys,pathlib,os,json,re,subprocess,time,urllib.request,http.server,threading,secrets,hashlib
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
    token=secrets.token_hex(16)
    route="/"+token
    visits=[]
    content=b"1\r\n00:00:01,000 --> 00:00:02,000\r\nTorrent TV fixture only.\r\n"
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self,*args):pass
        def do_GET(self):
            if self.path==route:
                data=("<html><title>TTV CDP9555 fixture</title><a download='fixture.srt' href='"+route+"/download'>Download fixture</a></html>").encode()
                kind="text/html"
                visits.append(("page",self.headers.get("User-Agent","")))
            elif self.path==route+"/download":
                data=content
                kind="application/x-subrip"
                visits.append(("download",self.headers.get("User-Agent","")))
            else:
                self.send_error(404);return
            self.send_response(200);self.send_header("Content-Type",kind)
            if kind!="text/html":self.send_header("Content-Disposition",'attachment; filename="fixture.srt"')
            self.send_header("Content-Length",str(len(data)));self.end_headers();self.wfile.write(data)
    srv=http.server.ThreadingHTTPServer(("127.0.0.1",0),Handler)
    threading.Thread(target=srv.serve_forever,daemon=True).start()
    fixture=f"http://127.0.0.1:{srv.server_port}{route}"
    prompt=("You are the Torrent TV AGY executor. Verify the dedicated Chrome profile already started by HostOps at http://127.0.0.1:9555. Use any supported CDP client, preferably Playwright. Connect only to 9555, open a new tab, navigate to "+fixture+", verify the title, click the normal Download fixture link, and save the actual file via browser download to downloads/fixture.srt. Do not fake the request or file, use curl/HTTP clients for the fixture, or touch port 9444, existing tabs, other profiles, user data, accounts or global settings. No external sites or provider calls: OpenSubtitles authorization remains unresolved. You may write scripts/install dependencies only in this workspace. Close only your new tab and disconnect without closing the browser. Save SETUP.md with reproducible commands and RESULT.json with the method and actual results. Do not use or auto-accept permission prompts. If a prompt or access restriction occurs, stop and report. No OwnerBridge changes.")
    args=[cli,"--model",model,"--sandbox","--mode","auto","--print-timeout","240s","--output-format","stream-json","-p",prompt]
    start=time.monotonic()
    try:
        p=subprocess.run(args,env=env,cwd=run,text=True,encoding="utf-8",errors="replace",capture_output=True,timeout=270,check=False)
    except subprocess.TimeoutExpired as e:
        for name,raw in (("agy-stdout.jsonl",e.stdout),("agy-stderr.txt",e.stderr)):
            if raw is not None:
                (run/name).write_bytes(raw if isinstance(raw,bytes) else raw.encode("utf-8"))
        srv.shutdown();srv.server_close()
        print("CDP9555_TIMEOUT_RESULT_UNKNOWN");sys.exit(0)
    srv.shutdown();srv.server_close()
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
    page=int(any(kind=="page" and "Chrome/" in ua for kind,ua in visits))
    download=int(any(kind=="download" and "Chrome/" in ua for kind,ua in visits))
    file=downloads/"fixture.srt"
    matched=int(file.is_file() and not file.is_symlink() and file.stat().st_size==len(content) and hashlib.sha256(file.read_bytes()).digest()==hashlib.sha256(content).digest())
    setup=int((run/"SETUP.md").is_file())
    report=int((run/"RESULT.json").is_file())
    print(f"CDP9555_LOCAL_PAGE{page}_DOWNLOAD{download}_HASH{matched}_SETUP{setup}_REPORT{report}_RC{int(p.returncode==0)}_{round(time.monotonic()-start)}S")
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
