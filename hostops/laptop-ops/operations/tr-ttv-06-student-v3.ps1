# BT04 forensic readout only; no browser, provider, production or film writes.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$env:TTV_READOUT_NONCE=[string]$rq.nonce
$py=@'
import json, pathlib, sys, os, re, sqlite3, urllib.parse, hashlib, zipfile
root,spool=map(pathlib.Path,sys.argv[1:])
source="4cd3124ac8c7102028ff0b1f079a5b3b522b15c9"
nonce=os.environ["TTV_READOUT_NONCE"]
assert re.fullmatch("[a-f0-9]{32}",nonce)
def read(p,cap=67108864):
    if p.is_symlink() or not p.is_file() or p.stat().st_size>cap: return ""
    return p.read_text(encoding="utf-8-sig",errors="replace")
def obj(p):
    try:return json.loads(read(p)) or {}
    except ValueError:return {}
receipts=[]
for f in (spool/"History").glob("receipt-*.json"):
    q=obj(f)
    if q.get("source_commit")==source and q.get("result")=="SUCCESS" and re.fullmatch("[a-f0-9]{32}",str(q.get("nonce",""))):receipts.append(q)
assert len(receipts)==1,"BT04R_RECEIPT_NOT_UNIQUE"
prior=receipts[0]["nonce"]
run=root/("bt04-neon-subtitlecat-"+prior)
assert run.is_dir() and not run.is_symlink(),"BT04R_RUN_MISSING"
err=read(run/"probe-error.txt",65536)
pyerr=read(run/"python-stderr.txt",1048576)
stderr=read(run/"agy-stderr.txt",4194304)
raw=read(run/"agy-stdout.jsonl")
report=obj(run/"BRAIN_TEACHER_REPORT.json")
timing=obj(run/"stream-timing.json")
fixture=obj(run/"verified-fixture.json")
assert not report or report.get("source_commit")==source
records=[];invalid=0
for line in raw.splitlines():
    try:
        x=json.loads(line)
        if isinstance(x,dict):records.append(x)
        else:invalid+=1
    except ValueError:invalid+=1
combined=err+"\n"+pyerr
kind="NO_EXCEPTION_TEXT"
for pat,code in [(r"stream timing drift","STREAM_TIMING_DRIFT"),(r"UnboundLocalError|NameError","NAME_ERROR"),(r"PermissionError|Permission denied|Access is denied","PERMISSION"),(r"FileNotFoundError","FILE_MISSING"),(r"Unicode(?:Encode|Decode)Error","UNICODE"),(r"JSONDecodeError","JSON"),(r"TimeoutError|TimeoutExpired","TIMEOUT"),(r"TypeError","TYPE"),(r"ValueError","VALUE"),(r"AttributeError","ATTRIBUTE"),(r"KeyError","KEY"),(r"IndexError","INDEX"),(r"OSError","OS"),(r"SyntaxError","SYNTAX"),(r"error","OTHER_ERROR")]:
    if re.search(pat,combined,re.I):kind=code;break
known={"list_pages","select_page","navigate_page","take_snapshot","click","fill","press_key","wait_for","evaluate_script","read_file","write_file","run_shell_command","execute_command","list_network_requests","call_mcp_tool"}
trace=[];final=[];tools=0;denied=0;blocked=0
times=timing.get("event_arrival_seconds",[])
timed=int(isinstance(times,list) and len(times)==len(records) and all(type(x) in (float,int) and 0<=x<1000000 for x in times))
for i,e in enumerate(records):
    st=e.get("step_update") if isinstance(e.get("step_update"),dict) else {}
    info=st.get("tool_info") if isinstance(st.get("tool_info"),dict) else {}
    params=info.get("parameters") if isinstance(info.get("parameters"),dict) else {}
    name=params.get("ToolName") if st.get("tool_name")=="call_mcp_tool" else st.get("tool_name")
    name=name.upper() if isinstance(name,str) and name in known else "OTHER"
    errors=[info.get("error"),st.get("error"),e.get("error")]
    state="RESULT" if e.get("event")=="result" else "ERROR" if any(x not in (None,"",False,[],{}) for x in errors) else "OUTPUT" if "output" in info else "CALL" if name!="OTHER" else "OTHER"
    if st.get("tool_name")=="call_mcp_tool" and state in ("ERROR","OUTPUT"):tools+=1
    denied+=int(bool(re.search(r"permission check failed|permission denied|auto.denied|user denied",json.dumps(errors),re.I)))
    blocked+=int(bool(re.search(r"making sure you.re not a bot|/\.within\.website/|captcha|access denied",str(info.get("output","")),re.I)))
    result=e.get("result")
    if isinstance(result,dict) and isinstance(result.get("response"),str) and result["response"].strip():final.append(result["response"])
    trace.append(f"{i}:{round(times[i]*1000) if timed else -1}:{name}:{state}")
