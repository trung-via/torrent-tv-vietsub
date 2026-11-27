Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'NONCE_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('NativeBrowserTest\g21-v33-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$head='f21f893c7888d031c7b5af4c1eb8628c67129f5b'
$code='G21_V33_LOCAL_ERROR'
try {
    $py=@'
import pathlib,sys,json,os,re,subprocess,shutil,urllib.request,hashlib,time
root,run,spool=map(pathlib.Path,sys.argv[1:4])
head=sys.argv[4];nonce=sys.argv[5]
def write(p,x):
    p.write_text(json.dumps(x,ensure_ascii=True,indent=2),encoding="utf-8")
def ps(cmd,timeout=15):
    return subprocess.run(["pwsh","-NoProfile","-NonInteractive","-Command",cmd],
        capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=timeout,check=True).stdout.strip()
def task_state():
    return ps("(Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -ErrorAction Stop).State.ToString()")
def busy():
    q=ps(r"""$p=@(Get-CimInstance Win32_Process | Where-Object {$_.ProcessId -ne $PID -and $_.CommandLine -and (
       ($_.Name -match '^(agy|antigravity)(\.exe)?$') -or
       ($_.Name -match '^(node|python|pythonw|py|pwsh|powershell)\.exe$' -and
        $_.CommandLine -match 'chrome-devtools-mcp|owner_p3_p4_entrypoint|owner_session_bridge|owner-p3-p4|run-owner-agent')
    )}); $p.Count""")
    return int(q.splitlines()[-1])
def pages():
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open("http://127.0.0.1:9555/json/list",timeout=3) as f:
        return [p for p in json.load(f) if p.get("type")=="page"]
def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else "MISSING"
def main():
    # Checkout only exact source, no installed application writes.
    checkout=run/"candidate";checkout.mkdir()
    env=dict(os.environ,GIT_TERMINAL_PROMPT="0",GCM_INTERACTIVE="never")
    git=shutil.which("git")
    if not git:return "G21_V33_GIT_UNAVAILABLE"
    def g(*a):
        p=subprocess.run([git,*a],cwd=checkout,env=env,capture_output=True,text=True,
            encoding="utf-8",errors="replace",timeout=60)
        with (run/"git-private.txt").open("a",encoding="utf-8") as f:f.write(p.stdout+"\n"+p.stderr+"\n")
        if p.returncode:raise RuntimeError("GIT_"+a[0].upper())
        return p.stdout.strip()
    try:
        g("init","-q");g("fetch","--depth=1","--no-tags","https://github.com/trung-via/torrent-tv-vietsub.git",head)
        if g("rev-parse","FETCH_HEAD")!=head:return "G21_V33_SOURCE_DRIFT"
        g("checkout","--detach","FETCH_HEAD")
        if g("rev-parse","HEAD")!=head:return "G21_V33_SOURCE_DRIFT"
    except (RuntimeError,subprocess.TimeoutExpired):return "G21_V33_SOURCE_FETCH_HOLD"
    sys.path[:0]=[str(checkout/"poc/p2-sub-discovery"),str(checkout/"poc/p2-aisub")]
    from owner_g2_submit import submit_private_file
    from owner_session_bridge import poll_private_g2
    from agy_v13_native_producer import NativeBrowserProducer
    # Real writer publication in isolated owner inbox, no live Owner effect.
    private=run/"isolated-owner";private.mkdir()
    payload={"schema":"TTV-OWNER-G2-METADATA-V1","request_id":nonce,
       "authorized_source":True,"source_url":"https://www.sunpictures.in/?sunpict_movies=jailer2",
       "queries":[{"title":"Jailer 2","year":2026},{"title":"Jailer 2","year":2026}]}
    req=run/"private-request.json";write(req,payload)
    first=submit_private_file(private,req);second=submit_private_file(private,req)
    event=private/"inbox"/("g2-"+nonce+".json")
    if first!=nonce or second!=nonce or not event.is_file():return "G21_V33_WRITER_HOLD"
    # Record structural prior evidence only; no model call here.
    preflight={"head":head,"writer_idempotent":True,"owner_task":task_state(),"busy_count":busy()}
    try:
        before=pages()
        preflight["pages"]=len(before)
        preflight["baseline_opensubtitles"]=sum(urllib.parse.urlsplit(p.get("url","")).hostname in ("opensubtitles.org","www.opensubtitles.org") for p in before)
    except Exception:
        before=[];preflight["pages"]=-1
    write(run/"PREFLIGHT.json",preflight)
    # Never overlap a live Owner, never close other tabs or reset a profile.
    # Do not submit to the installed Owner: candidate is not deployed.
    if preflight["owner_task"].upper() not in ("READY","DISABLED"):
        return "G21_V33_WRITER_PASS_OWNER_ACTIVE"
    if preflight["busy_count"]:return "G21_V33_WRITER_PASS_BROWSER_BUSY"
    if preflight.get("pages")!=1 or preflight.get("baseline_opensubtitles")!=1:
        return "G21_V33_WRITER_PASS_BASE_TAB_HOLD_"+str(max(0,preflight["pages"]))
    # Require no existing browser claims anywhere in this project's local state.
    # A live/unknown prior effect cannot be reconciled by this isolated test.
    for parent in (root/"P2",root/"OwnerBridge"):
        if parent.is_dir() and any(parent.rglob("browser.pending")):
            return "G21_V33_WRITER_PASS_PRIOR_CLAIM"
    if task_state().upper() not in ("READY","DISABLED") or busy():
        return "G21_V33_WRITER_PASS_STATE_CHANGED"
    profile=root/"NativeBrowserTest"/"CDP9555Profile"
    # Use the known shared P2 cache only if verified from the scheduled task
    # action/launcher. For this isolated acceptance, the task must be stopped,
    # and its schedule disabled (READY could launch during the test).
    if task_state().upper()!="DISABLED":return "G21_V33_WRITER_PASS_OWNER_ARMED"
    cache=run/"isolated-cache";cache.mkdir()
    producer=NativeBrowserProducer(profile=profile,probe=lambda _:None)
    conf=[pathlib.Path.home()/".gemini/antigravity-cli/settings.json",
          pathlib.Path.home()/".gemini/config/config.json",
          pathlib.Path.home()/".gemini/config/mcp_config.json"]
    hashes=[digest(p) for p in conf]
    log=[]
    started=time.monotonic()
    n=poll_private_g2(owner_root=private,cache_root=cache,discover=producer.discover_movies,
                      submit=lambda work:work(),emit=log.append)
    elapsed=round((time.monotonic()-started)*1000)
    receipt=private/"inbox"/("g2-"+nonce+".receipt.json")
    if n!=1 or not receipt.is_file():return "G21_V33_CONSUMER_RECEIPT_MISSING"
    result=json.loads(receipt.read_text("utf-8"))
    if hashes!=[digest(p) for p in conf]:return "G21_V33_GLOBAL_CONFIG_CHANGED"
    try:restored={p["id"]:p["url"] for p in pages()}=={p["id"]:p["url"] for p in before}
    except Exception:restored=False
    repeated=poll_private_g2(owner_root=private,cache_root=cache,discover=producer.discover_movies,
                             submit=lambda work:work(),emit=log.append)
    write(run/"ACCEPTANCE.json",{"head":head,"receipt":result,"restored":restored,"duplicate_count":repeated,"total_ms":elapsed})
    if result.get("request_id")!=nonce or repeated!=0:return "G21_V33_IDENTITY_HOLD"
    if not restored:return "G21_V33_RESTORE_HOLD"
    if result.get("status")!="COMPLETE":return "G21_V33_CONSUMER_"+str(result.get("status","UNKNOWN"))
    rows=result.get("results",[])
    if len(rows)!=2:return "G21_V33_PARTIAL"
    if not all(row.get("status")=="MATCH_FOUND" and row.get("candidates") for row in rows):
        return "G21_V33_HANDOFF_PASS_METADATA_UNVERIFIED"
    return "G21_V33_HANDOFF_PASS_C"+str(rows[0]["timing"]["final_ms"])+"_W"+str(rows[1]["timing"]["final_ms"])
try:
    import urllib.parse
    print(main())
except Exception as exc:
    import traceback
    (run/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("G21_V33_LOCAL_ERROR")
'@
    $f=Join-Path $run 'v33.py'
    [IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
    $out=@(& py -3 -I -B $f $root $run $spool $head $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
    if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
} catch {
    [IO.File]::WriteAllText((Join-Path $run 'host-private-error.txt'),($_|Out-String),[Text.UTF8Encoding]::new($false))
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
