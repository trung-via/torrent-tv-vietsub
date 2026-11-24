# Bounded unattended MCP-launched isolated Chrome capability probe.
# No attachment to existing browser, no global settings, no approval automation.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('mcp-headless-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='MCP_LOCAL_ERROR'
if($true){
 $py=@'
import sys,pathlib,os,json,re,subprocess,time,shutil
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
    config=run/".agents"
    config.mkdir()
    (config/"mcp_config.json").write_text(json.dumps({"mcpServers":{"torrent-tv-chrome":{"command":"cmd.exe","args":["/d","/c","npx","-y","chrome-devtools-mcp@latest","--headless","--isolated","--no-usage-statistics"]}}}),encoding="utf-8")
    prompt="Use ONLY the configured torrent-tv-chrome MCP server, not /browser, shell, HTTP requests, APIs, other browsers or profiles. Navigate to https://www.opensubtitles.org/ and use its snapshot tool to inspect the rendered page. If the server is unavailable, asks approval, or the site denies access, stop and report the reason. Do not bypass restrictions. No login, no downloads, no edits, no access to other tabs or user files. Report whether navigate_page and take_snapshot actually succeeded and whether the catalog/search control is visible."
    args=[cli,"--model",model,"--sandbox","--mode","auto","--print-timeout","120s","--output-format","stream-json","-p",prompt]
    start=time.monotonic()
    try:
        p=subprocess.run(args,env=env,cwd=run,text=True,encoding="utf-8",errors="replace",capture_output=True,timeout=150,check=False)
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
    # Classify actual event metadata and final report separately, not prompt text.
    ev=[x for x in records if x.get("event") not in ("user","result")]
    event_text=json.dumps(ev,ensure_ascii=False).lower()
    text=json.dumps(result,ensure_ascii=False).lower()
    # Require explicit MCP tool names and result-event evidence, not only prose.
    browser=bool(re.search(r"torrent[-_]tv[-_]chrome",event_text) and re.search(r"navigate_page",event_text) and re.search(r"take_snapshot",event_text) and re.search(r"tool_result|tool_response|toolresult|tool_call_end",event_text))
    if p.returncode!=0:code="CLI_FAILED"
    elif result.get("status")!="SUCCESS":code="NO_SUCCESS_RESULT"
    elif re.search(r'no (native )?browser tools|browser.{0,25}(unavailable|not available)|cannot.{0,30}browser',text):code="NO_BROWSER"
    elif re.search(r'awaiting.{0,20}approval|approval required|permission required|not connected|allow remote debugging',text):code="CONSENT_OR_CONNECTION"
    elif browser:code="NAV_SNAPSHOT_EVENTS_RECORDED"
    else:code="RESULT_REVIEW_REQUIRED"
    print("MCP_HEADLESS_"+code+"_"+str(round(time.monotonic()-start))+"S")
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
