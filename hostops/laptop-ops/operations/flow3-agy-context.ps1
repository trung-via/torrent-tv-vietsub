# Offline structural context diagnosis of two completed traces. No provider, CDP, playback, or installed code changes.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('OwnerBridge\backups\flow3-agy-context-detail-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='F3_DETAIL_LOCAL_ERROR'
try {
$py=@'
import hashlib,json,pathlib,re,sys
root,run,spool=map(pathlib.Path,sys.argv[1:4])
nonce=sys.argv[4]
owner=root/"OwnerBridge"; d2=owner/"app/poc/p2-sub-discovery"
inbox=owner/"inbox"; cache=root/"subtitle-trials"
class Hold(Exception):pass
def need(ok,reason):
    if not ok:raise Hold(reason)
def blob(b):return hashlib.sha1(b"blob "+str(len(b)).encode()+b"\0"+b).hexdigest()
def safe_file(p):
    need(p.is_file() and not p.is_symlink() and not (p.stat().st_file_attributes & 1024),"FILE_IDENTITY")
    return p.read_bytes()
def read_doc(p):
    return json.loads(safe_file(p).decode("utf-8-sig"))
def matching(source_commit,reason):
    found=set()
    for folder in (spool/"History",spool/"Receipts"):
        for p in folder.glob("receipt*.json"):
            try:r=read_doc(p)
            except (OSError,ValueError,Hold):continue
            n=r.get("nonce","")
            if r.get("source_commit")!=source_commit or r.get("result")!="SUCCESS" or not re.fullmatch(r"[a-f0-9]{32}",str(n)):continue
            s=read_doc(spool/"Receipts"/("odyssey-stage-"+n+".json"))
            if s.get("nonce")==n and s.get("reason")==reason:found.add(n)
    need(len(found)==1,"PRIOR_RECEIPT")
    return next(iter(found))

# Diagnostic only: classify fixed vocabulary and structure, never emit raw page content.
def context_flags(output):
    need(isinstance(output,str),"OUTPUT_TYPE")
    wrapper=re.fullmatch(r"(?is)(?:script ran on page and returned:|result:)\s*\x60{3}(?:json|text)?\s*\n(.*?)\n\x60{3}\s*",output.strip())
    need(wrapper is not None,"WRAPPER_DRIFT")
    obj=json.loads(wrapper.group(1))
    need(isinstance(obj,dict),"DICT_DRIFT")
    # Fixed semantic vocabulary only. Never emit unrecognized names or values.
    groups={
        "T":("title","pagetitle","documenttitle","heading","headings"),
        "B":("body","bodytext","bodypreview","bodyexcerpt","bodysample","bodysnippet","bodytextsnippet","text","textpreview","textexcerpt","textsample","textsnippet","textcontent","innertext","visibletext","pagetext","pagecontent","content","snippet","preview","description"),
        "U":("url","href","src","location","pathname","link","links","urls","origin"),
        "H":("html","outerhtml","innerhtml","script","scripts","class","classname","id","attributes","markup"),
        "M":("captcha","hascaptcha","captchavisible","captchatext","captchamarkers","challenge","challengevisible","challengepresent","challengemarkers","markers","signals","blocked","blockreason","accessblocked","isblocked","verification","status","error","reason","message","checks","flags","matches","indicators","detected","detection"),
        "R":("results","rows","items","candidates","releases","name","releasename","text"),
    }
    def tag(k):
        k=re.sub(r"[^a-z0-9]","",k.lower())
        for label,keys in groups.items():
            if k in keys:return label
        if re.search(r"captcha|challenge|verif|block|marker|detect|signal",k):return "M"
        if re.search(r"body|text|content|preview|snippet",k):return "B"
        return "X"
    present=set()
    matched=set()
    contexts=set()
    def walk(v,anc=()):
        if isinstance(v,dict):
            for k,x in v.items():
                t=tag(k)
                present.add(t)
                walk(x,anc+(t,))
        elif isinstance(v,list):
            for x in v:walk(x,anc)
        elif isinstance(v,str) and re.search(r"captcha",v,re.I):
            matched.add(anc[-1] if anc else "X")
            if "M" in anc:matched.add("M")
            if re.fullmatch(r"(?i)\s*captcha\s*",v):contexts.add("W")
            elif re.fullmatch(r"(?is)\s*https?://\S+\s*",v):contexts.add("U")
            elif re.search(r"(?i)<[^>]{0,250}captcha|captcha[^<]{0,100}>",v):contexts.add("H")
            elif re.search(r"(?i)(verify|human|robot|challenge|security|complete|solve|check|click|enter|failed|required)",v):contexts.add("A")
            else:contexts.add("P")
    walk(obj)
    need(bool(matched),"NO_MATCHED_VALUE")
    return "".join(sorted(present)),"".join(sorted(matched)),"".join(sorted(contexts))

def main():
    from urllib.parse import urlsplit
    def page_arg(params):
        values=[params]
        for key in ("Arguments","arguments","ToolArguments","toolArguments","Args","args","Parameters","parameters"):
            value=params.get(key)
            if isinstance(value,str):
                try:value=json.loads(value)
                except ValueError:continue
            if isinstance(value,dict):values.append(value)
        for v in values:
            p=v.get("pageId")
            if type(p) is int and p>=0:return p
        return None
    def source_page(output,host):
        if not isinstance(output,str):return None
        found=[]
        for line in output.splitlines():
            m=re.match(r"^\s*(\d+):\s*(.*)$",line)
            if not m:continue
            urls=re.findall(r"https?://[^\s\]\)<>\"']+",m[2],re.I)
            if len(urls)!=1:continue
            try:
                u=urlsplit(urls[0])
                if u.scheme=="https" and u.hostname==host and not u.username and not u.password and u.port in (None,443):
                    found.append(int(m[1]))
            except ValueError:continue
        return found[0] if len(found)==1 else None
    pattern=re.compile(r"access denied|403 forbidden|verify (?:you are|that you are) human|making sure you.re not a bot|anti.bot challenge|just a moment|captcha",re.I)
    explicit=re.compile(r"(?im)^\s*(?:title\s*[:=]\s*|(?:\d+\s+)?heading\s+)?[\"']?(?:access denied|403 forbidden|verify (?:you are|that you are) human|making sure you.re not a bot|just a moment)(?:[.!…]|\.\.\.)?[\"']?\s*$")
    def read_attempt(commit,stage,folder):
        n=matching(commit,stage)
        req=read_doc(owner/"backups"/(folder+n)/"private-request.json")
        need(req.get("request_id")==n and req.get("schema")=="TTV-OWNER-G2-METADATA-V1","REQ_BIND")
        receipt=read_doc(inbox/("g2-"+n+".receipt.json"))
        batch=cache/"movie-discovery"/".native-v13"/("g2-"+n)
        terminal=read_doc(batch/"terminal.json")
        need(receipt.get("request_id")==n and receipt.get("reason")=="AGY_STREAM_ACCESS_BLOCKED" and terminal.get("owner_request_id")==n and terminal.get("reason")=="AGY_STREAM_ACCESS_BLOCKED","RESULT_BIND")
        host=urlsplit(req.get("source_url","")).hostname
        need(host=="ext.to","SOURCE_BIND")
        outcomes=[]
        for f in sorted(batch.glob("*/agy-stdout.jsonl")):
            need(f.stat().st_size<=16*1024*1024,"TRACE_SIZE")
            pending=None; selected=None
            for line in safe_file(f).decode("utf-8").splitlines():
                try:e=json.loads(line)
                except ValueError:continue
                st=e.get("step_update") if isinstance(e,dict) else None
                if not isinstance(st,dict) or st.get("tool_name")!="call_mcp_tool":continue
                info=st.get("tool_info")
                if not isinstance(info,dict):continue
                params=info.get("parameters")
                if isinstance(params,dict) and params.get("ToolName"):
                    pending=(params.get("ToolName"),next((params[k] for k in ("ServerName","Server","serverName","server") if isinstance(params.get(k),str)),None),page_arg(params))
                if "output" not in info and not info.get("error"):continue
                if pending and pending[1]=="ttv-browser":
                    output=info.get("output","")
                    err=bool(info.get("error") or st.get("error"))
                    if pattern.search(str(output)):
                        bound=not err and selected is not None and pending[0] in ("evaluate_script","take_snapshot") and pending[2]==selected
                        strong=isinstance(output,str) and bool(explicit.search(output))
                        tool={"list_pages":"L","take_snapshot":"S","evaluate_script":"E"}.get(pending[0],"O")
                        shape,signal,field=context_flags(output)
                        outcomes.append({"tool":tool,"bound":bound,"strong":strong,"error":err,"shape":shape,"signal":signal,"field":field})
                        break
                    if not err and pending[0]=="list_pages":selected=source_page(output,host)
                pending=None
        need(len(outcomes)==1,"TRACE_OUTCOME_AMBIGUOUS")
        return outcomes[0]
    a=read_attempt("7fcc7d666a6fac8076f7916fffc471c7bd0230a9","FLOW3_AGY_HOLD_AGY_STREAM_ACCESS_BLOCKED","flow3-agy-metadata-")
    b=read_attempt("10e3c1e43e0133313292eb61c864661d0a87e5ab","FLOW3_POST_HUMAN_HOLD_AGY_STREAM_ACCESS_BLOCKED","flow3-post-human-verification-")
    installed=blob(safe_file(d2/"agy_owner_warm_session.py").replace(b"\r\n",b"\n"))=="9cbc45c643d99cc9655fe9a7357eafd07cd227d0"
    need(all(x["tool"]=="E" and x["bound"] and not x["strong"] and not x["error"] for x in (a,b)),"TRACE_FLAGS_DRIFT")
    (run/"diagnosis.json").write_text(json.dumps({"before":a,"after":b,"installed_old_source":installed},indent=2),encoding="utf-8")
    def compact(x):return x["shape"]+"_"+x["signal"]+"_"+x["field"]
    return "F3_DETAIL_B_"+compact(a)+"_A_"+compact(b)
try: print(main())
except Hold as e: print("F3_DETAIL_HOLD_"+str(e))
except Exception:
    import traceback
    (run/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("F3_DETAIL_LOCAL_ERROR")
'@
$f=Join-Path $run 'deploy.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $run $spool $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
}catch{[IO.File]::WriteAllText((Join-Path $run 'host-private-error.txt'),($_|Out-String),[Text.UTF8Encoding]::new($false))}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