# Recover model report schema without exposing arbitrary private content.
parsed=None
for a in reversed(final):
    for m in re.finditer(r"\{",a):
        try:q,_=json.JSONDecoder().raw_decode(a[m.start():])
        except ValueError:continue
        if isinstance(q,dict) and isinstance(q.get("actions"),list) and isinstance(q.get("reusable_recipe"),list):parsed=q;break
    if parsed is not None:break
status=parsed.get("status") if parsed else None
status=status if status in ("CANDIDATE_DOWNLOADED","NO_PLAUSIBLE_CANDIDATE","ACCESS_BLOCKED","AUTH_REQUIRED","DOWNLOAD_FAILED","TOOL_UNAVAILABLE","UNKNOWN") else "NOT_REPORTED"
# Files copied into the exact run directory only. Chrome History is read-only.
def cuecount(f):
    if f.is_symlink() or not f.is_file() or not 0<f.stat().st_size<=10000000:return 0
    try:
        if f.suffix.lower()==".srt":blobs=[f.read_bytes()]
        elif f.suffix.lower()==".zip":
            with zipfile.ZipFile(f) as z:blobs=[z.read(i) for i in z.infolist()[:100] if i.filename.lower().endswith(".srt") and 0<i.file_size<=2000000 and not i.flag_bits&1]
        else:return 0
        return max((len(re.findall(rb"(?m)^\d{2}:\d{2}:\d{2}[,.]\d{3}\s+-->\s+\d{2}:\d{2}:\d{2}[,.]\d{3}",x)) for x in blobs),default=0)
    except (OSError,ValueError,RuntimeError,zipfile.BadZipFile):return 0
copied=[cuecount(f) for f in (run/"browser-downloads").glob("*")]
copied=[x for x in copied if x]
history=0;downloads=0;history_cues=0
binding=obj(run/"task-binding.json")
dest=binding.get("download_directory")
if dest:
    dest=pathlib.Path(dest)
    try:
        con=sqlite3.connect((root/"CDP9555Profile/Default/History").resolve().as_uri()+"?mode=ro",uri=True,timeout=3)
        # Exact original job window (UTC); not the current readout window.
        lo=int((1795599261+11644473600)*1000000);hi=int((1795599810+11644473600)*1000000)
        # Use run folder/prompt timestamp as a stronger lower bound when present.
        prompt=run/"teacher-prompt.txt"
        if prompt.is_file():lo=int((prompt.stat().st_mtime-2+11644473600)*1000000)
        end=run/"agy-stdout.jsonl"
        if end.is_file():hi=int((end.stat().st_mtime+3+11644473600)*1000000)
        for rid,target,state,received in con.execute("select id,target_path,state,received_bytes from downloads where start_time>=? and start_time<=?",(lo,hi)):
            if state!=1 or received<=0:continue
            urls=[x[0] for x in con.execute("select url from downloads_url_chains where id=?",(rid,))]
            if not any(urllib.parse.urlsplit(str(u)).scheme=="https" and urllib.parse.urlsplit(str(u)).hostname in ("subtitlecat.com","www.subtitlecat.com") for u in urls):continue
            f=pathlib.Path(target)
            if not f.resolve().is_relative_to(dest.resolve()):continue
            c=cuecount(f)
            if c:downloads+=1;history_cues=max(history_cues,c)
        con.close();history=1
    except (OSError,ValueError,sqlite3.Error):pass
nums={"events":len(records),"invalid":invalid,"timed":timed,"fixture":int(bool(fixture.get("release_origin")=="TORRSERVER_VERIFIED")),"prompt":int((run/"teacher-prompt.txt").is_file()),"stdout_chars":len(raw),"stderr_chars":len(stderr),"report":int(bool(report)),"recipe":int((run/"TEACHER_RECIPE_PRIVATE.json").is_file()),"final_chars":sum(map(len,final)),"report_ok":int(parsed is not None),"actions":len(parsed["actions"]) if parsed else 0,"recipe_steps":len(parsed["reusable_recipe"]) if parsed else 0,"tools":tools,"denied":denied,"blocked_mentions":blocked,"copied":len(copied),"copied_cues":max(copied,default=0),"history":history,"downloads":downloads,"history_cues":history_cues,"elapsed":timing.get("elapsed_before_report",-1) if type(timing.get("elapsed_before_report")) is int else -1}
assert len(trace)<=2048
summary={"schema":"TTV-BT04-FORENSIC-V1","nonce":nonce,"source":source,"prior":prior,"error_kind":kind,"status":status,"trace":trace,**nums}
(spool/"Receipts"/("bt04-forensic-"+nonce+".json")).write_text(json.dumps(summary,separators=(",",":")),encoding="utf-8")
'@
$f=Join-Path $env:TEMP ('ttv-bt04r-'+$rq.nonce+'.py')
try{
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
& py -3 -I -B $f $root $spool
if($LASTEXITCODE -ne 0){throw 'BT04R_READ_ERROR'}
}finally{Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason='BT04R_READ_COMPLETE'}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output 'BT04R_READ_COMPLETE'
