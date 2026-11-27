Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'NONCE_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('g21-v33-list-shape-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$py=@'
import sys,pathlib,json,re,queue,time,types
root,spool,run=map(pathlib.Path,sys.argv[1:])
def obj(p):
    if not p.is_file() or p.is_symlink() or p.stat().st_size>16777216:return {}
    try:
        v=json.loads(p.read_text(encoding="utf-8-sig"))
        return v if isinstance(v,dict) else {}
    except ValueError:return {}
def bound(source):
    found=[]
    for p in (spool/"History").glob("receipt-*.json"):
        v=obj(p);n=v.get("nonce","")
        if v.get("source_commit")!=source or v.get("result")!="SUCCESS" or not re.fullmatch("[a-f0-9]{32}",str(n)):continue
        q=obj(spool/"History"/("request-"+n+".json"))
        if q.get("nonce")==n and q.get("source_commit")==source:found.append(n)
    if len(found)!=1:raise ValueError("RECEIPT_COUNT")
    return found[0]
def main():
    old=bound("10b322a779f353b14a0ebb201e5502ae58afd683")
    new=bound("3822be4a3ba896772f06e9274633418b852d7ad8")
    v31=root/("g21-v31-stream-"+old)
    v33=root/("g21-v33-"+new)
    h=obj(v31/"BRAIN_HANDOFF.json")
    if h.get("process_state")!="EXITED" or h.get("conversation_id_match") is not True or len(h.get("turns",[]))!=2:return "G21_V33_REPLAY_PRIOR_DRIFT"
    checkout=v33/"candidate"/"poc"/"p2-sub-discovery"
    import subprocess
    sha=subprocess.run(["git","rev-parse","HEAD"],cwd=checkout,capture_output=True,text=True,check=True,timeout=5).stdout.strip()
    if sha!="f21f893c7888d031c7b5af4c1eb8628c67129f5b":return "G21_V33_REPLAY_SOURCE_DRIFT"
    sys.path.insert(0,str(checkout))
    from agy_owner_warm_session import OwnerAgyWarmSession,_source_page,_page_argument
    p=v31/"agy-stdout.jsonl"
    if not p.is_file() or p.is_symlink() or p.stat().st_size>16777216:return "G21_V33_REPLAY_LOG_MISSING"
    turns=[];current=[]
    for line in p.read_text("utf-8-sig",errors="replace").splitlines():
        current.append(line+"\n")
        try:e=json.loads(line)
        except ValueError:continue
        if isinstance(e,dict) and e.get("event")=="result":
            turns.append(current);current=[]
    if len(turns)!=2:return "G21_V33_REPLAY_TURN_COUNT"
    # Inspect only native list_pages structure, including nested JSON/text wrappers.
    # Export enums/counts; all raw payloads stay in the existing private logs.
    import urllib.parse
    reports=[]
    def strings(v,depth=0):
        if depth>5:return
        if isinstance(v,str):
            yield v
            try:x=json.loads(v)
            except (ValueError,TypeError):return
            if not isinstance(x,str) or x!=v:yield from strings(x,depth+1)
        elif isinstance(v,dict):
            for k,x in v.items():yield from strings(x,depth+1)
        elif isinstance(v,list):
            for x in v:yield from strings(x,depth+1)
    for i,lines in enumerate(turns,1):
        for line in lines:
            try:e=json.loads(line)
            except ValueError:continue
            if not isinstance(e,dict):continue
            st=e.get("step_update")
            if not isinstance(st,dict) or st.get("tool_name")!="call_mcp_tool":continue
            info=st.get("tool_info")
            if not isinstance(info,dict):continue
            params=info.get("parameters",{})
            if not isinstance(params,dict) or params.get("ToolName")!="list_pages" or "output" not in info:continue
            out=info["output"]
            shape=type(out).__name__.upper()
            vals=list(strings(out))
            has_www=any("www.sunpictures.in" in v for v in vals)
            has_bare=any("sunpictures.in" in v for v in vals)
            # Distinguish newline/prefix/JSON issues without publishing actual content.
            row_patterns=[r"(?m)^\s*(\d+):\s*(https://[^\s\]\)]+)",r"(?m)^\s*(\d+):\s*(?:\[[^\]]+\]\s*)?(https://[^\s\]\)]+)",r"(?m)^\s*(\d+):\s*.*?(https://[^\s\]\)]+)",r"(?m)^\s*(\d+)\s*[-.)]\s*(https://[^\s\]\)]+)"]
            hits=[]
            for pat in row_patterns:
                hits.append(sum(urllib.parse.urlsplit(url).hostname in ("sunpictures.in","www.sunpictures.in") for v in vals for _,url in re.findall(pat,v)))
            # Record safe key names and redacted text in private output only.
            reports.append({"turn":i,"shape":shape,"strings":len(vals),"www":has_www,"bare":has_bare,"hits":hits,"keys":list(out) if isinstance(out,dict) else [],"native_output":out})
    (run/"LIST_SHAPE.json").write_text(json.dumps(reports,indent=2),encoding="utf-8")
    if not reports:return "G21_LIST_NO_OUTPUT_WITH_PARAMS"
    x=reports[0]
    return "G21_LIST_"+x["shape"]+"_N"+str(len(reports))+"_W"+str(int(x["www"]))+"_B"+str(int(x["bare"]))+"_H"+"".join(str(min(9,v)) for v in x["hits"])

try:print(main())
except Exception:
    import traceback
    (run/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("G21_V33_REPLAY_LOCAL_ERROR")
'@
$f=Join-Path $run 'replay.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run 2> (Join-Path $run 'python-stderr.txt'))
$code=if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){[string]$out[0]}else{'G21_V33_REPLAY_LOCAL_ERROR'}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
