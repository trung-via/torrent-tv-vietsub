Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'NONCE_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('g21-v33-r3-replay-'+$rq.nonce)
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
    # Fetch only the corrected parser at the immutable candidate HEAD and verify the Git blob.
    import hashlib,urllib.request
    url="https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/d7aa1673e70255db575246a6da27ad037def9fac/poc/p2-sub-discovery/agy_owner_warm_session.py"
    with urllib.request.urlopen(url,timeout=20) as response:
        data=response.read(262145)
    if len(data)>262144 or hashlib.sha1(b"blob "+str(len(data)).encode()+b"\0"+data).hexdigest()!="4fe02e6c18f2e2bbeebe70a808d3ae7b995190ad":
        return "G21_V33_R3_SOURCE_HASH_HOLD"
    (run/"agy_owner_warm_session.py").write_bytes(data)
    sys.path.insert(0,str(run))
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
    reports=[]
    for idx,lines in enumerate(turns,1):
        # Invoke the unmodified candidate parser with recorded stdout; no process or provider.
        s=OwnerAgyWarmSession(ps="",env={},root=run,timeout=5)
        s.process=types.SimpleNamespace(poll=lambda:None,stdin=types.SimpleNamespace(write=lambda _:None,flush=lambda:None))
        for line in lines:s._queue.put((time.monotonic(),line))
        # Analyze only protocol structure; never export raw page text/URLs/session IDs.
        shape=[]
        for line in lines:
            try:e=json.loads(line)
            except ValueError:continue
            if not isinstance(e,dict):continue
            st=e.get("step_update")
            if not isinstance(st,dict) or st.get("tool_name")!="call_mcp_tool":continue
            info=st.get("tool_info")
            if not isinstance(info,dict):continue
            params=info.get("parameters")
            if not isinstance(params,dict):continue
            name=params.get("ToolName")
            if name not in ("list_pages","select_page","evaluate_script","take_snapshot","click","fill","navigate_page","press_key","wait_for"):continue
            keys=[k for k in params if re.fullmatch("[A-Za-z_]{1,40}",k)]
            shape.append({"tool":name,"parameter_keys":keys,"page_arg":_page_argument(params) is not None,"output_type":type(info.get("output")).__name__,"source_page_detected":_source_page(info.get("output",""),"www.sunpictures.in") is not None if name=="list_pages" else None})
        try:
            result=s.turn("REPLAY ONLY",run/("turn-"+str(idx)),source_host="www.sunpictures.in")
            status="PASS"
        except Exception as e:
            status=str(e) if re.fullmatch("AGY_STREAM_[A-Z0-9_]{1,70}",str(e)) else "OTHER_ERROR"
        reports.append({"turn":idx,"status":status,"shape":shape})
    (run/"REPLAY.json").write_text(json.dumps(reports,indent=2),encoding="utf-8")
    states=["P" if r["status"]=="PASS" else "B" if r["status"]=="AGY_STREAM_SOURCE_PAGE_UNBOUND" else "F" for r in reports]
    # Counts of actual list_pages recognition and pageId extraction in saved native logs.
    codes=[]
    for r in reports:
        shape=r["shape"]
        codes.append("L"+str(sum(x["source_page_detected"] is True for x in shape))+"D"+str(sum(x["page_arg"] and x["tool"] in ("evaluate_script","take_snapshot") for x in shape)))
    return "G21_V33_REPLAY_"+states[0]+codes[0]+"_"+states[1]+codes[1]
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
