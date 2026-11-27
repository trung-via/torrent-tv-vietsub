Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'NONCE_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('NativeBrowserTest\g21-v33-preflight-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='G21_PRE_LOCAL_ERROR'
try{
 $py=@'
import sys,pathlib,os,json,re,time,urllib.request,urllib.parse,subprocess
root,run,spool=map(pathlib.Path,sys.argv[1:])
def ps(cmd):
    p=subprocess.run(["pwsh","-NoProfile","-NonInteractive","-Command",cmd],capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=15,check=True)
    return p.stdout.strip()
def read(p,maxsize=4096):
    try:
        if not p.is_file() or p.is_symlink() or p.stat().st_size>maxsize:return {}
        return json.loads(p.read_text(encoding="utf-8-sig"))
    except (OSError,ValueError):return {}
def main():
    owner=root/"OwnerBridge"
    task=ps("(Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\\').State.ToString()").upper()
    if task not in ("RUNNING","READY","DISABLED"):task="UNKNOWN"
    h=read(owner/"agent-health.json",512)
    d=read(spool.parent/"OwnerBridge"/"Diagnostics"/"owner-snapshot.json")
    now=time.time()
    def fresh(x,key):
        v=x.get(key)
        return type(v) is int and 0<=now-v<=15
    p2=d.get("p2",{})
    p3=d.get("p3_state","UNKNOWN")
    if p3 not in ("FRESH_ON","FRESH_REQUESTED","FRESH_OFF","FRESH_OTHER","FRESH_INACTIVE","STALE","MISSING","UNKNOWN"):p3="UNKNOWN"
    inbox=owner/"inbox";state=root/"P2"/"auto-lean120-state"
    p=sum(1 for _ in inbox.glob("event-*.json")) if inbox.is_dir() else -1
    i=sum(1 for _ in state.rglob("*.inflight")) if state.is_dir() else -1
    b=sum(1 for x in (root/"P2",owner) if x.is_dir() for _ in x.rglob("browser.pending"))
    active=int(ps(r"""$p=@(Get-CimInstance Win32_Process | Where-Object {$_.ProcessId -ne $PID -and $_.CommandLine -and (
            ($_.Name -match '^(agy|antigravity|gemini|codex)(\.exe)?$') -or
            ($_.Name -match '^(node|python|pythonw|py|pwsh|powershell|cmd)\.exe$' -and
            $_.CommandLine -match 'chrome-devtools-mcp|--browser-url=http://127\.0\.0\.1:9555|antigravity-cli|TTV_AGY_CLI')
        )}); $p.Count""").splitlines()[-1])
    o=urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with o.open("http://127.0.0.1:9555/json/list",timeout=3) as f:pages=[x for x in json.load(f) if x.get("type")=="page"]
    except Exception:pages=None
    def cat(x):
        u=urllib.parse.urlsplit(x.get("url",""));host=u.hostname or ""
        if x.get("url") in ("about:blank","chrome://newtab/","chrome://new-tab-page/"):return "BLANK"
        if host in ("www.opensubtitles.org","opensubtitles.org"):return "OS"
        if host in ("www.sunpictures.in","sunpictures.in"):
            return "JAILER" if urllib.parse.parse_qs(u.query).get("sunpict_movies")==["jailer2"] else "PUBLISHER"
        if host in ("ext.to","www.ext.to"):return "EXT"
        if host in ("primevideo.com","www.primevideo.com"):return "PRIME"
        if u.scheme=="chrome-error":return "ERROR"
        return "OTHER"
    tab="UNAVAILABLE" if pages is None else cat(pages[0]) if len(pages)==1 else "COUNT"+str(len(pages))
    health="FRESH" if h.get("state")=="READY" and fresh(h,"observed_utc_epoch") else "UNKNOWN"
    snap="FRESH" if d.get("status")=="READY_FRESH" and fresh(d,"snapshot_utc_epoch") else "UNKNOWN"
    data={"task":task,"tab_category":tab,"health":health,"snapshot":snap,"p3":p3,"pending":p,"inflight":i,"browser_claims":b,"provider_processes":active,"p2_status":p2.get("status","UNKNOWN"),"p2_pending":p2.get("pending_events"),"p2_inflight":p2.get("inflight_count")}
    (run/"READOUT.json").write_text(json.dumps(data,indent=2),encoding="utf-8")
    def n(v):return str(v) if type(v) is int and 0<=v<=999 else "X"
    return "G21_PRE_"+tab+"_T"+task+"_H"+health[0]+"_S"+snap[0]+"_"+p3+"_P"+n(p)+"I"+n(i)+"B"+n(b)+"A"+n(active)
try:print(main())
except Exception:
    import traceback
    (run/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("G21_PRE_LOCAL_ERROR")
'@
 $f=Join-Path $run 'readout.py'
 [IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
 $out=@(& py -3 -I -B $f $root $run $spool 2> (Join-Path $run 'python-stderr.txt'))
 if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
}catch{[IO.File]::WriteAllText((Join-Path $run 'host-private-error.txt'),($_|Out-String),[Text.UTF8Encoding]::new($false))}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
