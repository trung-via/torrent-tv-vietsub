Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('g21-full-report-'+$rq.nonce)
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
reports=[]
lines=[]
known={"list_pages":"LIST_PAGES","select_page":"SELECT_PAGE","navigate_page":"NAVIGATE_PAGE","take_snapshot":"TAKE_SNAPSHOT","click":"CLICK","fill":"FILL","press_key":"PRESS_KEY","wait_for":"WAIT_FOR","evaluate_script":"EVALUATE_SCRIPT"}
def flags(s,patterns):
    return "+".join(k for k,p in patterns if re.search(p,s,re.I)) or "NONE"
actions=[("QUERY",r"big[ +%20._-]+buck[ +%20._-]+bunny"),("FORM",r"\bform\b|searchinput|search_input|input\[|input\.|input#"),("SUBMIT",r"\.submit\(|requestSubmit|dispatchEvent|\.click\(|press_key"),("NAVIGATION",r"location\.href|location\.assign|location\.replace|window\.open|navigate_page"),("DOM_SELECT",r"querySelector|getElementById|getElementsBy|querySelectorAll"),("TEXT_READ",r"innerText|textContent|document\.title"),("LINK_READ",r"\.href|a\[href|\.links"),("ROW_READ",r"\brows\b|tbody|querySelectorAll\(.{0,30}tr|table|torrent"),("SEED_READ",r"seeders?|seeds"),("SIZE_READ",r"\bsize\b|filesize|[0-9]\s*[GM]i?B"),("RESOLUTION",r"1080p|720p|2160p|resolution"),("SORT",r"\.sort\(|sortBy|orderBy|sort=")]
signals=[("BLOCK",r"captcha|access denied|403 forbidden|just a moment|verify (?:you are|that you are) human|checking your browser|cloudflare"),("QUERY",actions[0][1]),("SEED",r"seeders?|seeds"),("SIZE",r"\bsize\b|[0-9.]+\s*[GM]i?B"),("RESULT",r"\bresults?\b|no torrents|no matches|nothing found"),("1080P",r"1080p"),("720P",r"720p"),("2160P",r"2160p"),("EXT_TO",r"(?:www\.)?ext\.to")]
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
    d=root/("g21-teacher-"+n)
    report=obj(d/"BRAIN_HANDOFF.json")
    result=obj(d/"BRAIN_RESULT.json")
    if report.get("source_commit")!=source or result.get("metrics")!=report:print("G21_FULL_REPORT_DRIFT");sys.exit(0)
    raw=read(d/"agy-stdout.jsonl")
    final=result.get("model_final",{})
    if not isinstance(final,dict):final={}
    rec=[x for x in report.get("recipe_codes",[]) if isinstance(x,str) and x in recipes]
    lines.append(f"G21_FULL_R{ri}_SUMMARY=PROCESS:{safe_status(report.get('status'))},MODEL:{safe_status(final.get('status'))},CANDIDATES:{report.get('candidate_count',0) if type(report.get('candidate_count')) is int else 0}")
    lines.append(f"G21_FULL_R{ri}_RECIPE="+("+".join(rec[:16]) or "NONE"))
    pending=None; i=0; eventrows=[]
    for line in raw.splitlines():
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
            name,features,plen=pending if pending else (name,"UNKNOWN",0)
            data=json.dumps(info.get("output",""),ensure_ascii=True)
            out=flags(data,signals)
            row=f"G21_FULL_R{ri}_A{i}={name},ACTION:{features},PARAM_BYTES:{plen},OUTPUT_BYTES:{len(data.encode())},SIGNALS:{out},RESULT:{'ERROR' if err else 'RETURNED'}"
            lines.append(row);eventrows.append(row);pending=None
        else:
            p=json.dumps(params,ensure_ascii=True)
            pending=(name,flags(p,actions),len(p.encode()))
    candidates=final.get("candidates",[])
    if not isinstance(candidates,list):candidates=[]
    for ci,c in enumerate(candidates[:20],1):
        if not isinstance(c,dict):
            lines.append(f"G21_FULL_R{ri}_C{ci}=NON_OBJECT");continue
        title=get(c,("title","name","release","release_name","filename","torrent_name"))
        title=title if isinstance(title,str) else ""
        combined=json.dumps(c,ensure_ascii=True)
        res=next((r.upper() for r in ("2160p","1080p","720p","480p","576p","360p") if re.search(r"\b"+r+r"\b",combined,re.I)),"UNKNOWN")
        match=bool(re.search(r"big[ ._-]+buck[ ._-]+bunny",title,re.I))
        year=get(c,("year","release_year"))
        if year is None:
            m=re.search(r"\b(19\d{2}|20\d{2})\b",title);year=m[1] if m else None
        year=num(year)
        year=str(int(year)) if year is not None and 1900<=year<=2100 else "UNKNOWN"
        seed=num(get(c,("seeds","seeders","seed","seed_count","reported_seeds","reported_seeders")))
        seed=str(int(seed)) if seed is not None and 0<=seed<=100000000 else "UNKNOWN"
        mb=size_mb(get(c,("size","reported_size","file_size","total_size","size_text")))
        if mb is None:
            b=num(get(c,("size_bytes","total_bytes","bytes")))
            if b is not None:mb=round(b/1000000)
        fmt=flags(combined,[("H264",r"h[ ._-]?264|x264|avc"),("H265",r"h[ ._-]?265|x265|hevc"),("AV1",r"\bav1\b"),("VP9",r"\bvp9\b"),("MKV",r"\bmkv\b"),("MP4",r"\bmp4\b"),("WEB_DL",r"web[ ._-]?dl"),("BLURAY",r"blu[ ._-]?ray|bdrip")])
        lines.append(f"G21_FULL_R{ri}_C{ci}=TITLE_MATCH:{int(match)},YEAR:{year},RES:{res},SIZE_MB:{mb if mb is not None else 'UNKNOWN'},SEEDS:{seed},FORMAT:{fmt}")
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
