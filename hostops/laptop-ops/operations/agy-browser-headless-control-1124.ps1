# Delegate unattended browser setup and verification to AGY in a disposable workspace.
# No existing profile attachment, global configuration, or automated consent.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('agy-self-setup-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='MCP_LOCAL_ERROR'
if($true){
 $py=@'
import sys,pathlib,os,json,re,subprocess,time,shutil,zipfile,http.server,threading,secrets
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
    prior=run/"prior-diagnostics"
    prior.mkdir()
    history=pathlib.Path(os.environ["ProgramData"])/"TorrentTVVietsub"/"LaptopHostOps"/"History"
    matches=[]
    for f in history.glob("receipt-*.json"):
        try:
            if f.is_symlink() or f.stat().st_size>2048:continue
            q=json.loads(f.read_text(encoding="utf-8-sig"))
            if q.get("source_commit")=="44df3b78bf1c22d2fb566d51a12fd74d0600a0aa" and re.fullmatch(r"[a-f0-9]{32}",str(q.get("nonce",""))):matches.append(q)
        except Exception:pass
    if len(matches)==1:
        oldrun=run.parent/("mcp-search-"+matches[0]["nonce"])
        for name in ("mcp-debug.log","agy-stdout.jsonl","agy-stderr.txt"):
            f=oldrun/name
            if f.is_file() and not f.is_symlink() and f.stat().st_size<=4000000:shutil.copyfile(f,prior/name)
    token=secrets.token_hex(16)
    visits=[]
    fixture_path="/"+token+"/fixture"
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self,*args):pass
        def do_GET(self):
            if self.path!=fixture_path:
                self.send_error(404);return
            visits.append(self.headers.get("User-Agent",""))
            body=b"<html><title>Torrent TV browser smoke</title><body>Browser fixture is ready.</body></html>"
            self.send_response(200);self.send_header("Content-Type","text/html");self.send_header("Content-Length",str(len(body)));self.end_headers();self.wfile.write(body)
    srv=http.server.ThreadingHTTPServer(("127.0.0.1",0),Handler)
    thread=threading.Thread(target=srv.serve_forever,daemon=True)
    thread.start()
    fixture=f"http://127.0.0.1:{srv.server_port}{fixture_path}"
    prompt=("You are the engineering executor for Torrent TV Vietsub. Own the solution, not just a report. Diagnose the previous browser attempt using prior-diagnostics in this workspace, inspect installed tool help and supported AGY configuration, then configure and test a repeatable unattended browser acquisition path yourself. Choose the simplest supported technique; you may use local scripts, workspace MCP config, an isolated Chrome launched with supported local automation or another normal browser mechanism. You may create/edit files and install dependencies only inside this disposable workspace; no global AGY/Chrome/Windows settings, credentials, existing browser profiles, system services, OwnerBridge, other repositories, or other user files. Do not auto-click or bypass approval prompts, site restrictions, CAPTCHA, login, rate limits or access controls. The goal is no human approval at runtime using a supported isolated browser startup. First open the local smoke page in the actual isolated browser (not via curl, HTTP client or spoofed headers): "+fixture+". Then, if the normal website permits access, find the correct English subtitle for Spider-Man: Brand New Day (2026), WEB-DL 1080p, matching selezen release and MovieDalen audio label when applicable, on https://www.opensubtitles.org/ and download one genuinely matching file into downloads/. Do not guess or substitute a release or claim a fabricated download. Stop if site denies access. Save the reusable workspace setup/invocation instructions as SETUP.md and concise diagnosis and actual observations as RESULT.json. Clearly distinguish working browser from site access and artifact. Use real tool outputs and verify your work. No translation or TV changes.")
    args=[cli,"--model",model,"--sandbox","--mode","auto","--print-timeout","240s","--output-format","stream-json","-p",prompt]
    start=time.monotonic()
    try:
        p=subprocess.run(args,env=env,cwd=run,text=True,encoding="utf-8",errors="replace",capture_output=True,timeout=270,check=False)
    except subprocess.TimeoutExpired as e:
        for name,raw in (("agy-stdout.jsonl",e.stdout),("agy-stderr.txt",e.stderr)):
            if raw is not None:
                (run/name).write_bytes(raw if isinstance(raw,bytes) else raw.encode("utf-8"))
        srv.shutdown();srv.server_close()
        print("AGY_SETUP_TIMEOUT_RESULT_UNKNOWN");sys.exit(0)
    srv.shutdown();srv.server_close()
    browser_visit=int(any("Chrome/" in ua or "Chromium/" in ua or "Firefox/" in ua or "Edg/" in ua for ua in visits))
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
    setup=int((run/"SETUP.md").is_file() and (run/"SETUP.md").stat().st_size>20)
    report=int((run/"RESULT.json").is_file() and (run/"RESULT.json").stat().st_size>10)
    cues=0
    files=0
    for f in downloads.iterdir():
        if f.is_file() and not f.is_symlink() and f.stat().st_size<=10000000 and f.suffix.lower() in (".srt",".zip"):
            files+=1
            try:
                if f.suffix.lower()==".srt":
                    blobs=[f.read_bytes()]
                else:
                    with zipfile.ZipFile(f) as z:
                        members=[i for i in z.infolist() if i.filename.lower().endswith(".srt") and i.file_size<=2000000]
                        blobs=[z.read(i) for i in members[:5]]
                for data in blobs:
                    n=len(re.findall(rb"(?m)^\d{2}:\d{2}:\d{2},\d{3}\s+-->\s+\d{2}:\d{2}:\d{2},\d{3}",data))
                    cues=max(cues,n)
            except Exception:pass
    text=json.dumps(result,ensure_ascii=False).lower()
    if re.search(r"captcha|access denied|403 forbidden|cloudflare challenge|rate.limit|login required",text):out="BLOCKED_REPORTED"
    elif re.search(r"approval required|permission required|allow remote debugging",text):out="CONSENT_REPORTED"
    elif cues>=50:out="ARTIFACT_PRESENT"
    elif p.returncode!=0:out="CLI_FAILED"
    else:out="NO_VALID_ARTIFACT"
    print(f"AGY_SETUP_{out}_BROWSER{browser_visit}_SETUP{setup}_REPORT{report}_FILES{min(files,99)}_CUES{min(cues,99999)}_{round(time.monotonic()-start)}S")
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
