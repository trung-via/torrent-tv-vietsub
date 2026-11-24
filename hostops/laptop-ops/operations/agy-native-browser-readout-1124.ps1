# TR-TTV.04a exact prior smoke readout, no provider or browser actions.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('tr-ttv-04a-smoke2-readout-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$py=@'
import sys,pathlib,os,json,re
root,run=map(pathlib.Path,sys.argv[1:])
def read(p):
    if not p.is_file() or p.is_symlink() or p.stat().st_size>16777216:return ""
    return p.read_text(encoding="utf-8-sig",errors="replace")
def probe():
    history=pathlib.Path(os.environ["ProgramData"])/"TorrentTVVietsub"/"LaptopHostOps"/"History"
    hits=[]
    for f in history.glob("receipt-*.json"):
        try:
            q=json.loads(read(f))
            if q.get("source_commit")=="de49e8547eea9fce6e34f717921a7ec87162dadf" and q.get("operation")=="agy-native-browser-readout-1124" and q.get("result")=="SUCCESS" and re.fullmatch(r"[a-f0-9]{32}",q.get("nonce","")):hits.append(q["nonce"])
        except (ValueError,TypeError,OSError):pass
    if len(hits)!=1:return "TR04AR_PRIOR_HOLD"
    p=root/("tr-ttv-04a-smoke2-"+hits[0])
    summary=json.loads(read(p/"smoke-summary.json"))
    raw=read(p/"agy-stdout.jsonl")
    err=read(p/"agy-stderr.txt")
    helptext=read(p/"cli-help.txt")
    events=[]
    for line in raw.splitlines():
        try:
            v=json.loads(line)
            if isinstance(v,dict):events.append(v)
        except ValueError:pass
    # Read actual records, including nested step_update metadata and user-facing tool output.
    # Do not export private browser content, internal reasoning, or raw strings.
    def norm(x):return re.sub(r"[^a-z0-9]","",x.lower()) if isinstance(x,str) else ""
    def walk(v,trail=()):
        if isinstance(v,dict):
            yield trail,v
            for k,x in v.items():
                if norm(k) not in {"prompt","input","arguments","thinking","reasoning","thought","signature","instructions","system","user","env","credentials"}:
                    yield from walk(x,trail+(k,))
        elif isinstance(v,list):
            for i,x in enumerate(v):yield from walk(x,trail+(str(i),))
    def strs(v,trail=()):
        if isinstance(v,dict):
            for k,x in v.items():
                if norm(k) not in {"prompt","input","arguments","thinking","reasoning","thought","signature","instructions","system","user","env","credentials"}:
                    yield from strs(x,trail+(k,))
        elif isinstance(v,list):
            for i,x in enumerate(v):yield from strs(x,trail+(str(i),))
        elif isinstance(v,str):yield trail,v
    target=r"ttv[-_]browser(?:[/\\.:_ -]+)list[_ -]?pages"
    # Record per-event metadata separately from text mentions and actual output.
    rows=[];matched=0;calls=0;toolout=0;denied=0;final=0;finalclaim=0;pageout=0
    for i,e in enumerate(events):
        event=e.get("event",e.get("type",""))
        meta=[];out=[];mentions=[];errors=[]
        for trail,n in walk(e):
            names=[norm(n.get(k)) for k in ("name","tool","tool_name","toolName","functionName","serverName","title")]
            server=norm(n.get("server",n.get("serverName","")))
            direct=any(v in {"ttvbrowserlistpages","mcpttvbrowserlistpages"} for v in names) or ("listpages" in names and server=="ttvbrowser")
            typ={norm(n.get(k)) for k in ("event","type","kind","status","state","phase")}
            if direct:
                meta.append({"path":trail,"types":sorted(typ- {""})})
                if typ & {"toolcall","tooluse","mcp","running","inprogress","pending","toolinvocation"}:calls+=1
                if (typ & {"toolresult","toolresponse","toolcompleted","completed","success","succeeded"} or "result" in n or "output" in n) and (n.get("ok") is True or n.get("success") is True or n.get("isError") is False or typ & {"success","succeeded","completed"}) and not n.get("error") and n.get("isError") is not True:
                    toolout+=1
            # Browser MCP list_pages emits a page list or an explicit no-pages result.
            # Count only fields in tool result/output structures, not arbitrary assistant text.
            for k,x in n.items():
                if norm(k) in {"toolresult","tooloutput","toolresponse","result","output","outputtext","toolresulttext"}:
                    if isinstance(x,(dict,list,str)):
                        s="\n".join(v for _,v in strs(x)) if not isinstance(x,str) else x
                        if re.search(r"(?im)^\s*#{1,4}\s*pages\b|^\s*\d+:\s*(?:about:blank|https?://)|no pages (?:found|open)|\bpageId\b",s):
                            if direct or re.search(target,s,re.I) or any("tool" in norm(t) for t in trail):
                                pageout+=1;out.append({"path":trail+(k,),"page_list_shape":True})
        for trail,s in strs(e):
            if re.search(target,s,re.I) or re.search(r"\blist_pages\b",s,re.I):mentions.append({"path":trail,"qualified":bool(re.search(target,s,re.I))})
            if re.search(r"permission check failed|user denied permission|auto.denied|permission denied",s,re.I):errors.append({"path":trail,"type":"denied"})
            if event=="result" and s.strip() and norm(trail[-1] if trail else "") in {"text","response","final","finalresponse","message","output","content","result"}:
                final+=1
                if re.search(r"\b(success|successful|successfully|completed|listed)\b",s,re.I):finalclaim+=1
        if meta or mentions:matched+=1
        if errors:denied+=1
        rows.append({"index":i,"event":event,"keys":sorted(e.keys()),"target_metadata":meta,"target_mentions":mentions,"page_output":out,"errors":errors})
    report={"source_commit":"de49e8547eea9fce6e34f717921a7ec87162dadf","summary":summary,"events":rows,"counts":{"matched_events":matched,"calls":calls,"structured_tool_success":toolout,"page_output":pageout,"denied_events":denied,"final_text_fields":final,"final_success_claims":finalclaim}}
    (run/"event-evidence.json").write_text(json.dumps(report,ensure_ascii=True,indent=2),encoding="utf-8")
    # Owner-local only: retain user-facing final/step tool output and field shapes, not reasoning.
    detail=[]
    for i,e in enumerate(events):
        event=e.get("event",e.get("type",""))
        for trail,s in strs(e):
            last=norm(trail[-1] if trail else "")
            if last in {"text","message","output","result","response","content","error","title","name","status","type"} and (event=="result" or re.search(target,s,re.I) or re.search(r"\blist_pages\b|#{1,4}\s*pages\b|permission|no pages",s,re.I)):
                detail.append({"event":i,"field":trail,"value":s[:4000]})
    (run/"TR04A_EVENT_READOUT.json").write_text(json.dumps(detail,ensure_ascii=False,indent=2),encoding="utf-8")
    return f"TR04E_N{len(events)}_M{matched}_C{calls}_V{toolout}_P{pageout}_D{denied}_F{final}_S{finalclaim}"

try:print(probe())
except Exception as e:
    (run/"readout-error.txt").write_text(type(e).__name__+": "+str(e),encoding="utf-8")
    print("TR04AR_LOCAL_ERROR")
'@
$f=Join-Path $run 'control.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $run 2> (Join-Path $run 'python-stderr.txt'))
$code='TR04AR_LOCAL_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,65}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
