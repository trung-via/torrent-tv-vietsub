# Bounded unattended MCP-launched isolated Chrome capability probe.
# No attachment to existing browser, no global settings, no approval automation.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('mcp-search-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='MCP_LOCAL_ERROR'
if($true){
 $py=@'
import sys,pathlib,os,json,re,subprocess,time,shutil,zipfile
owner,run=map(pathlib.Path,sys.argv[1:])
sys.path[:0]=[str(owner/"app/poc/p2-aisub")]
from translator_gateway import preflight_antigravity,_validated_antigravity_alias
try:
    cli=preflight_antigravity()
    model=_validated_antigravity_alias("gemini-4-hydrogen-low","low")
    env=dict(os.environ)
    for k in ("GEMINI_API_KEY","GOOGLE_API_KEY","GOOGLE_GEMINI_BASE_URL","AGY_ADC_AUTH","GOOGLE_CLOUD_PROJECT","GOOGLE_CLOUD_QUOTA_PROJECT"):env.pop(k,None)
    npx=shutil.which("npx.cmd") or shutil.which("npx")
    if not npx:
        print("MCP_NPX_MISSING");sys.exit(0)
    downloads=run/"downloads"
    downloads.mkdir()
    profile=run/"chrome-profile"
    (profile/"Default").mkdir(parents=True)
    (profile/"Default"/"Preferences").write_text(json.dumps({"download":{"default_directory":str(downloads),"prompt_for_download":False}}),encoding="utf-8")
    config=run/".agents"
    config.mkdir()
    (config/"mcp_config.json").write_text(json.dumps({"mcpServers":{"torrent-tv-chrome":{"command":"cmd.exe","args":["/d","/c","npx","-y","chrome-devtools-mcp@latest","--headless","--user-data-dir="+str(profile),"--no-usage-statistics","--log-file="+str(run/"mcp-debug.log")]}}}),encoding="utf-8")
    prompt="Use only the configured torrent-tv-chrome MCP server and its browser tools, not /browser auto-connect, APIs, shell or other profiles. Open https://www.opensubtitles.org/ normally. Search Spider-Man: Brand New Day (2026), English subtitle, WEB-DL 1080p, matching selezen release and MovieDalen audio label when applicable. Verify actual release metadata, do not guess or substitute a different movie or release. If a matching result is available and permitted, download one file using the normal site download control to the isolated browser download directory. Do not bypass access restrictions, login, CAPTCHA or quota; stop if any occur. No other sites or files. Report actual page access, match and download status, even on failure. Do not claim success without tool results."
    args=[cli,"--model",model,"--sandbox","--mode","auto","--print-timeout","180s","--output-format","stream-json","-p",prompt]
    start=time.monotonic()
    try:
        p=subprocess.run(args,env=env,cwd=run,text=True,encoding="utf-8",errors="replace",capture_output=True,timeout=210,check=False)
    except subprocess.TimeoutExpired as e:
        for name,raw in (("agy-stdout.jsonl",e.stdout),("agy-stderr.txt",e.stderr)):
            if raw is not None:
                (run/name).write_bytes(raw if isinstance(raw,bytes) else raw.encode("utf-8"))
        print("MCP_HEADLESS_TIMEOUT_RESULT_UNKNOWN");sys.exit(0)
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
    def visit(x):
        if isinstance(x,dict):
            yield x
            for v in x.values():yield from visit(v)
        elif isinstance(x,list):
            for v in x:yield from visit(v)
    ev=[x for x in records if x.get("event") not in ("user","result","assistant")]
    names=[str(v).lower() for x in visit(ev) for k,v in x.items() if k.lower() in ("name","tool_name","toolname","step_type") and isinstance(v,str)]
    nav=int(any("navigate_page" in v for v in names))
    snap=int(any("take_snapshot" in v for v in names))
    rawlog=run/"mcp-debug.log"
    log=int(rawlog.is_file() and rawlog.stat().st_size>0)
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
    print(f"MCP_SEARCH_{out}_NAV{nav}_SNAP{snap}_LOG{log}_FILES{min(files,99)}_CUES{min(cues,99999)}_{round(time.monotonic()-start)}S")
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
