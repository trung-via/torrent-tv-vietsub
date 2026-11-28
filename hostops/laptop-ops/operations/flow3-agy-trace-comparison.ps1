# Read-only comparison of two completed G2 traces. No provider, CDP, playback, or browser changes.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('OwnerBridge\backups\flow3-agy-trace-comparison-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='FLOW3_TRACE_LOCAL_ERROR'
try {
$py=@'
import ast,hashlib,json,os,pathlib,re,shutil,subprocess,sys,time,urllib.request,difflib
root,run,spool=map(pathlib.Path,sys.argv[1:4])
nonce=sys.argv[4]
owner=root/"OwnerBridge"; app=owner/"app"; d2=app/"poc/p2-sub-discovery"; launcher=owner/"start-owner-session-agent.ps1"
inbox=owner/"inbox"; state=root/"P2/auto-lean120-state"; cache=root/"subtitle-trials"
base="b0e0cba86a09a7353c416536088d666363f3676c"; head="47c265fc908171ab18bb0707b2e26b014fb39d40"
new={"agy_owner_warm_session.py":"9cbc45c643d99cc9655fe9a7357eafd07cd227d0","owner_g2_discovery.py":"2707298aaa10e38c79f44505a6853ed31336ff0d","owner_g2_submit.py":"196da5a5e560faa9f780428073e67a75e956d73b","owner_movie_handoff.py":"0e5d351af58d089bd53d3fd78b4a6f46509ecbbb"}
shared={"agy_v13_native_producer.py":("20e9c725bce400593ae9a5ba27eda19f2aed797f","cfd8af916f73eff84cbb46ca75f0eab184540641"),"owner_p3_p4_runtime.py":("f8b6aa4b22647190e372d91f5bda045e7f17a326","33277f5ea67cabf95cb096ba87a6c2c659bfb6e1"),"owner_session_bridge.py":("6c0d14c66e401f5cdb9ac0ccd2974208355b167f","3b6faaeb4481ea8c1a06b0bcd777dbdad336070e")}
class Hold(Exception):pass
def need(ok,reason):
    if not ok:raise Hold(reason)
def blob(b):return hashlib.sha1(b"blob "+str(len(b)).encode()+b"\0"+b).hexdigest()
def norm(b):return b.replace(b"\r\n",b"\n")
def ps(s,timeout=20):
    p=subprocess.run(["pwsh","-NoProfile","-NonInteractive","-Command","$ErrorActionPreference='Stop';"+s],capture_output=True,encoding="utf-8",errors="replace",timeout=timeout)
    need(p.returncode==0,"TASK_OR_PS_FAILED")
    return p.stdout.strip()
def q(s):return "'"+str(s).replace("'","''")+"'"
def write_doc(name,v):(run/name).write_text(json.dumps(v,indent=2),encoding="utf-8")
def safe_file(p):
    need(p.is_file() and not p.is_symlink() and not (p.stat().st_file_attributes & 1024),"FILE_IDENTITY")
    return p.read_bytes()
def source(ref,name,expected):
    url=f"https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/{ref}/poc/p2-sub-discovery/{name}"
    with urllib.request.urlopen(url,timeout=25) as f:b=f.read(2_000_000)
    need(blob(b)==expected,"SOURCE_HASH")
    return b
def task_info():
    return json.loads(ps(r"""$t=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\';$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;$u=[string]$t.Principal.UserId;if($u -notmatch '^S-1-'){$u=([Security.Principal.NTAccount]::new($u)).Translate([Security.Principal.SecurityIdentifier]).Value};if($u -cne $sid -or $t.Principal.LogonType -ine 'Interactive' -or @($t.Actions).Count -ne 1){throw 'TASK_IDENTITY'};$a=$t.Actions[0];if([IO.Path]::GetFileName([string]$a.Execute) -ine 'pwsh.exe' -or [string]$a.Arguments -notmatch '^(-NoLogo\s+-NoProfile\s+-NonInteractive\s+-File\s+)' -or ([string]$a.Arguments -replace '^(-NoLogo\s+-NoProfile\s+-NonInteractive\s+-File\s+)','').Trim('"') -ine """+q(launcher)+r"""){throw 'TASK_ACTION'};([pscustomobject]@{state=([string]$t.State).ToUpperInvariant();enabled=[bool]$t.Settings.Enabled}|ConvertTo-Json -Compress)"""))
def task():return task_info()["state"]
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
def apply_context(old,baseline,target):
    # Apply only exact unique G2 hunks on the installed text. No fuzzy merge.
    old,baseline,target=map(norm,(old,baseline,target))
    if old==baseline:return target
    if old==target:return old
    lines=old.splitlines(keepends=True); b=baseline.splitlines(keepends=True); t=target.splitlines(keepends=True)
    groups=list(difflib.SequenceMatcher(None,b,t,autojunk=False).get_grouped_opcodes(3))
    for group in groups:
        start,end=group[0][1],group[-1][2]; ts,te=group[0][3],group[-1][4]
        before=b[start:end]; after=t[ts:te]
        hits=[i for i in range(len(lines)-len(before)+1) if lines[i:i+len(before)]==before]
        need(len(hits)==1,"SHARED_CONTEXT_CONFLICT")
        i=hits[0];lines[i:i+len(before)]=after
    return b"".join(lines)
def replace(p,b):
    tmp=p.with_name("."+p.name+".g2-"+nonce+".tmp")
    with tmp.open("xb") as f:f.write(b);f.flush();os.fsync(f.fileno())
    os.replace(tmp,p)
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
                        outcomes.append({"tool":tool,"bound":bound,"strong":strong,"error":err})
                        break
                    if not err and pending[0]=="list_pages":selected=source_page(output,host)
                pending=None
        need(len(outcomes)==1,"TRACE_OUTCOME_AMBIGUOUS")
        return outcomes[0]
    a=read_attempt("7fcc7d666a6fac8076f7916fffc471c7bd0230a9","FLOW3_AGY_HOLD_AGY_STREAM_ACCESS_BLOCKED","flow3-agy-metadata-")
    b=read_attempt("10e3c1e43e0133313292eb61c864661d0a87e5ab","FLOW3_POST_HUMAN_HOLD_AGY_STREAM_ACCESS_BLOCKED","flow3-post-human-verification-")
    installed=blob(norm(safe_file(d2/"agy_owner_warm_session.py")))==new["agy_owner_warm_session.py"]
    write_doc("diagnosis.json",{"before":a,"after":b,"installed_old_source":installed})
    def compact(x):
        return x["tool"]+"B"+str(int(x["bound"]))+"S"+str(int(x["strong"]))+"E"+str(int(x["error"]))
    return "FLOW3_TRACE_BEFORE_"+compact(a)+"_AFTER_"+compact(b)+"_SRC"+str(int(installed))
try: print(main())
except Hold as e: print("FLOW3_TRACE_HOLD_"+str(e))
except Exception:
    import traceback
    (run/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("FLOW3_TRACE_LOCAL_ERROR")
'@
$f=Join-Path $run 'deploy.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $run $spool $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
}catch{[IO.File]::WriteAllText((Join-Path $run 'host-private-error.txt'),($_|Out-String),[Text.UTF8Encoding]::new($false))}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
