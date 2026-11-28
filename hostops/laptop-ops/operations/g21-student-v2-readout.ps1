Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('NativeBrowserTest\g21-r6-diagnosis-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$py=@'
import os,sys,pathlib,json,re,time,queue,threading,subprocess,shutil,hashlib
root,spool,run=map(pathlib.Path,sys.argv[1:4])
nonce=sys.argv[4]
source="c53d426a89c62b8f0116e61fd2a6a8b33aef68fb"
def read(p,limit=16777216):
    if not p.is_file() or p.is_symlink() or p.stat().st_size>limit:raise ValueError("FILE_BOUND")
    return p.read_text(encoding="utf-8-sig")
def obj(p):return json.loads(read(p))
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=True,indent=2),encoding="utf-8")
def ms(t,start):return round((t-start)*1000)
def main():
    ids=set()
    for p in (spool/"History").glob("receipt-*.json"):
        try:r=obj(p)
        except (OSError,ValueError):continue
        n=r.get("nonce","")
        if r.get("source_commit")==source and r.get("result")=="SUCCESS" and re.fullmatch("[a-f0-9]{32}",str(n)):
            q=obj(spool/"History"/("request-"+n+".json"))
            if q.get("nonce")==n and q.get("source_commit")==source:ids.add(n)
    if len(ids)!=1:return "G21_INIT_RECEIPT_UNRESOLVED"
    prior=root/"NativeBrowserTest"/("g21-r6-mcp-"+next(iter(ids)))
    metrics=obj(prior/"r6-metrics.json")
    if not isinstance(metrics,list) or len(metrics)!=2 or [r.get("mode") for r in metrics]!=["COLD_A","COLD_B"]:return "G21_R6_DIAG_METRICS_UNVERIFIED"
    lines=[];private=[]
    def norm(v):return re.sub(r"\s+"," ",str(v)).strip().casefold()
    def decode(s):
        for m in re.finditer(r"\{",s):
            try:v,_=json.JSONDecoder().raw_decode(s[m.start():])
            except ValueError:continue
            if isinstance(v,dict) and v.get("status") in ("MATCH_FOUND","ACCESS_BLOCKED","UNKNOWN"):return v
        return {}
    for i,(mode,title,url,anchor) in enumerate((("COLD_A","Big Buck Bunny","https://studio.blender.org/projects/big-buck-bunny/","Frankie the squirrel"),("COLD_B","Sintel","https://studio.blender.org/projects/sintel/","baby dragon")),1):
        raw=read(prior/mode/"stdout.jsonl").splitlines()
        ts=[json.loads(x) for x in read(prior/mode/"arrivals.jsonl").splitlines()]
        events=[]
        for line in raw:
            try:e=json.loads(line)
            except ValueError:continue
            if isinstance(e,dict):events.append(e)
        if len(events)!=len(ts) or any(t.get("turn")!=1 or t.get("event")!=e.get("event") for t,e in zip(ts,events)):return "G21_R6_DIAG_TRACE_DRIFT"
        r=metrics[i-1];first=None;final=None;outs=0;errs=0;answer={};outputs=[];errors=[]
        for e,t in zip(events,ts):
            ms=t["elapsed_ms"]
            st=e.get("step_update")
            if isinstance(st,dict) and st.get("tool_name")=="call_mcp_tool":
                if first is None:first=ms
                info=st.get("tool_info") or {}
                if isinstance(info,dict):
                    if info.get("error") or st.get("error"):
                        errs+=1
                        error=json.dumps([info.get("error"),st.get("error"),info.get("output")],ensure_ascii=True)
                        names=[n.upper() for n in ("take_snapshot","list_pages","select_page","evaluate_script","click","navigate_page") if n in json.dumps(info)]
                        flags=[k for k,pat in (("INVALID_ARGUMENT",r"invalid argument|invalid parameter|validation error"),("PAGE_ID",r"page.?id"),("NUMBER",r"number|integer"),("STRING",r"string"),("MISSING",r"missing|required"),("TIMEOUT",r"timeout|timed out"),("NOT_FOUND",r"not found|no such"),("DENIED",r"access denied|forbidden"),("SCHEMA",r"schema|zod"),("UID",r"\buid\b")) if re.search(pat,error,re.I)]
                        errors.append({"ms":ms,"tools":names,"flags":flags,"error":error})
                    if "output" in info:
                        outs+=1
                        out=info["output"]
                        outputs.append(out if isinstance(out,str) else json.dumps(out,ensure_ascii=True))
            v=e.get("result")
            if e.get("event")=="result" and isinstance(v,dict):
                final=ms;answer=decode(v.get("response",""));break
        actual=answer.get("title");ev=answer.get("evidence")
        titleok=norm(actual)==norm(title)
        src=any(url in x for x in outputs)
        fresh=isinstance(ev,str) and 8<=len(ev)<=180 and any(norm(anchor) in norm(x) and norm(ev) in norm(x) for x in outputs)
        if any((r.get("first")!=first,r.get("final")!=final,r.get("outcomes")!=outs,r.get("errors")!=errs,r.get("title")!=titleok,r.get("source")!=src,r.get("fresh")!=fresh,r.get("status")!=answer.get("status"))):return "G21_R6_DIAG_METRIC_DRIFT"
        words=re.findall(r"[A-Za-z0-9]+",actual or "") if isinstance(actual,str) else []
        public_words={"BIG","BUCK","BUNNY","SINTEL","BLENDER","STUDIO","FOUNDATION","OPEN","MOVIE","FILM","SHORT","PROJECT","PROJECTS","THE","2008","2010","DURiAN".upper(),"ANIMATION","ANIMATED","A","BY","PRODUCTION","OFFICIAL"}
        safe="_".join(w.upper() for w in words) if words and len(words)<=16 and all(w.upper() in public_words for w in words) else "OTHER_RETAINED_LOCAL"
        has_expected=bool(re.search(r"(?<!\w)"+re.escape(norm(title))+r"(?!\w)",norm(actual)))
        appears=isinstance(actual,str) and bool(actual.strip()) and any(norm(actual) in norm(x) for x in outputs)
        lines.append(f"G21_FULL_R2_A{i}=MODE:{mode},TITLE_WORDS:{safe},TITLE_EXACT:{int(titleok)},EXPECTED_PRESENT:{int(has_expected)},TITLE_IN_OUTPUT:{int(appears)},SOURCE:{int(src)},FRESH:{int(fresh)},ERRORS:{errs},FINAL_MS:{final}")
        for j,err in enumerate(errors,1):
            lines.append(f"G21_FULL_R2_C{i*10+j}=MODE:{mode},MS:{err['ms']},TOOL:{'+'.join(err['tools']) or 'UNKNOWN'},CLASS:{'+'.join(err['flags']) or 'OTHER'}")
        private.append({"mode":mode,"actual_title":actual,"title_exact":titleok,"title_in_output":appears,"errors":errors})
    write(run/"diagnostic-private.json",private)
    lines.append("G21_FULL_R2_SUMMARY=BOUND:1,ROWS:2,AGY_CALLS:0")
    write(spool/"Receipts"/("g21-full-report-"+nonce+".json"),{"schema":"G21_TRAINING_FULL_REPORT_V1","nonce":nonce,"lines":lines})
    return "G21_R6_DIAG_READY"
try:print(main())
except Exception:
    import traceback
    (run/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("G21_INIT_STUDY_LOCAL_ERROR")
'@
$f=Join-Path $run 'study.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
$code=if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){[string]$out[0]}else{'G21_INIT_STUDY_LOCAL_ERROR'}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
