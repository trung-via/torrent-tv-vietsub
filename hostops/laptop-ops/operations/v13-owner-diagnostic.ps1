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
$profile=Join-Path $root 'CDP9555Profile'
$profileOk=[int](Test-Path -LiteralPath $profile -PathType Container)
$chromeOk=[int](@(@("$env:ProgramFiles\Google\Chrome\Application\chrome.exe","${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe","$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")|Where-Object{Test-Path -LiteralPath $_ -PathType Leaf}).Count -gt 0)
$proc=0;$listener=0;$correct=0
try{
 $all=@(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'")
 $proc=[int](@($all|Where-Object{$_.CommandLine -and $_.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0}).Count -gt 0)
 $ls=@(Get-NetTCPConnection -LocalPort 9555 -State Listen -ErrorAction SilentlyContinue)
 $listener=[int]($ls.Count -gt 0)
 if($listener -eq 1){
  $ids=@($ls|Select-Object -ExpandProperty OwningProcess -Unique)
  if($ids.Count -eq 1 -and @($ls|Where-Object{$_.LocalAddress -notin @('127.0.0.1','::1')}).Count -eq 0){
   $p=$all|Where-Object{[int]$_.ProcessId -eq [int]$ids[0]}
   if($p -and $p.CommandLine -and $p.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0){$correct=1}
  }
 }
}catch{}
$py=@'
import sys,pathlib,json,re,math,shutil
from fractions import Fraction
owner,root,spool,run=map(pathlib.Path,sys.argv[1:5])
sys.path[:0]=[str(owner/"app/poc/p2-aisub"),str(owner/"app/poc/p2-sub-discovery")]
def obj(p):
    if not p.is_file() or p.is_symlink() or not 0<p.stat().st_size<=16777216:raise ValueError("file")
    return json.loads(p.read_text(encoding="utf-8-sig"))
phase="FIXTURE";code="FIXTURE";ff=int(shutil.which("ffprobe") is not None)
try:
    receipts=[]
    for p in (spool/"History").glob("receipt-*.json"):
        q=obj(p)
        if q.get("source_commit")=="29c8dac83ed663b137a39c666d242258cd93c848" and q.get("result")=="SUCCESS" and re.fullmatch(r"[a-f0-9]{32}",str(q.get("nonce",""))):receipts.append(q["nonce"])
    if len(receipts)!=1:raise ValueError("fixture")
    f=obj(root/("bt24-human-fixture-preflight-"+receipts[0])/"BRAIN_HUMAN_FIXTURE.json")
    if f.get("schema")!="BT10_HUMAN_FIXTURE_V1" or f.get("exact_file_verified") is not True:raise ValueError("fixture")
    from owner_torrserver_readonly import OwnerLocalTorrServer,OwnerTorrServerReader
    from owner_torrserver_ffp_tracks import _read_local_ffp
    policy=obj(owner/"p3-p4-policy.json")
    cfg=OwnerLocalTorrServer(policy["profile_id"],policy["torrserver_port"])
    tor,idx=f["hash"],f["file_index"]
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}",tor) or type(idx) is not int or not 0<=idx<4096:raise ValueError("identity")
    phase="IDENTITY"
    actual=OwnerTorrServerReader(cfg)(cfg.profile_id,tor,idx)
    if actual.path.replace("\\","/").rsplit("/",1)[-1]!=f["filename"] or actual.length!=f["size_bytes"]:raise ValueError("identity")
    phase="FETCH"
    raw=_read_local_ffp(f"http://127.0.0.1:{cfg.localhost_port}/ffp/{tor}/{idx}",8.0)
    phase="JSON"
    doc=json.loads(raw)
    phase="STREAMS"
    tracks=[v for v in doc["streams"] if v["codec_type"]=="video" and not v.get("disposition",{}).get("attached_pic")]
    if len(tracks)!=1:raise ValueError("streams")
    phase="DURATION"
    duration=float(doc["format"]["duration"])
    if not math.isfinite(duration) or not 0<duration<=86400:raise ValueError("duration")
    phase="FPS"
    fps=float(Fraction(tracks[0]["avg_frame_rate"]))
    if not math.isfinite(fps) or not 0<fps<=240:raise ValueError("fps")
    code="PASS" if abs(duration-float(f["duration_seconds"]))<=2 and abs(fps-float(f["fps"]))<=0.01 else "DRIFT"
except Exception as exc:
    code=phase
    (run/"diagnostic.json").write_text(json.dumps({"phase":phase,"exception_type":type(exc).__name__}),encoding="utf-8")
print("F"+str(ff)+"M"+code)
'@
$file=Join-Path $run 'diagnostic.py'
[IO.File]::WriteAllText($file,$py,[Text.UTF8Encoding]::new($false))
$lines=@(& py -3 -I -B $file $owner $root $spool $run 2> (Join-Path $run 'stderr.txt'))
$code='V13_DIAG_PRIVATE_ERROR'
if($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and [string]$lines[0] -cmatch '^F[01]M(FIXTURE|IDENTITY|FETCH|JSON|STREAMS|DURATION|FPS|PASS|DRIFT)$'){
 $code='V13_DIAG_P'+$profileOk+'E'+$chromeOk+'C'+$proc+'L'+$listener+'B'+$correct+[string]$lines[0]
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
