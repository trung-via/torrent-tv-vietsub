# Inspect existing AGY event timing and verified download/report times only.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$py=@'
import sys,pathlib,json,re,hashlib,zipfile,urllib.parse
spool,root,owner=map(pathlib.Path,sys.argv[1:])
import datetime,collections,statistics
def load(source,version,prefix):
    receipts=[]
    for p in (spool/"History").glob("receipt-*.json"):
        try:
            if p.is_symlink() or not 0<p.stat().st_size<=2048:continue
            v=json.loads(p.read_text(encoding="utf-8-sig"))
            if v.get("source_commit")==source and v.get("operation")=="agy-native-browser-readout-1124" and v.get("result")=="SUCCESS" and re.fullmatch("[a-f0-9]{32}",str(v.get("nonce",""))):receipts.append(v)
        except (OSError,ValueError):pass
    if len(receipts)!=1:raise ValueError("binding")
    run=root/(prefix+receipts[0]["nonce"])
    def read(p):
        if not p.is_file() or p.is_symlink() or not 0<p.stat().st_size<=32000000:raise ValueError("file")
        return p.read_text(encoding="utf-8",errors="strict")
    report=json.loads(read(run/"BRAIN_STUDENT_REPORT.json"))
    if report.get("source_commit")!=source or report.get("recipe_version")!=version or report.get("provider")!="SubtitleCat" or report.get("model")!="gemini-4-hydrogen-low":raise ValueError("drift")
    records=[]
    for line in read(run/"agy-stdout.jsonl").splitlines():
        try:
            event=json.loads(line)
            if isinstance(event,dict):records.append(event)
        except ValueError:pass
    if len(records)!=report["event_count"]:raise ValueError("event drift")
    def ts(v):
        if isinstance(v,str):
            try:
                d=datetime.datetime.fromisoformat(v.replace("Z","+00:00"))
                if d.tzinfo is not None:return d.timestamp()
            except ValueError:pass
        if type(v) in (int,float):
            for div in (1,1000,1000000,1000000000):
                if 1760000000<=v/div<=1830000000:return v/div
        return None
    # Strict top-level event clock, not arbitrary timestamps inside webpage/tool content.
    clockkeys=("timestamp","time","created_at","createdAt","event_time","eventTime","ts")
    rows=[]
    for i,e in enumerate(records):
        values=[ts(e[k]) for k in clockkeys if k in e]
        values=[v for v in values if v is not None]
        stamp=values[0] if values and max(values)-min(values)<.1 else None
        st=e.get("step_update",{})
        if not isinstance(st,dict):st={}
        ti=st.get("tool_info",{})
        if not isinstance(ti,dict):ti={}
        params=ti.get("parameters",{})
        if not isinstance(params,dict):params={}
        tool=st.get("tool_name")=="call_mcp_tool"
        completed=tool and ("output" in ti or "error" in ti)
        rows.append((i,stamp,tool,completed,e.get("event")=="result"))
    timed=[r for r in rows if r[1] is not None]
    elapsed=report["elapsed_seconds"]
    span=round(timed[-1][1]-timed[0][1]) if len(timed)>1 and all(b[1]>=a[1] for a,b in zip(timed,timed[1:])) else -1
    if span<0 or span>elapsed+3:span=-1
    # If wall clock is not retained, do not turn event counts into seconds.
    # File mtime and report mtime provide only a post-download-to-report estimate.
    arts=report.get("artifacts",[])
    tail=-1
    if len(arts)==1:
        art=arts[0];name=art["filename"]
        if pathlib.Path(name).name==name:
            f=run/"browser-downloads"/name
            if f.is_file() and not f.is_symlink() and 0<f.stat().st_size<=10000000 and hashlib.sha256(f.read_bytes()).hexdigest()==art["sha256"]:
                diff=(run/"BRAIN_STUDENT_REPORT.json").stat().st_mtime-f.stat().st_mtime
                if 0<=diff<=elapsed+10:tail=round(diff)
    # No assumptions about model computation versus browser waiting without paired timestamps.
    complete=[r for r in timed if r[3]]
    result=[r for r in timed if r[4]]
    first=-1;last=-1
    if span>=0 and complete:
        first=round(complete[0][1]-timed[0][1])
        if result and result[-1][1]>=complete[-1][1]:last=round(result[-1][1]-complete[-1][1])
    return dict(t=elapsed,n=len(records),c=len(timed),span=span,tail=tail,first=first,last=last)
def main():
    rows=[
        load("9cbdbd4459f5db009c960164bcf4b8d9d254a91d","V4","tr-ttv-11-kalki2898ad-subtitlecat-v4-"),
        load("7929ef249419698007aa8ee0948e2fe92cb093cf","V5","tr-ttv-13-kalki2898ad-subtitlecat-v5-"),
        load("20bd193ff2fb23ba8d6552e3053c0a84ca665684","V6","tr-ttv-14-kalki2898ad-subtitlecat-v6-")]
    # X = unavailable. Compact sanitized evidence, never print private log values.
    def val(x):return str(x) if x>=0 else "X"
    return "TR15_"+ "_".join(f"V{i}T{r['t']}C{r['c']}S{val(r['span'])}D{val(r['tail'])}F{val(r['first'])}L{val(r['last'])}" for i,r in zip((4,5,6),rows))

try:print(main())
except Exception:print("TR15QA_PRIVATE_ERROR")
'@
$f=Join-Path $env:TEMP ('ttv-v4-qa-'+[Guid]::NewGuid().ToString('N')+'.py')
try{
 [IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
 $out=@(& py -3 -I -B $f $spool $root $owner 2>$null)
 $code='TR15QA_READ_ERROR'
 if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
}finally{Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
