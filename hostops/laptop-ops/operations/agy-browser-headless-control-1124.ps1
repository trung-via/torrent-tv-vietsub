# Delegate diagnosis of the reported OpenSubtitles 403 and permitted access options.
# No bypass, global settings, credentials, or repeat of denied requests.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('agy-access-diagnosis-'+$rq.nonce)
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
            if q.get("source_commit")=="64e4df93194ca7f4b609d2b47cc213af0ddc6b53" and re.fullmatch(r"[a-f0-9]{32}",str(q.get("nonce",""))):matches.append(q)
        except Exception:pass
    if len(matches)==1:
        oldrun=run.parent/("agy-self-setup-"+matches[0]["nonce"])
        for name in ("RESULT.json","SETUP.md"):
            f=oldrun/name
            if f.is_file() and not f.is_symlink() and f.stat().st_size<=4000000:shutil.copyfile(f,prior/name)
    prompt=("Continue the authorized Torrent TV Vietsub investigation. Prior job used Playwright and reported HTTP 403 from OpenSubtitles, with zero downloaded subtitles. Read prior-diagnostics/RESULT.json and SETUP.md, if present. Identify the exact failed stage, HTTP observation versus inference, and whether the cause is explicitly stated by the site. Do not repeat requests to the denied endpoint or circumvent the denial. Research current official OpenSubtitles documentation, support and legitimate access methods, including the documented REST API as a comparison only, and ordinary website access where explicitly permitted. Use official public documentation and normal browsing; stop at any access restriction, CAPTCHA, login, payment or quota. No alternate host/proxy/fingerprint/identity intended to evade a denial, no credentials or account creation, no paid calls, no API key discovery. Prefer an authorized free unattended path compatible with existing AGY workflow; do not assume one exists. If official documentation identifies a distinct explicitly permitted no-credential workflow, you may verify that workflow once within this disposable workspace; otherwise report the requirement or limitation without retrying the blocked site. Do not change OwnerBridge, global settings or other projects. No subtitle translation or TV changes. Save SETUP.md with the recommended supported integration and official source URLs, and RESULT.json with keys status (one of PERMITTED_PATH_VERIFIED, AUTH_REQUIRED, ACCESS_DENIED, NO_VERIFIED_PATH, DOCUMENTATION_ONLY), observed_http_status, cause (observed or unknown), method, official_sources (array), actual_test and next_action. Record real observations only. If no valid permitted path exists, say so. Never fabricate results or downloads.")
    args=[cli,"--model",model,"--sandbox","--mode","auto","--print-timeout","240s","--output-format","stream-json","-p",prompt]
    start=time.monotonic()
    try:
        p=subprocess.run(args,env=env,cwd=run,text=True,encoding="utf-8",errors="replace",capture_output=True,timeout=270,check=False)
    except subprocess.TimeoutExpired as e:
        for name,raw in (("agy-stdout.jsonl",e.stdout),("agy-stderr.txt",e.stderr)):
            if raw is not None:
                (run/name).write_bytes(raw if isinstance(raw,bytes) else raw.encode("utf-8"))
        print("AGY_ACCESS_TIMEOUT_RESULT_UNKNOWN");sys.exit(0)
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
    rr={}
    try:
        rr=json.loads((run/"RESULT.json").read_text(encoding="utf-8-sig"))
        if not isinstance(rr,dict):rr={}
    except Exception:pass
    allowed={"PERMITTED_PATH_VERIFIED","AUTH_REQUIRED","ACCESS_DENIED","NO_VERIFIED_PATH","DOCUMENTATION_ONLY"}
    status=rr.get("status","")
    if not isinstance(status,str) or status not in allowed:status="UNCLASSIFIED"
    http=rr.get("observed_http_status")
    http=str(http) if str(http) in ("200","401","403","429","503") else "NA"
    sources=rr.get("official_sources",[])
    official=sum(1 for x in sources if isinstance(x,str) and re.match(r"^https://(?:[a-z0-9-]+\.)*opensubtitles\.(?:org|com)(?:/|$)",x,re.I)) if isinstance(sources,list) else 0
    print(f"AGY_ACCESS_{status}_HTTP{http}_DOC{min(official,99)}_SETUP{setup}_REPORT{report}_{round(time.monotonic()-start)}S")
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
