# One paired acquisition experiment. No production, TV, cache or translation change.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0){throw 'AGY_OWNER_CONTEXT_REQUIRED'}
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$run=Join-Path $env:LOCALAPPDATA ('TorrentTVVietsub\AGYWebsiteSmoke\spiderman-ab-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop | Out-Null
$py=@'
import sys,pathlib,json,os,subprocess,time,hashlib,re
from urllib.parse import urlparse
owner,root=map(pathlib.Path,sys.argv[1:3])
app=owner/"app/poc"
sys.path[:0]=[str(app/"p2-sub-discovery"),str(app/"p2-aisub"),str(app/"p3-vietsub-trigger")]
from translator_gateway import preflight_antigravity,_validated_antigravity_alias
from matcher import parse_release
from opensubtitles import validate_timed_text
from cue_pipeline import parse_cues
prompt="""Acquire one actual existing English SRT for an owner-authorized video. Do not translate, generate, or use existing cached subtitles.
Full torrent title: Человек-паук: Новый день / Spider-Man: Brand New Day (2026) WEB-DL 1080p от селезень | D | MovieDalen.
Extract the complete international title Spider-Man: Brand New Day, year 2026, WEB-DL, 1080p, release hint селезень (selez(en)), and audio label MovieDalen. Do not confuse another Spider-Man movie. MovieDalen is not necessarily the EN subtitle release group. No invented codec or FPS.
Search normally accessible public Google/Bing indexed OpenSubtitles pages or the accessible OpenSubtitles website. Start with site:opensubtitles.org "Spider-Man Brand New Day" "2026" "1080p" "WEB-DL". Broaden query if needed. Compare actual EN subtitle release metadata; prioritize exact edition, WEB-DL 1080p, release group and FPS where available, credible uploader/download ratings. Do not substitute BluRay or another film.
Inspect an accessible selected subtitle detail page and its legitimate download link, e.g. https://dl.opensubtitles.org/en/download/file/<file-id> (pattern only, never guess IDs). Use ordinary authorized HTTP GET or browser download (curl.exe --fail --output english.srt REAL_URL or Invoke-WebRequest -Uri REAL_URL -OutFile english.srt). If a legitimate ZIP is offered, extract its matching EN SRT. Stop at login, CAPTCHA, 401 or rate/access restrictions; no circumvention, no API or API keys. Save real SRT as english.srt in the isolated current directory. Do not access other folders, cache, TV or media. Do not claim success from snippets alone. Keep content private.
Return six string fields in the provided JSON schema: status FOUND, NO_MATCH, SEARCH_BLOCKED, DOWNLOAD_BLOCKED or ERROR; release_name actual candidate; source_page actual accessible detail URL; download_url actual legitimate download URL; reason brief actual observation; file_name english.srt only if saved. Use empty strings for unavailable fields. FOUND requires a real saved file."""
fields=["status","release_name","source_page","download_url","reason","file_name"]
schema={"type":"object","properties":{k:{"type":"string"} for k in fields},"required":fields,"additionalProperties":False}
schema["properties"]["status"]["enum"]=["FOUND","NO_MATCH","SEARCH_BLOCKED","DOWNLOAD_BLOCKED","ERROR"]
def one(cli,env,model,level,label):
    run=root/label
    run.mkdir()
    (run/"prompt.txt").write_text(prompt,encoding="utf-8")
    start=time.monotonic()
    code="LOCAL_ERROR"; count=0
    try:
        _validated_antigravity_alias(model,level)
        cmd=[cli,"--input-format","stream-json","--output-format","stream-json","--json-schema",json.dumps(schema,separators=(",",":")),"--model",model,"--print-timeout","180s","--mode","auto","--sandbox"]
        message=json.dumps({"event":"user","message":{"content":prompt}},ensure_ascii=False)+"\n"
        p=subprocess.run(cmd,input=message,cwd=run,env=env,text=True,encoding="utf-8",errors="replace",capture_output=True,timeout=210,check=False)
        (run/"agy-stdout.jsonl").write_text(p.stdout,encoding="utf-8")
        (run/"agy-stderr.txt").write_text(p.stderr,encoding="utf-8")
        events=[]
        for line in p.stdout.splitlines():
            try: e=json.loads(line)
            except ValueError: continue
            if isinstance(e,dict) and e.get("event")=="result": events.append(e.get("result"))
        result=events[0] if len(events)==1 and isinstance(events[0],dict) else {}
        r=result.get("structured_output")
        # Inspect artifact independently even if provider output is malformed.
        f=run/"english.srt"
        digest=""
        if f.is_file() and not f.is_symlink() and 1000<=f.stat().st_size<=2000000:
            try:
                raw=f.read_bytes()
                q=validate_timed_text(raw,"srt")
                if q>=50 and len(parse_cues(raw,"srt"))==q:
                    count=q;digest=hashlib.sha256(raw).hexdigest()
            except Exception: pass
        if isinstance(r,str):
            try: r=json.loads(r)
            except ValueError: pass
        if p.returncode!=0: code="CLI_FAIL"
        elif result.get("status")!="SUCCESS": code="PROVIDER_FAIL"
        elif not isinstance(r,dict) or set(r)!=set(fields) or any(not isinstance(v,str) for v in r.values()): code="BAD_RESULT"
        else:
            (run/"result-private.json").write_text(json.dumps(r,ensure_ascii=False),encoding="utf-8")
            st=r["status"]
            if st in ("NO_MATCH","SEARCH_BLOCKED","DOWNLOAD_BLOCKED","ERROR"): code=st
            elif st!="FOUND": code="BAD_RESULT"
            elif count==0: code="NO_VALID_SRT"
            else:
                page=urlparse(r["source_page"]);dl=urlparse(r["download_url"])
                if not(page.scheme=="https" and page.hostname in ("opensubtitles.org","www.opensubtitles.org") and not page.username and not page.password and dl.scheme=="https" and dl.hostname in ("dl.opensubtitles.org","opensubtitles.org","www.opensubtitles.org") and not dl.username and not dl.password and r["file_name"]=="english.srt"):
                    code="BAD_PROVENANCE"
                else:
                    rls=parse_release(r["release_name"])
                    title=re.sub(r"[^a-z0-9]","",rls.title.lower())
                    match=title=="spidermanbrandnewday" and rls.year==2026 and rls.source=="web" and rls.resolution=="1080p" and re.search(r"web[ ._-]*dl",r["release_name"],re.I)
                    code="META_MATCH" if match else "RELEASE_UNVERIFIED"
        (run/"qa-private.json").write_text(json.dumps({"requested_model":model,"provider_status":result.get("status"),"result_code":code,"cues":count,"sha256":digest}),encoding="utf-8")
    except subprocess.TimeoutExpired: code="TIMEOUT"
    except Exception as e: (run/"local-error.txt").write_text(type(e).__name__+":"+str(e),encoding="utf-8")
    sec=round(time.monotonic()-start)
    return {"label":label,"code":code,"seconds":sec,"cues":count}
def main():
    cli=preflight_antigravity()
    env=dict(os.environ)
    for k in ("GEMINI_API_KEY","GOOGLE_API_KEY","GOOGLE_GEMINI_BASE_URL","AGY_ADC_AUTH","GOOGLE_CLOUD_PROJECT","GOOGLE_CLOUD_QUOTA_PROJECT"):env.pop(k,None)
    h=one(cli,env,"gemini-4-hydrogen-low","low","H")
    n=one(cli,env,"gemini-4-neon-medium","medium","N")
    (root/"comparison-private.json").write_text(json.dumps([h,n]),encoding="utf-8")
    print("_".join(f'{r["label"]}_{r["code"]}_{r["seconds"]}S_{r["cues"]}C' for r in (h,n)))
try: main()
except Exception: print("AB_PREFLIGHT_ERROR");sys.exit(1)
'@
$f=Join-Path $run 'run-test.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $owner $run 2> (Join-Path $run 'python-stderr.txt'))
$code=$LASTEXITCODE
$v=if($out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){[string]$out[0]}else{'AB_PRIVATE_ERROR'}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$v}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $v
if($code -ne 0){throw 'AB_TEST_PREFLIGHT_HOLD'}
