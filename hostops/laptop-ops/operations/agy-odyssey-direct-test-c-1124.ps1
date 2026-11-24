# One owner-approved AGY direct download test C, isolated from live TV/cache.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0){throw 'AGY_OWNER_CONTEXT_REQUIRED'}
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$run=Join-Path $env:LOCALAPPDATA ('TorrentTVVietsub\AGYWebsiteSmoke\direct-c-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop | Out-Null
$py=@'
import sys, pathlib, json, os, subprocess, time, hashlib, re
from urllib.parse import urlparse
owner,run=map(pathlib.Path,sys.argv[1:3])
app=owner/"app/poc"
sys.path[:0]=[str(app/"p2-sub-discovery"),str(app/"p2-aisub"),str(app/"p3-vietsub-trigger")]
from translator_gateway import preflight_antigravity,_validated_antigravity_alias
from lean120_api import load_profile
from matcher import parse_release
from opensubtitles import validate_timed_text
from cue_pipeline import parse_cues
def require(v,msg):
    if not v: raise ValueError(msg)
def main():
    profile=load_profile(app/"p2-aisub/translator_profile.json")
    model=_validated_antigravity_alias(profile.model,profile.thinking_level)
    cli=preflight_antigravity()
    env=dict(os.environ)
    for k in ("GEMINI_API_KEY","GOOGLE_API_KEY","GOOGLE_GEMINI_BASE_URL","AGY_ADC_AUTH","GOOGLE_CLOUD_PROJECT","GOOGLE_CLOUD_QUOTA_PROJECT"): env.pop(k,None)
    prompt="""TEST C: one isolated download-only experiment. The owner supplies this previously verified legitimate direct file URL: https://dl.opensubtitles.org/en/download/file/1962752152 . No website search, API, SDK, credentials or existing files. This is a publicly accessible download link previously observed, not permission to bypass any access restriction. Use ordinary HTTP GET with an available authorized tool (for example curl.exe --fail --output english.srt URL or Invoke-WebRequest -Uri URL -OutFile english.srt), respecting the service terms. If redirected to authentication, challenge, or denied/rate-limited, stop and report the actual status; never change identity, evade access controls, or attempt a different endpoint. Save the downloaded bytes exactly, unmodified, to english.srt in the current working directory. Do not read cache, translate, synthesize or edit the subtitle. Do not touch any other folder, TV or TorrServer. Report status FOUND, DOWNLOAD_BLOCKED or ERROR; release_name The Odyssey (2026) AMZN WEB-DL 1080p H.264-KyoGo, source_page https://www.opensubtitles.org/en/subtitles/14190981/the-odyssey-en, download_url the exact supplied URL, reason actual observation including HTTP status if available, file_name english.srt only when actually saved. Do not claim FOUND without a real downloaded file. Return only structured output."""
    fields=["status","release_name","source_page","download_url","reason","file_name"]
    schema={"type":"object","properties":{k:{"type":"string"} for k in fields},"required":fields,"additionalProperties":False}
    schema["properties"]["status"]["enum"]=["FOUND","DOWNLOAD_BLOCKED","ERROR"]
    (run/"prompt.txt").write_text(prompt,encoding="utf-8")
    cmd=[cli,"--input-format","stream-json","--output-format","stream-json","--json-schema",json.dumps(schema,separators=(",",":")),"--model",model,"--print-timeout","180s","--mode","auto","--sandbox"]
    message=json.dumps({"event":"user","message":{"content":prompt}},ensure_ascii=False)+"\n"
    try:
        p=subprocess.run(cmd,input=message,cwd=run,env=env,text=True,encoding="utf-8",errors="replace",capture_output=True,timeout=210,check=False)
    except subprocess.TimeoutExpired as e:
        (run/"agy-timeout.txt").write_text(str(e),encoding="utf-8")
        raise ValueError("AGY_DIRECT_TIMEOUT_RESULT_UNKNOWN")
    (run/"agy-stdout.jsonl").write_text(p.stdout,encoding="utf-8")
    (run/"agy-stderr.txt").write_text(p.stderr,encoding="utf-8")
    require(p.returncode==0,"AGY_DIRECT_CLI_FAILED")
    results=[]
    for line in p.stdout.splitlines():
        try: event=json.loads(line)
        except ValueError: continue
        if isinstance(event,dict) and event.get("event")=="result": results.append(event.get("result"))
    require(len(results)==1 and isinstance(results[0],dict),"AGY_DIRECT_RESULT_MISSING")
    require(results[0].get("status")=="SUCCESS","AGY_DIRECT_PROVIDER_FAILED")
    r=results[0].get("structured_output")
    require(isinstance(r,dict) and set(r)==set(fields) and all(isinstance(v,str) for v in r.values()),"AGY_DIRECT_RESULT_INVALID")
    (run/"result-private.json").write_text(json.dumps(r,ensure_ascii=False),encoding="utf-8")
    if r["status"]!="FOUND":
        require(r["status"] in ("DOWNLOAD_BLOCKED","ERROR"),"AGY_DIRECT_RESULT_INVALID")
        raise ValueError("AGY_DIRECT_"+r["status"])
    require(r["file_name"]=="english.srt","AGY_DIRECT_FILENAME_INVALID")
    require(r["download_url"]=="https://dl.opensubtitles.org/en/download/file/1962752152","AGY_DIRECT_URL_MISMATCH")
    f=run/"english.srt"
    require(f.is_file() and not f.is_symlink() and 1000<=f.stat().st_size<=2000000,"AGY_DIRECT_NO_VALID_FILE")
    raw=f.read_bytes()
    count=validate_timed_text(raw,"srt")
    require(count>=50 and len(parse_cues(raw,"srt"))==count,"AGY_DIRECT_SRT_INVALID")
    digest=hashlib.sha256(raw).hexdigest()
    exact=count==2009 and digest=="d04a47b307ef6618ad8c8de406ec0dfcfba8b495509c32a3b6fbf76b40185932"
    (run/"qa-private.json").write_text(json.dumps({"sha256":digest,"cues":count,"bytes":len(raw),"exact":exact}),encoding="utf-8")
    print(("AGY_DIRECT_EXACT_PASS" if exact else "AGY_DIRECT_VALID_DIFFERENT_BYTES")+"_CUES_"+str(count))
    if not exact: sys.exit(2)
try: main()
except Exception as e:
    v=str(e)
    print(v if re.fullmatch(r"AGY_[A-Z0-9_]{2,85}",v) else "AGY_DIRECT_LOCAL_ERROR")
    sys.exit(1)
'@
$f=Join-Path $run 'run-test.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $owner $run 2> (Join-Path $run 'python-stderr.txt'))
$code=$LASTEXITCODE
$v=if($out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){[string]$out[0]}else{'AGY_DIRECT_PRIVATE_ERROR'}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$v}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $v
if($code -ne 0){throw 'AGY_DIRECT_TEST_HOLD'}
