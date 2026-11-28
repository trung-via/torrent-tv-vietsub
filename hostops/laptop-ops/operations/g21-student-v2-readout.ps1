Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('g21-student-readout-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$py=@'
import pathlib,sys,json,re
root,spool,run=map(pathlib.Path,sys.argv[1:4])
source="99ff9d03ff90bae805ae6235108b1894ff1a002f"
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
if len(prior)!=1:print("G21_READOUT_RECEIPT_COUNT_"+str(len(prior)));sys.exit(0)
reports=[]
lines=[]
known={"list_pages":"LIST_PAGES","select_page":"SELECT_PAGE","navigate_page":"NAVIGATE_PAGE","take_snapshot":"TAKE_SNAPSHOT","click":"CLICK","fill":"FILL","press_key":"PRESS_KEY","wait_for":"WAIT_FOR","evaluate_script":"EVALUATE_SCRIPT"}
def flags(s,patterns):
    return "+".join(k for k,p in patterns if re.search(p,s,re.I)) or "NONE"
actions=[("QUERY",r"wicker"),("FORM",r"\bform\b|searchinput|search_input|input\[|input\.|input#"),("SUBMIT",r"\.submit\(|requestSubmit|dispatchEvent|\.click\(|press_key"),("NAVIGATION",r"location\.href|location\.assign|location\.replace|window\.open|navigate_page"),("DOM_SELECT",r"querySelector|getElementById|getElementsBy|querySelectorAll"),("TEXT_READ",r"innerText|textContent|document\.title")]
signals=[("BLOCK",r"captcha|access denied|403 forbidden|just a moment|verify (?:you are|that you are) human|checking your browser"),("QUERY",r"wicker"),("YEAR",r"\b2026\b"),("RESULT",r"\bresults?\b|no matches|nothing found"),("EXT_TO",r"(?:www\.)?ext\.to")]
def safe_status(x):
    return x if isinstance(x,str) and x in ("MATCH_FOUND","NO_MATCH","ACCESS_BLOCKED","TOOL_UNAVAILABLE","UNKNOWN","TIMEOUT","CLI_FAILED","MCP_UNVERIFIED","CONFIG_CHANGED") else "UNKNOWN"
def num(value):
    if isinstance(value,bool):return None
    if type(value) in (float,int) and 0<=value<=100000000000000:return value
    if isinstance(value,str):
        v=value.strip().replace(",","")
        if re.fullmatch(r"\d+(?:\.\d+)?",v):return float(v)
    return None
def get(c,keys):
    if not isinstance(c,dict):return None
    for k in keys:
        if k in c:return c[k]
    return None
def size_mb(x):
    if isinstance(x,str):
        m=re.fullmatch(r"\s*(\d+(?:[.,]\d+)?)\s*(B|KB|KIB|MB|MIB|GB|GIB|TB|TIB)\s*",x,re.I)
        if m:
            return round(float(m[1].replace(",","."))*{"B":1/1000000,"KB":.001,"KIB":.001024,"MB":1,"MIB":1.048576,"GB":1000,"GIB":1073.741824,"TB":1000000,"TIB":1099511.627776}[m[2].upper()])
    return None
recipes={"LIST_TASK_TAB","QUERY_TITLE_YEAR","READ_VISIBLE_RESULTS","FILTER_EXACT_TITLE","RANK_SIZE_SEEDS","READ_DETAIL_IF_NEEDED","STOP_ON_DENIAL","MARK_UNKNOWN_METADATA","FINAL_REPORT"}
for ri,(_,n) in enumerate(sorted(prior),1):
    d=root/("g21-student-v2-"+n)
    report=obj(d/"BRAIN_HANDOFF.json")
    result=obj(d/"BRAIN_RESULT.json")
    if report.get("source_commit")!=source or result.get("metrics")!=report:print("G21_FULL_REPORT_DRIFT");sys.exit(0)
    raw=read(d/"agy-stdout.jsonl")
    final=result.get("model_final",{})
    if not isinstance(final,dict):final={}
    rec=[x for x in report.get("recipe_codes",[]) if isinstance(x,str) and x in recipes]
    lines.append(f"G21_FULL_R{ri}_SUMMARY=PROCESS:{report.get('process_state') if report.get('process_state') in ('EXITED','TIMEOUT','FINAL_EXIT_TIMEOUT','CLI_FAILED','CLEANUP_UNVERIFIED') else 'UNKNOWN'},MODEL:{safe_status(final.get('status'))},CANDIDATES:{report.get('candidate_count',0) if type(report.get('candidate_count')) is int else 0}")
    lines.append(f"G21_FULL_R{ri}_RECIPE="+("+".join(rec[:16]) or "NONE"))
    timing={}
    for line in read(d/"event-arrivals.jsonl").splitlines():
        try:t=json.loads(line)
        except ValueError:continue
        if type(t.get("ordinal")) is int and type(t.get("elapsed_ms")) is int:timing[t["ordinal"]]=t["elapsed_ms"]
    if len(timing)!=len(raw.splitlines()):print("G21_TIMING_DRIFT");sys.exit(0)
    def ms(x):return str(x) if type(x) is int and x>=0 else "UNKNOWN"
    lines.append(f"G21_FULL_R{ri}_TIMING=FIRST_MCP_MS:{ms(report.get('first_mcp_ms'))},LAST_MCP_MS:{ms(report.get('last_mcp_ms'))},FINAL_MS:{ms(report.get('final_ms'))},TOTAL_MS:{round(report.get('elapsed_seconds',0)*1000)}")
    pending=None; i=0; eventrows=[]; last_output=0
    for ordinal,line in enumerate(raw.splitlines(),1):
        try:e=json.loads(line)
        except ValueError:continue
        if not isinstance(e,dict):continue
        st=e.get("step_update")
        if not isinstance(st,dict) or st.get("tool_name")!="call_mcp_tool":continue
        info=st.get("tool_info")
        if not isinstance(info,dict):info={}
        params=info.get("parameters")
        if not isinstance(params,dict):params={}
        name=known.get(params.get("ToolName"),"OTHER") if isinstance(params.get("ToolName"),str) else "OTHER"
        err=bool(info.get("error") or st.get("error"))
        if err or "output" in info:
            i+=1
            name,features,plen,callms=pending if pending else (name,"UNKNOWN",0,None)
            outms=timing.get(ordinal)
            duration=outms-callms if callms is not None and outms is not None else None
            gap=callms-last_output if callms is not None else None
            data=json.dumps(info.get("output",""),ensure_ascii=True)
            out=flags(data,signals)
            row=f"G21_FULL_R{ri}_A{i}={name},ACTION:{features},PARAM_BYTES:{plen},OUTPUT_BYTES:{len(data.encode())},SIGNALS:{out},RESULT:{'ERROR' if err else 'RETURNED'}"
            row+=f",CALL_MS:{ms(callms)},OUT_MS:{ms(outms)},DURATION_MS:{ms(duration)},GAP_MS:{ms(gap)}"
            lines.append(row);eventrows.append(row);pending=None
            if outms is not None:last_output=outms
        else:
            p=json.dumps(params,ensure_ascii=True)
            pending=(name,flags(p,actions),len(p.encode()),timing.get(ordinal))
    candidates=final.get("candidates",[])
    if not isinstance(candidates,list):candidates=[]
    for ci,c in enumerate(candidates[:20],1):
        if not isinstance(c,dict):
            lines.append(f"G21_FULL_R{ri}_C{ci}=NON_OBJECT");continue
        title=get(c,("title","name","release","release_name","filename","torrent_name"))
        title=title if isinstance(title,str) else ""
        match=bool(re.fullmatch(r"wicker(?:\s*\(2026\))?",title,re.I))
        year=num(get(c,("year","release_year")))
        if year is None and re.search(r"\b2026\b",title):year=2026
        year=str(int(year)) if year is not None and 1900<=year<=2100 else "UNKNOWN"
        lines.append(f"G21_FULL_R{ri}_C{ci}=TITLE_MATCH:{int(match)},YEAR:{year}")
    reports.append({"run":ri,"status":safe_status(report.get("status")),"final_status":safe_status(final.get("status")),"recipe":rec,"actions":eventrows})
(run/"BRAIN_FULL_REPORT.json").write_text(json.dumps(reports,indent=2),encoding="utf-8")
nonce=sys.argv[4]
assert re.fullmatch("[a-f0-9]{32}",nonce)
dest=spool/"Receipts"/("g21-full-report-"+nonce+".json")
dest.write_text(json.dumps({"schema":"G21_TRAINING_FULL_REPORT_V1","nonce":nonce,"lines":lines},ensure_ascii=True),encoding="utf-8")
print("G21_FULL_REPORT_READY")
'@
$f=Join-Path $run 'readout.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
$code=if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){[string]$out[0]}else{'G21_READOUT_LOCAL_ERROR'}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
