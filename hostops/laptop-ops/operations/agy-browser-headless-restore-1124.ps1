# One bounded headless slash-command capability test; no subtitle download or cache change.
# Browser connection must be explicitly approved by Chrome. Never auto-approve.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$profile=Join-Path $root 'ChromeProfile'
$run=Join-Path $root ('headless-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$chrome=Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'
function Roots {
 @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object {$_.CommandLine -and $_.CommandLine -notmatch '--type='})
}
$all=@(Roots)
$ch=@($all|Where-Object{$_.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0})
$code='HEADLESS_DEDICATED_CHROME_MISSING'
if($ch.Count -eq 0 -and (Test-Path -LiteralPath $profile -PathType Container) -and (Test-Path -LiteralPath $chrome -PathType Leaf)){
 Start-Process -FilePath $chrome -ArgumentList @('--user-data-dir="'+$profile+'"','--new-window','chrome://inspect/#remote-debugging')
 for($i=0;$i -lt 12;$i++){
  Start-Sleep -Milliseconds 500
  $all=@(Roots)
  $ch=@($all|Where-Object{$_.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0})
  if($ch.Count -eq 1){break}
 }
}
$all=@(Roots)
$ch=@($all|Where-Object{$_.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0})
$other=@($all|Where-Object{$_.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -lt 0})
$debugFile=Join-Path $profile 'DevToolsActivePort'
$debugReady=Test-Path -LiteralPath $debugFile -PathType Leaf
if($ch.Count -eq 1){
 if(-not $debugReady){$code='CHROME_RESTORED_DEBUG_CONSENT_REQUIRED'}
 elseif($other.Count -gt 0){$code='CHROME_RESTORED_OTHER_CHROME_PRESENT_HOLD'}
 else{$code='CHROME_RESTORED_DEBUG_MARKER_PRESENT'}
}
if($ch.Count -eq 1 -and $debugReady -and $other.Count -eq 0){
 $py=@'
import sys,pathlib,os,json,re,subprocess,time
owner,run=map(pathlib.Path,sys.argv[1:])
sys.path[:0]=[str(owner/"app/poc/p2-aisub")]
from translator_gateway import preflight_antigravity,_validated_antigravity_alias
try:
    cli=preflight_antigravity()
    model=_validated_antigravity_alias("gemini-4-hydrogen-low","low")
    env=dict(os.environ)
    for k in ("GEMINI_API_KEY","GOOGLE_API_KEY","GOOGLE_GEMINI_BASE_URL","AGY_ADC_AUTH","GOOGLE_CLOUD_PROJECT","GOOGLE_CLOUD_QUOTA_PROJECT"):env.pop(k,None)
    prompt="/browser Check ONLY the dedicated owner-authorized TorrentTV Chrome profile. If the browser is not connected to that specific profile, stop without visiting any site or inspecting tabs. Open https://www.opensubtitles.org/ through normal supported browsing and report whether the catalog/search bar is accessible. Stop on access restrictions or if approval is required; never bypass. No searching for a particular film, no download, no file edits, no credentials, no other tabs. Report whether the browser subagent actually ran and whether the page rendered."
    args=[cli,"--model",model,"--sandbox","--mode","auto","--print-timeout","90s","--output-format","stream-json","-p",prompt]
    start=time.monotonic()
    try:
        p=subprocess.run(args,env=env,cwd=run,text=True,encoding="utf-8",errors="replace",capture_output=True,timeout=120,check=False)
    except subprocess.TimeoutExpired as e:
        for name,raw in (("agy-stdout.jsonl",e.stdout),("agy-stderr.txt",e.stderr)):
            if raw is not None:
                (run/name).write_bytes(raw if isinstance(raw,bytes) else raw.encode("utf-8"))
        print("HEADLESS_TIMEOUT_RESULT_UNKNOWN");sys.exit(0)
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
    browser=bool(re.search(r'chrome-devtools|browser.subagent|spawn.{0,60}browser|\"agent_name\"\s*:\s*\"browser\"',event_text))
    if p.returncode!=0:code="CLI_FAILED"
    elif result.get("status")!="SUCCESS":code="NO_SUCCESS_RESULT"
    elif re.search(r'no (native )?browser tools|browser.{0,25}(unavailable|not available)|cannot.{0,30}browser',text):code="NO_BROWSER"
    elif re.search(r'awaiting.{0,20}approval|approval required|permission required|not connected|allow remote debugging',text):code="CONSENT_OR_CONNECTION"
    elif browser:code="BROWSER_EVENT_RECORDED"
    else:code="RESULT_REVIEW_REQUIRED"
    print("HEADLESS_"+code+"_"+str(round(time.monotonic()-start))+"S")
except Exception:print("HEADLESS_LOCAL_ERROR")
'@
 $f=Join-Path $run 'control.py'
 [IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
 $out=@(& py -3 -I -B $f $owner $run 2> (Join-Path $run 'python-stderr.txt'))
 if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}else{$code='HEADLESS_LOCAL_ERROR'}
}elseif($ch.Count -gt 1){$code='HEADLESS_PROFILE_NOT_UNIQUE'}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
