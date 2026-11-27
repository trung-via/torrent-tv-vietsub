Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'NONCE_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('NativeBrowserTest\g21-r4-readout-'+$rq.nonce)
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
    started=turns=results=reads=errors=finals=bound=0
    code="NO_RUN"
    if len(runs)==1:
        x=runs[0]
        started=int((x/"browser.started.json").is_file())
        trace=[p for p in x.glob("*/agy-stdout.jsonl") if p.is_file() and not p.is_symlink()]
        turns=len(trace)
        code="NO_TURN" if not turns else "NO_FINAL"
        for p in trace:
            if p.stat().st_size>16777216:return "G21_READOUT_TRACE_LIMIT"
            # Only structural facts; never publish prompts, raw responses, URLs or IDs.
            for line in p.read_text(encoding="utf-8",errors="replace").splitlines():
                try:e=json.loads(line)
                except ValueError:continue
                if not isinstance(e,dict):continue
                st=e.get("step_update")
                if isinstance(st,dict) and st.get("tool_name")=="call_mcp_tool":
                    info=st.get("tool_info",{})
                    if isinstance(info,dict):
                        if "output" in info:reads+=1
                        if info.get("error") or st.get("error"):errors+=1
                if e.get("event")=="result" and isinstance(e.get("result"),dict):
                    finals+=1
                    response=e["result"].get("response")
                    if not isinstance(response,str):code="RESULT_INVALID";continue
                    fence=re.fullmatch(r"\x60{3}(?:json)?\s*(.*?)\s*\x60{3}",response.strip(),re.S)
                    try:payload=json.loads(fence[1] if fence else response)
                    except ValueError:code="JSON_INVALID";continue
                    code="FINAL_JSON" if isinstance(payload,dict) else "RESULT_INVALID"
            if (p.parent/"result.json").is_file():results+=1
        if results==turns and turns:code="RESULT_WRITTEN"
        if (x/"completed.json").is_file():code="COMPLETED"
        stderr=x/"agy-stderr.txt"
        if stderr.is_file() and stderr.stat().st_size<=4194304:
            st=stderr.read_text(encoding="utf-8",errors="replace").lower()
            if re.search(r"quota|resource_exhausted|rate limit",st):code="QUOTA_HINT"
    h=read(root/"OwnerBridge"/"agent-health.json",4096)
    fresh=h.get("schema")=="TTV-OWNER-AGENT-HEALTH-V1" and h.get("state")=="READY" and type(h.get("pid")) is int and 0<=time.time()-h.get("observed_utc_epoch",0)<=30
    if fresh:fresh=ps("if(Get-Process -Id "+str(h["pid"])+" -ErrorAction SilentlyContinue){'YES'}else{'NO'}")=="YES"
    status="READY" if task_state().upper()=="RUNNING" and fresh else "UNVERIFIED"
    restore="Y" if acceptance.get("restored") is True else "N"
    j="Y" if journal.get("stage")=="RESTORED" else "N"
    return "G21_READ_"+code+"_T"+str(turns)+"_F"+str(finals)+"_R"+str(results)+"_M"+str(reads)+"_E"+str(errors)+"_S"+str(started)+"_P"+str(int(pending))+"_B"+restore+"_J"+j+"_O"+status

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
