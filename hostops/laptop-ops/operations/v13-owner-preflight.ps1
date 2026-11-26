# G1.3 read-only Owner environment preflight. No model, provider, playback, install, or restart.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$run=Join-Path $root ('v13-owner-preflight-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$o=0;$b=0
try {
 $task=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'
 if([string]$task.State -eq 'Running'){$o=1}
} catch {}
try {
 $profile=Join-Path $root 'CDP9555Profile'
 $ls=@(Get-NetTCPConnection -LocalPort 9555 -State Listen -ErrorAction Stop)
 $pids=@($ls|Select-Object -ExpandProperty OwningProcess -Unique)
 if($pids.Count -eq 1 -and @($ls|Where-Object {$_.LocalAddress -notin @('127.0.0.1','::1')}).Count -eq 0){
  $p=Get-CimInstance Win32_Process -Filter ('ProcessId='+$pids[0])
  if($p.Name -eq 'chrome.exe' -and $p.CommandLine -and $p.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0 -and $p.CommandLine -match '(?:^|\s|")--remote-debugging-port=9555(?:\s|"|\z)'){$b=1}
 }
} catch {}
$py=@'
import sys,pathlib,json,time,re,math,shutil,subprocess,os
from urllib.request import build_opener,ProxyHandler,HTTPRedirectHandler
from urllib.parse import urlsplit
from fractions import Fraction
owner,root,spool,run=map(pathlib.Path,sys.argv[1:5])
sys.path[:0]=[str(owner/"app/poc/p2-aisub"),str(owner/"app/poc/p2-sub-discovery")]
def obj(p):
    if not p.is_file() or p.is_symlink() or not 0<p.stat().st_size<=16777216:raise ValueError("file")
    return json.loads(p.read_text(encoding="utf-8-sig"))
x={k:0 for k in ("H","P","A","S","D","T","F","M","I","N","U")}
try:
    from owner_session_bridge import read_owner_agent_health
    x["H"]=int(read_owner_agent_health(owner_root=owner)=="READY")
    if x["H"]:
        health=obj(owner/"agent-health.json")
        pid=health["pid"]
        q=subprocess.run(["pwsh","-NoProfile","-NonInteractive","-Command","if(Get-Process -Id "+str(int(pid))+" -ErrorAction SilentlyContinue){exit 0}else{exit 1}"],capture_output=True,timeout=10)
        x["P"]=int(q.returncode==0)
except Exception:pass
try:
    from translator_gateway import preflight_antigravity
    cli=preflight_antigravity()
    x["A"]=1
    env=dict(os.environ,TTV_AGY_CLI=str(cli))
    q=subprocess.run(["pwsh","-NoProfile","-NonInteractive","-Command","& $env:TTV_AGY_CLI --help; exit $LASTEXITCODE"],env=env,capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=20)
    x["S"]=int(q.returncode==0 and re.search(r"(?m)^\s*--?settings(?:[ =\t]|$)",q.stdout+q.stderr) is not None)
except Exception:pass
try:
    class NoRedirect(HTTPRedirectHandler):
        def redirect_request(self,*args):return None
    op=build_opener(ProxyHandler({}),NoRedirect())
    def local(path):
        with op.open("http://127.0.0.1:9555"+path,timeout=3) as f:return json.loads(f.read(65536))
    v=local("/json/version")
    x["D"]=int(str(v.get("Browser","")).startswith("Chrome/") and str(v.get("webSocketDebuggerUrl","")).startswith("ws://127.0.0.1:9555/"))
    pages=[p for p in local("/json/list") if p.get("type")=="page"]
    if len(pages)==1:
        u=urlsplit(pages[0].get("url",""))
        x["T"]=int(u.scheme=="https" and u.hostname in ("opensubtitles.org","www.opensubtitles.org") and not re.search(r"captcha|access denied|just a moment|making sure you.re not a bot",pages[0].get("title","")+" "+pages[0].get("url",""),re.I))
except Exception:pass
# Reconcile only the retained, previously selected BT24H fixture. No new selection.
try:
    src="29c8dac83ed663b137a39c666d242258cd93c848"
    receipts=[]
    for p in (spool/"History").glob("receipt-*.json"):
        q=obj(p)
        if q.get("source_commit")==src and q.get("result")=="SUCCESS" and re.fullmatch(r"[a-f0-9]{32}",str(q.get("nonce",""))):receipts.append(q["nonce"])
    if len(receipts)!=1:raise ValueError("fixture receipt")
    f=obj(root/("bt24-human-fixture-preflight-"+receipts[0])/"BRAIN_HUMAN_FIXTURE.json")
    if f.get("schema")!="BT10_HUMAN_FIXTURE_V1" or f.get("exact_file_verified") is not True:raise ValueError("fixture")
    x["I"]={"FFP":1,"FFPROBE":2}.get(f.get("probe"),0)
    from owner_torrserver_readonly import OwnerLocalTorrServer,OwnerTorrServerReader
    from owner_torrserver_ffp_tracks import _read_local_ffp
    policy=obj(owner/"p3-p4-policy.json")
    cfg=OwnerLocalTorrServer(policy["profile_id"],policy["torrserver_port"])
    tor,idx=f["hash"],f["file_index"]
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}",tor) or type(idx) is not int or not 0<=idx<4096:raise ValueError("identity")
    actual=OwnerTorrServerReader(cfg)(cfg.profile_id,tor,idx)
    if actual.path.replace("\\","/").rsplit("/",1)[-1]!=f["filename"] or actual.length!=f["size_bytes"]:raise ValueError("identity changed")
    x["F"]=1
    raw=_read_local_ffp(f"http://127.0.0.1:{cfg.localhost_port}/ffp/{tor}/{idx}",8.0)
    doc=json.loads(raw)
    tracks=[v for v in doc["streams"] if v["codec_type"]=="video" and not v.get("disposition",{}).get("attached_pic")]
    duration=float(doc["format"]["duration"])
    fps=float(Fraction(tracks[0]["avg_frame_rate"]))
    x["M"]=int(len(tracks)==1 and math.isfinite(duration) and math.isfinite(fps) and 0<duration<=86400 and 0<fps<=240)
    x["U"]=int(x["M"] and abs(duration-float(f["duration_seconds"]))<=2 and abs(fps-float(f["fps"]))<=0.01)
except Exception:pass
# File presence only, not a claim of loaded code or matching hash.
x["N"]=int(all((owner/"app/poc/p2-sub-discovery"/n).is_file() for n in ("agy_v13_native_producer.py","agy_v13_browser_evidence.py")))
(run/"preflight.json").write_text(json.dumps(x,sort_keys=True),encoding="utf-8")
print("".join(k+str(v) for k,v in x.items()))
'@
$file=Join-Path $run 'preflight.py'
[IO.File]::WriteAllText($file,$py,[Text.UTF8Encoding]::new($false))
$lines=@(& py -3 -I -B $file $owner $root $spool $run 2> (Join-Path $run 'stderr.txt'))
$code='V13_PREFLIGHT_PRIVATE_ERROR'
if($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and [string]$lines[0] -cmatch '^H[01]P[01]A[01]S[01]D[01]T[01]F[01]M[01]I[012]N[01]U[01]$'){
 $code='V13_O'+$o+'B'+$b+[string]$lines[0]
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
