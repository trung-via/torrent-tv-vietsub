Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'NONCE_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('NativeBrowserTest\g21-r4-timing-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$head='687511732e84ef76becc2004e97c0ee9c6e0170b'
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
def pages():
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open("http://127.0.0.1:9555/json/list",timeout=3) as f:
        return [p for p in json.load(f) if p.get("type")=="page"]
def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else "MISSING"
def main():
    def read(p,limit=4194304):
        if p.is_symlink() or not p.is_file() or p.stat().st_size>limit:return {}
        return json.loads(p.read_text(encoding="utf-8-sig"))
    matches=[]
    for p in (spool/"History").glob("receipt-*.json"):
        d=read(p,4096);n=d.get("nonce","")
        if d.get("source_commit")!="93874fb147b7031215df8b228c970576d1ef8546" or d.get("result")!="SUCCESS" or not re.fullmatch("[a-f0-9]{32}",str(n)):continue
        q=read(spool/"History"/("request-"+n+".json"),4096)
        s=read(spool/"Receipts"/("odyssey-stage-"+n+".json"),4096)
        if q.get("nonce")==n and q.get("source_commit")==d["source_commit"] and s.get("nonce")==n and s.get("reason")=="G21_V33_CONSUMER_REVIEW_REQUIRED":matches.append(n)
    if len(matches)!=1:return "G21_READOUT_PRIOR_HOLD"
    n=matches[0];old=root/"NativeBrowserTest"/("g21-r4-acceptance-"+n)
    journal=read(old/"OWNER_RECOVERY.json")
    acceptance=read(old/"ACCEPTANCE.json")
    receipt=acceptance.get("receipt",{})
    if receipt.get("request_id")!=n or receipt.get("status")!="REVIEW_REQUIRED":return "G21_READOUT_RECEIPT_HOLD"
    base=old/"isolated-cache"/".native-v13"
    runs=[p for p in base.glob("g2-*") if p.is_dir() and not p.is_symlink()]
    pending=(base/"browser.pending").exists()
    if len(runs)!=1:return "G21_TIMING_RUN_HOLD"
    x=runs[0]
    traces=[p for p in x.glob("*/event-arrivals.jsonl") if p.is_file() and not p.is_symlink()]
    if len(traces)!=2:return "G21_TIMING_TURN_COUNT_HOLD"
    values=[]
    for p in traces:
        if p.stat().st_size>4194304:return "G21_TIMING_TRACE_LIMIT"
        rows=[json.loads(line) for line in p.read_text(encoding="utf-8").splitlines() if line.strip()]
        ms=[v["elapsed_ms"] for v in rows if type(v.get("elapsed_ms")) is int and 0<=v["elapsed_ms"]<=600000]
        finals=[v["elapsed_ms"] for v in rows if v.get("event")=="result" and type(v.get("elapsed_ms")) is int]
        result=read(p.parent/"result.json")
        values.append((bool(result),max(ms,default=0),len(finals),result.get("timing",{}).get("final_ms",0),len(rows)))
    first=[v for v in values if v[0]]
    second=[v for v in values if not v[0]]
    if len(first)!=1 or len(second)!=1:return "G21_TIMING_RESULT_COUNT_HOLD"
    a,b=first[0],second[0]
    elapsed=acceptance.get("total_ms",0)
    if type(elapsed) is not int or not 0<=elapsed<=600000:return "G21_TIMING_ELAPSED_HOLD"
    return "G21_TIME_C"+str(a[3])+"_W"+str(b[1])+"_F"+str(b[2])+"_N"+str(b[4])+"_ALL"+str(elapsed)

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
