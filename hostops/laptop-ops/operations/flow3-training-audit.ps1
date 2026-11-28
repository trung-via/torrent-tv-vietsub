# Training-to-production audit: retained teacher trace, latest result and installed module hashes.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('OwnerBridge\backups\flow3-training-audit-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='G2_AUDIT_LOCAL_ERROR'
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

def main():
    # Only retained evidence, no provider, browser, or media action.
    n=matching("2487de73a7f4d65e5fbb7e7d1f5f73acf7a838c9","G21_TEACHER_ACCESS_BLOCKED")
    teacher=root/"NativeBrowserTest"/("g21-teacher-"+n)
    doc=read_doc(teacher/"BRAIN_RESULT.json")
    metrics=doc.get("metrics",{})
    need(metrics.get("status")=="ACCESS_BLOCKED" and metrics.get("model")=="gemini-4-neon-high" and metrics.get("source_commit")=="2487de73a7f4d65e5fbb7e7d1f5f73acf7a838c9","TEACHER_BIND")
    trace=teacher/"agy-stdout.jsonl"
    need(trace.stat().st_size<=16*1024*1024,"TRACE_SIZE")
    # Distinguish model report, tool failure and explicit challenge wording.
    # Never print private page content or source locators.
    strong=0; weak=0; errors=0; reads=0
    explicit=re.compile(r"(?im)^\s*(?:title\s*[:=]\s*|(?:\d+\s+)?heading\s+)?[\"']?(?:access denied|403 forbidden|verify (?:you are|that you are) human|just a moment|making sure you.re not a bot)[.!…]?[\"']?\s*$")
    loose=re.compile(r"access denied|403 forbidden|verify (?:you are|that you are) human|captcha|just a moment|making sure you.re not a bot",re.I)
    for line in safe_file(trace).decode("utf-8-sig").splitlines():
        try:e=json.loads(line)
        except ValueError:continue
        st=e.get("step_update") if isinstance(e,dict) else None
        if not isinstance(st,dict) or st.get("tool_name")!="call_mcp_tool":continue
        info=st.get("tool_info")
        if not isinstance(info,dict):continue
        if info.get("error") or st.get("error"):errors+=1
        output=info.get("output")
        if isinstance(output,str):
            reads+=1
            strong+=int(bool(explicit.search(output)))
            weak+=int(bool(loose.search(output)))
    latest=hashlib.sha256(b"ttv-production-movie-v1:7235976175").hexdigest()[:32]
    req=read_doc(owner/"backups"/("production-movie-"+latest)/"private-request.json")
    rec=read_doc(inbox/("g2-"+latest+".receipt.json"))
    need(req.get("request_id")==latest and rec.get("request_id")==latest and rec.get("status")=="COMPLETE","LATEST_BIND")
    rows=rec.get("results",[])
    need(len(rows)==1 and rows[0].get("owner_request_id")==latest and rows[0].get("status")=="NO_MATCH","LATEST_RESULT")
    need(req.get("source_url")=="https://webtorrent.io/free-torrents","LATEST_SOURCE")
    # Compare normalized installed bytes to the exact merged modules.
    expected={"agy_owner_warm_session.py":"9cbc45c643d99cc9655fe9a7357eafd07cd227d0","owner_g2_discovery.py":"dedc863037161ec68df98f6db237f5e83518ddef","owner_g2_inbox.py":"de6830921b648d292c679aa4957b4cee5e69e5f0","owner_g2_submit.py":"0eafd74eeb08dac8d461a353dbe96447e5a783c1"}
    flags=[]; hashes={}
    for name,want in expected.items():
        path=d2/name
        if not path.exists():flags.append("A");continue
        actual=blob(safe_file(path).replace(b"\r\n",b"\n"))
        hashes[name]=actual;flags.append("M" if actual==want else "D")
    (run/"audit.json").write_text(json.dumps({"teacher":{"read_events":reads,"strong":strong,"weak":weak,"errors":errors,"recipe_count":len(metrics.get("recipe_codes",[]))},"latest":{"source":"OPEN_CATALOG","status":"NO_MATCH"},"installed_hashes":hashes,"expected":expected},indent=2),encoding="utf-8")
    return "G2_AUDIT_"+ "".join(flags)+"_TREAD"+str(reads)+"_STRONG"+str(strong)+"_WEAK"+str(weak)+"_ERR"+str(errors)+"_RECIPE"+str(len(metrics.get("recipe_codes",[])))+"_CATALOG_NOMATCH"
try: print(main())
except Hold as e: print("G2_AUDIT_HOLD_"+str(e))
except Exception:
    import traceback
    (run/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("G2_AUDIT_LOCAL_ERROR")
'@
$f=Join-Path $run 'deploy.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $run $spool $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
}catch{[IO.File]::WriteAllText((Join-Path $run 'host-private-error.txt'),($_|Out-String),[Text.UTF8Encoding]::new($false))}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
