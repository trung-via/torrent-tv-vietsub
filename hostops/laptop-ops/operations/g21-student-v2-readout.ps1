Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('NativeBrowserTest\g21-session-study-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$py=@'
import os,sys,pathlib,json,re,time,queue,threading,subprocess,shutil,hashlib
root,spool,run=map(pathlib.Path,sys.argv[1:4])
nonce=sys.argv[4]
source="99ff9d03ff90bae805ae6235108b1894ff1a002f"
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
    prior=root/"NativeBrowserTest"/("g21-student-v2-"+next(iter(ids)))
    metrics=obj(prior/"BRAIN_HANDOFF.json")
    result=obj(prior/"BRAIN_RESULT.json")
    if metrics.get("source_commit")!=source or result.get("metrics")!=metrics:return "G21_INIT_BIND_DRIFT"
    raw=read(prior/"agy-stdout.jsonl").splitlines()
    ts=[json.loads(x) for x in read(prior/"event-arrivals.jsonl").splitlines()]
    if len(raw)!=len(ts) or any(t.get("ordinal")!=i for i,t in enumerate(ts,1)):return "G21_INIT_TIMING_DRIFT"
    lines=[]; private=[]; first={}; mcp=[]
    for i,(line,t) in enumerate(zip(raw,ts),1):
        try:e=json.loads(line)
        except ValueError:e={}
        if not isinstance(e,dict):e={}
        t=t["elapsed_ms"]
        event=e.get("event")
        kind=event.upper() if isinstance(event,str) and re.fullmatch(r"[a-zA-Z_]{1,30}",event) else "UNKNOWN"
        first.setdefault(kind,t)
        st=e.get("step_update")
        info=st.get("tool_info",{}) if isinstance(st,dict) else {}
        if not isinstance(info,dict):info={}
        private.append({"ordinal":i,"ms":t,"event":kind,"keys":list(e),"step_keys":list(st) if isinstance(st,dict) else []})
        if isinstance(st,dict) and st.get("tool_name")=="call_mcp_tool":
            k="ERROR" if info.get("error") or st.get("error") else "OUTPUT" if "output" in info else "CALL_OR_UPDATE"
            mcp.append((t,k))
            if k=="ERROR":
                msg=json.dumps([info.get("error"),st.get("error"),info.get("output")],ensure_ascii=True)
                patterns=[("TIMEOUT",r"timed? ?out|timeout"),("NOT_FOUND",r"not found|no such"),("NO_SNAPSHOT",r"snapshot.{0,40}(missing|not available|not found|first)"),("NOT_CONNECTED",r"not connected|disconnected"),("DENIED",r"permission denied|access denied|forbidden"),("INVALID_ARGUMENT",r"invalid argument|invalid parameter|validation error")]
                flags=[k for k,p in patterns if re.search(p,msg,re.I)]
                lines.append("G21_FULL_R1_A1=ERROR_CLASS:"+("+".join(flags) or "OTHER"))
    lines.append("G21_FULL_R1_SUMMARY=TRACE_EVENTS:"+str(len(raw))+",MCP_UPDATES:"+str(len(mcp)))
    for i,(kind,t) in enumerate(first.items(),2):
        if i>30:break
        lines.append(f"G21_FULL_R1_A{i}=FIRST_EVENT:{kind},MS:{t}")
    for i,(t,k) in enumerate(mcp,31):
        if i>65:break
        lines.append(f"G21_FULL_R1_A{i}=MCP_EVENT:{k},MS:{t}")
    write(run/"prior-event-index.json",private)
    write(run/"prior-mcp-timeline.json",mcp)
    # Neutral output-format comparison, no browsing or requested tool use.
    sys.path.insert(0,str(root/"OwnerBridge/app/poc/p2-aisub"))
    from translator_gateway import preflight_antigravity,_validated_antigravity_alias
    cli=preflight_antigravity()
    ps=shutil.which("pwsh")
    if not ps:return "G21_INIT_NO_PWSH"
    env=dict(os.environ)
    for k in ("GEMINI_API_KEY","GOOGLE_API_KEY","GOOGLE_GEMINI_BASE_URL","AGY_ADC_AUTH","GOOGLE_CLOUD_PROJECT","GOOGLE_CLOUD_QUOTA_PROJECT"):env.pop(k,None)
    env["TTV_AGY_CLI"]=str(cli)
    env["TTV_AGY_MODEL"]=_validated_antigravity_alias("gemini-4-hydrogen-low","low")
    original=prior/"session-settings.json"
    settings=obj(original)
    global_paths=[pathlib.Path.home()/".gemini"/p for p in ("antigravity-cli/settings.json","config/config.json","config/mcp_config.json")]
    def hashes():return [hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else "MISSING" for p in global_paths]
    before=hashes()
    helpcmd="& $env:TTV_AGY_CLI --help; exit $LASTEXITCODE"
    q=subprocess.run([ps,"-NoProfile","-NonInteractive","-Command",helpcmd],env=env,cwd=run,capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=20)
    helptext=q.stdout+"\n"+q.stderr
    (run/"cli-help.txt").write_text(helptext,encoding="utf-8")
    if q.returncode!=0:return "G21_OUTPUT_HELP_FAILED"
    # Use only the documented streaming protocol already observed on the
    # historical V3.1 neutral/public-metadata test. No website or tool request.
    def has(flag):
        return bool(re.search(r"(?<![\w-])"+re.escape(flag)+r"(?![\w-])",helptext))
    stream=has("--input-format") and has("--output-format") and "stream-json" in helptext and has("--print")
    resume=has("--resume")
    cont=has("--continue")
    lines.append(f"G21_FULL_R2_SUMMARY=STREAM_INPUT:{int(stream)},RESUME_FLAG:{int(resume)},CONTINUE_FLAG:{int(cont)}")
    def publish():
        assert re.fullmatch("[a-f0-9]{32}",nonce)
        write(spool/"Receipts"/("g21-full-report-"+nonce+".json"),{"schema":"G21_TRAINING_FULL_REPORT_V1","nonce":nonce,"lines":lines})
    if not stream:
        publish()
        return "G21_SESSION_STREAM_UNVERIFIED"
    shutil.copyfile(original,run/"session-settings.json")
    env["TTV_SESSION_SETTINGS"]=str(run/"session-settings.json")
    cmd="& $env:TTV_AGY_CLI --model $env:TTV_AGY_MODEL --sandbox --settings $env:TTV_SESSION_SETTINGS --print= --input-format stream-json --output-format stream-json; exit $LASTEXITCODE"
    events=queue.Queue()
    def reader(pipe):
        try:
            for line in pipe:events.put((time.monotonic(),line))
        finally:events.put((time.monotonic(),None))
    reports=[];ids=[];state="UNKNOWN";start=time.monotonic()
    with (run/"persistent-stderr.txt").open("w",encoding="utf-8") as ef,(run/"persistent-stdout.jsonl").open("w",encoding="utf-8") as rf,(run/"persistent-arrivals.jsonl").open("w",encoding="utf-8") as tf:
        p=subprocess.Popen([ps,"-NoProfile","-NonInteractive","-Command",cmd],env=env,cwd=run,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=ef,text=True,encoding="utf-8",errors="replace",bufsize=1)
        threading.Thread(target=reader,args=(p.stdout,),daemon=True).start()
        try:
            for i,expected in enumerate(("READY_A","READY_B","READY_C"),1):
                sent=time.monotonic();first=-1;init=-1;final=-1;count=0;tools=0;answer=False;sid=None;turn_state="TIMEOUT"
                if p.poll() is not None:break
                question="Return exactly "+expected+". Do not use any tool, browse, read files, or run commands."
                message={"event":"user","message":{"content":[{"type":"text","text":question}]}}
                p.stdin.write(json.dumps(message)+"\n");p.stdin.flush()
                while time.monotonic()-sent<85:
                    try:at,line=events.get(timeout=.2)
                    except queue.Empty:
                        if p.poll() is not None:turn_state="PROCESS_EXIT";break
                        continue
                    if line is None:turn_state="EOF";break
                    v=max(0,ms(at,sent));count+=1
                    if first<0:first=v
                    rf.write(line);rf.flush()
                    tf.write(json.dumps({"turn":i,"ordinal":count,"elapsed_ms":v})+"\n");tf.flush()
                    try:e=json.loads(line)
                    except ValueError:continue
                    if not isinstance(e,dict):continue
                    if e.get("event")=="init" and init<0:init=v
                    st=e.get("step_update")
                    if isinstance(st,dict) and st.get("tool_name"):
                        tools+=1;turn_state="UNEXPECTED_TOOL";break
                    r=e.get("result")
                    if e.get("event")=="result" and isinstance(r,dict):
                        final=v;sid=r.get("conversation_id")
                        answer=isinstance(r.get("response"),str) and r["response"].strip()==expected
                        turn_state="READY" if answer else "RESULT_MISMATCH";break
                alive=p.poll() is None
                row={"turn":i,"first_ms":first,"init_ms":init,"final_ms":final,"state":turn_state,"ready":answer,"tools":tools,"events":count,"alive":alive,"pid":p.pid}
                reports.append(row);ids.append(sid if isinstance(sid,str) and sid else None)
                write(run/"turns.json",reports)
                def pos(x):return str(x) if x>=0 else "UNKNOWN"
                lines.append(f"G21_FULL_R2_A{i}=TURN:{i},STATE:{turn_state},FIRST_MS:{pos(first)},INIT_MS:{pos(init)},FINAL_MS:{pos(final)},READY:{int(answer)},TOOLS:{tools},EVENTS:{count},ALIVE:{int(alive)}")
                if not answer or tools or not alive or hashes()!=before:break
            try:p.stdin.close()
            except OSError:pass
            try:state="EXITED" if p.wait(timeout=10)==0 else "CLI_FAILED"
            except subprocess.TimeoutExpired:state="EXIT_TIMEOUT"
        finally:
            if p.poll() is None:
                subprocess.run(["taskkill.exe","/PID",str(p.pid),"/T","/F"],capture_output=True,timeout=10,check=False)
                try:p.wait(timeout=10)
                except subprocess.TimeoutExpired:state="CLEANUP_UNVERIFIED"
    same=len(ids)==3 and all(ids) and len(set(ids))==1
    unchanged=hashes()==before
    lines.append(f"G21_FULL_R2_TIMING=PROCESS:{state},TOTAL_MS:{ms(time.monotonic(),start)},TURNS:{len(reports)},SAME_CONVERSATION:{int(bool(same))},GLOBAL_UNCHANGED:{int(unchanged)}")
    publish()
    return "G21_SESSION_STUDY_READY" if len(reports)==3 and all(r["ready"] and not r["tools"] for r in reports) and state=="EXITED" and unchanged else "G21_SESSION_STUDY_HOLD"
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
