Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'NONCE_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('NativeBrowserTest\g2-sintel-locator-audit-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$head='9a110724cab7b184ca56bd171a5ccdebf469b9b5'
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
    for directory in (spool/"History",spool/"Receipts"):
        for p in directory.glob("receipt*.json"):
            d=read(p,4096);n=d.get("nonce","")
            if d.get("source_commit")!="02a02788a3d06fc28b4f7b023e0fc0294bb7a74d" or d.get("result")!="SUCCESS" or not re.fullmatch("[a-f0-9]{32}",str(n)):continue
            q=read(spool/"History"/("request-"+n+".json"),4096) or read(spool/"Requests"/"request.json",4096)
            # Latest request may already have been archived by dispatcher.
            st=read(spool/"Receipts"/("odyssey-stage-"+n+".json"),4096)
            if q.get("nonce")==n and q.get("source_commit")==d["source_commit"] and st.get("nonce")==n and st.get("reason")=="G2_SINTEL_NO_EXACT_MATCH_REPORTED_MS60488":matches.append(n)
    matches=list(set(matches))
    if len(matches)!=1:return "G2_READOUT_PRIOR_HOLD"
    n=matches[0];old=root/"NativeBrowserTest"/("g2-sintel-library-once-"+n)
    acc=read(old/"ACCEPTANCE.json");rec=acc.get("receipt",{})
    if acc.get("head")!=head or rec.get("request_id")!=n or len(rec.get("results",[]))!=1:return "G2_READOUT_BINDING_HOLD"
    row=rec["results"][0];tid=row.get("turn_request_id","")
    if row.get("status")!="NO_EXACT_MATCH_REPORTED" or not re.fullmatch("[a-f0-9]{32}",tid):return "G2_READOUT_RESULT_HOLD"
    trace=old/"isolated-cache"/".native-v13"/("g2-"+n)/tid/"agy-stdout.jsonl"
    if not trace.is_file() or trace.is_symlink() or trace.stat().st_size>16777216:return "G2_READOUT_TRACE_HOLD"
    finals=[]
    for line in trace.read_text(encoding="utf-8").splitlines():
        try: ev=json.loads(line)
        except ValueError:continue
        if ev.get("event")=="result" and isinstance(ev.get("result"),dict):
            response=ev["result"].get("response")
            if isinstance(response,str):
                response=response.strip()
                fence=re.fullmatch(r"\x60{3}(?:json)?\s*(.*?)\s*\x60{3}",response,re.S)
                finals.append(json.loads(fence[1] if fence else response))
    if len(finals)!=1:return "G2_READOUT_FINAL_HOLD"
    payload=finals[0];rows=payload.get("candidates")
    if payload.get("request_id")!=tid or not isinstance(rows,list):return "G2_READOUT_PAYLOAD_HOLD"
    counts=dict(c=len(rows),title=0,year=0,string=0,missing=0,other=0,both=0,link=0)
    for x in rows:
        if not isinstance(x,dict):continue
        title=x.get("title");year=x.get("year")
        match=isinstance(title,str) and " ".join(title.casefold().split())=="sintel"
        counts["title"]+=int(match)
        counts["year"]+=int(type(year) is int and year==2010)
        counts["string"]+=int(year=="2010")
        counts["missing"]+=int(year is None)
        counts["other"]+=int(year is not None and year!="2010" and not(type(year) is int and year==2010))
        counts["both"]+=int(match and type(year) is int and year==2010)
        counts["link"]+=int(isinstance(x.get("link"),str) and x["link"].startswith("magnet:?"))
    journal=read(old/"OWNER_RECOVERY.json")
    selected=payload.get("selected")
    counts["pick"]=int(isinstance(selected,dict) and isinstance(selected.get("link"),str))
    counts["handoff"]=len(acc.get("handoffs",[]))
    counts["restored"]=int(journal.get("stage")=="RESTORED" and acc.get("restored") is True)
    # Inspect the exact saved MCP events and AGY candidate, without browser,
    # provider, new download or modification to the original run.
    candidate=old/"candidate"
    if subprocess.check_output(["git","-C",str(candidate),"rev-parse","HEAD"],text=True).strip()!=head:return "G2_AUDIT_SOURCE_HOLD"
    sys.path[:0]=[str(candidate/"poc/p2-sub-discovery"),str(candidate/"poc/p2-aisub")]
    from owner_g2_discovery import _link_hash,_observed_locator
    from agy_owner_warm_session import _page_argument,_source_page
    from owner_movie_handoff import _post,_listed,_file
    from html import unescape
    expected="08ada5a7a6183aae1e09d831df6748d566095a10"
    if len(rows)!=1 or not isinstance(rows[0],dict):return "G2_AUDIT_ROW_HOLD"
    name=rows[0].get("release_name")
    link=rows[0].get("link")
    if not isinstance(name,str) or not isinstance(link,str):return "G2_AUDIT_FIELDS_HOLD"
    target=_link_hash(link)
    if target!=expected:return "G2_AUDIT_HASH_MISMATCH"
    norm=lambda x:" ".join(x.casefold().split())
    pending=None;page=None
    c=dict(bound=0,raw=0,hash=0,label=0,obj=0,other=0,exact=0,alt=0,output=0)
    details=[]
    for line in trace.read_text(encoding="utf-8").splitlines():
        try:ev=json.loads(line)
        except ValueError:continue
        st=ev.get("step_update")
        if not isinstance(st,dict) or st.get("tool_name")!="call_mcp_tool":continue
        info=st.get("tool_info")
        if not isinstance(info,dict):continue
        params=info.get("parameters")
        if isinstance(params,dict) and params.get("ToolName"):
            pending=(params["ToolName"],next((params[k] for k in ("ServerName","Server","serverName","server") if isinstance(params.get(k),str)),None),_page_argument(params))
        if "output" not in info and not info.get("error"):continue
        if pending and pending[1]=="ttv-browser" and not (info.get("error") or st.get("error")):
            output=info.get("output")
            if pending[0]=="list_pages":page=_source_page(output,"webtorrent.io")
            elif pending[0] in ("evaluate_script","take_snapshot") and page is not None and pending[2]==page:
                c["bound"]+=1
                if not isinstance(output,str):c["other"]+=1
                else:
                    c["output"]+=1
                    visible=unescape(output)
                    hasname=norm(name) in norm(visible)
                    c["label"]+=int(hasname)
                    c["raw"]+=int(link in visible)
                    c["hash"]+=int(expected in visible.casefold())
                    objects=[]
                    for m in re.finditer(r"\{",output):
                        try:o,_=json.JSONDecoder().raw_decode(output,m.start())
                        except ValueError:continue
                        if not isinstance(o,dict):continue
                        if isinstance(o.get("release_name"),str) and isinstance(o.get("link"),str):
                            c["obj"]+=1
                            if norm(o["release_name"])==norm(name) and unescape(o["link"])==link:c["exact"]+=1
                        # Summarize alternate key pairings only, never raw values.
                        keys=tuple(sorted(k for k,v in o.items() if isinstance(v,str)))
                        matching=[k for k,v in o.items() if isinstance(v,str) and _link_hash(unescape(v))==expected]
                        labels=[k for k,v in o.items() if isinstance(v,str) and norm(v)==norm(name)]
                        if matching and labels:c["alt"]+=1
                        if matching:objects.append({"keys":keys,"matching":matching,"labels":labels})
                    details.append({"tool":pending[0],"length":len(output),"label":hasname,"exact_link":link in visible,"hash_present":expected in visible.casefold(),"objects":objects})
        pending=None
    library=-1;file=-1
    try:
        library=int(_listed(_post({"action":"list"},5),expected))
        if library:
            try:file=int(_file(_post({"action":"get","hash":expected},5),expected,None) is not None)
            except Exception:file=0
        else:file=0
    except Exception:pass
    claim=sum(1 for p in (root/"NativeBrowserTest").glob("g2-sintel-resume-*") if (p/"resume-attempt.json").exists())
    write(run/"AUDIT.json",{"counts":c,"details":details,"library":library,"file":file,"resume_claim":claim})
    return "G2_LOC_B{bound}_R{raw}_H{hash}_L{label}_O{obj}_E{exact}_A{alt}_X{other}_TS".format(**c)+("U" if library<0 else str(library))+"_F"+("U" if file<0 else str(file))+"_C"+str(claim)

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
