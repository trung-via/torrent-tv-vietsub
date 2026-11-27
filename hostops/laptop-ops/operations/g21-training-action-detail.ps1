Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('g21-detail-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$py=@'
import pathlib,sys,json,re
root,spool,run=map(pathlib.Path,sys.argv[1:])
source="2487de73a7f4d65e5fbb7e7d1f5f73acf7a838c9"
def read(p,limit=16777216):
    if not p.is_file() or p.is_symlink() or p.stat().st_size>limit:return ""
    return p.read_text(encoding="utf-8-sig",errors="replace")
def obj(p):
    try:
        v=json.loads(read(p))
        return v if isinstance(v,dict) else {}
    except ValueError:return {}
prior=[]
for p in (spool/"History").glob("receipt-*.json"):
    v=obj(p);n=v.get("nonce","")
    if v.get("source_commit")!=source or v.get("result")!="SUCCESS" or not re.fullmatch("[a-f0-9]{32}",str(n)):continue
    q=obj(spool/"History"/("request-"+n+".json"))
    if q.get("nonce")==n and q.get("source_commit")==source:prior.append((q.get("requested_utc_epoch",0),n))
if len(prior)!=2:print("G21_READOUT_RECEIPT_COUNT_"+str(len(prior)));sys.exit(0)
reports=[];parts=[]
known={"list_pages":"LP","select_page":"SP","navigate_page":"NV","take_snapshot":"SN","click":"CL","fill":"FL","press_key":"PK","wait_for":"WF","evaluate_script":"EV"}
for _,n in sorted(prior):
    d=root/("g21-teacher-"+n)
    report=obj(d/"BRAIN_HANDOFF.json")
    result=obj(d/"BRAIN_RESULT.json")
    if report.get("source_commit")!=source or result.get("metrics")!=report:print("G21_READOUT_REPORT_DRIFT");sys.exit(0)
    raw=read(d/"agy-stdout.jsonl")
    stderr=read(d/"agy-stderr.txt")
    events=[];details=[];query=False;bad=0;calls=0;outputs=0;errors=0;last="NA";pending="NA";block=False
    for line in raw.splitlines():
        try:e=json.loads(line)
        except ValueError:bad+=1;continue
        if not isinstance(e,dict):continue
        st=e.get("step_update")
        if not isinstance(st,dict) or st.get("tool_name")!="call_mcp_tool":continue
        info=st.get("tool_info")
        if not isinstance(info,dict):info={}
        params=info.get("parameters")
        if not isinstance(params,dict):params={}
        name=params.get("ToolName")
        name=known.get(name,"OT") if isinstance(name,str) else "OT"
        if name=="OT" and pending!="NA":name=pending
        err=bool(info.get("error") or st.get("error"))
        if err or "output" in info:
            outputs+=1;errors+=int(err);last=name;pending="NA"
            data=json.dumps(info.get("output",""),ensure_ascii=True)
            hit=bool(re.search(r"captcha|access denied|403 forbidden|just a moment|verify (?:you are|that you are) human|checking your browser|cloudflare",data,re.I))
            block |= hit
            details.append(name+("E" if err else "B" if hit else "O")+("Q" if query else "N"))
            query=False
            events.append(name+("E" if err else "O"))
        else:
            calls+=1;pending=name;events.append(name+"C")
            query=bool(re.search(r"big[ +%20._-]+buck[ +%20._-]+bunny",json.dumps(params,ensure_ascii=True),re.I))
    final=result.get("model_final",{})
    if not isinstance(final,dict):final={}
    status=report.get("status")
    if status not in ("ACCESS_BLOCKED","TIMEOUT"):print("G21_READOUT_UNEXPECTED_STATUS");sys.exit(0)
    errclass="QUOTA" if re.search(r"quota exceeded|resource.exhausted|rate limit",stderr,re.I) else "MCP" if re.search(r"mcp.{0,40}(?:failed|error)|connection refused",stderr,re.I) else "AUTH" if re.search(r"authentication failed|not authenticated",stderr,re.I) else "OTHER" if stderr.strip() else "NONE"
    elapsed=round(float(report.get("elapsed_seconds",0)))
    reports.append({"status":status,"elapsed_seconds":elapsed,"calls":calls,"outputs":outputs,"errors":errors,"last_completed_tool":last,"last_pending_tool":pending,"block_evidence_in_tool_output":block,"stderr_class":errclass,"invalid_json_lines":bad,"event_trace":events[:100],"recipe_codes":report.get("recipe_codes",[])})
    count=report.get("candidate_count",0)
    if type(count) is not int or not 0<=count<=9999:count=9999
    parts.append(("B" if status=="ACCESS_BLOCKED" else "T")+"F"+str(int(bool(final)))+"C"+str(count)+"_"+"".join(details))
(run/"BRAIN_DIAGNOSTIC.json").write_text(json.dumps(reports,indent=2),encoding="utf-8")
code="G21_ACT_"+ "_".join(parts)
print(code if len(code)<=90 else "G21_READOUT_SUMMARY_TOO_LONG")
'@
$f=Join-Path $run 'readout.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run 2> (Join-Path $run 'python-stderr.txt'))
$code=if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){[string]$out[0]}else{'G21_READOUT_LOCAL_ERROR'}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
