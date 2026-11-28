Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('NativeBrowserTest\g21-settings-study-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$py=@'
import os,sys,pathlib,json,re,time,queue,threading,subprocess,shutil,hashlib,copy
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
    # ABBA neutral context-settings comparison, no browsing or tool use. No production edits.
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
    if not isinstance(settings,dict):return "G21_SETTINGS_SCHEMA_UNKNOWN"
    minimal=copy.deepcopy(settings)
    # Only restrict optional context loading, never remove rules, permissions,
    # auth, sandbox, tools, MCP or unrecognized settings. No assumed schema changes.
    changed=[]
    ctx=minimal.get("context")
    if isinstance(ctx,dict):
        if isinstance(ctx.get("includeDirectories"),list) and ctx["includeDirectories"]:
            ctx["includeDirectories"]=[];changed.append("INCLUDE_DIRS")
        if ctx.get("loadMemoryFromIncludeDirectories") is True:
            ctx["loadMemoryFromIncludeDirectories"]=False;changed.append("INCLUDE_MEMORY")
    restored=copy.deepcopy(minimal)
    if changed:restored["context"]=copy.deepcopy(settings["context"])
    assert restored==settings
    known=("context","permissions","extensions","mcpServers","tools","security","model","general","advanced","agentMode","memory")
    present=[k.upper() for k in known if k in settings]
    write(run/"settings-audit.json",{"present_known_sections":present,"top_level_count":len(settings),"changed":changed,"context_keys":list(settings["context"]) if isinstance(settings.get("context"),dict) else [],"original_bytes":original.stat().st_size})
    lines.append("G21_FULL_R2_SUMMARY=SETTINGS_KEYS:"+str(len(settings))+",KNOWN:"+("+".join(present) or "NONE")+",CHANGED:"+("+".join(changed) or "NONE"))
    lines.append("G21_FULL_R2_TIMING=ORIGINAL_BYTES:"+str(original.stat().st_size))
    global_paths=[pathlib.Path.home()/".gemini"/p for p in ("antigravity-cli/settings.json","config/config.json","config/mcp_config.json")]
    def hashes():return [hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else "MISSING" for p in global_paths]
    before=hashes()
    variants=("ORIGINAL","MINIMAL","MINIMAL","ORIGINAL") if changed else ()
    for idx,label in enumerate(variants,1):
        local_mcp=False
        d=run/("sample-"+str(idx));d.mkdir()
        # Same saved settings, separate task directory; no existing config writes.
        if label=="ORIGINAL":shutil.copyfile(original,d/"session-settings.json")
        else:write(d/"session-settings.json",minimal)
        if local_mcp:
            (d/".agents").mkdir()
            shutil.copyfile(prior/".agents/mcp_config.json",d/".agents/mcp_config.json")
        env["TTV_SESSION_SETTINGS"]=str(d/"session-settings.json")
        (d/"prompt.txt").write_text("Return exactly READY. Do not use any tool, browse, read files, or run commands.",encoding="utf-8")
        env["TTV_AGY_PROMPT"]=str(d/"prompt.txt")
        cmd="$ErrorActionPreference='Stop'; $p=Get-Content -LiteralPath $env:TTV_AGY_PROMPT -Raw; & $env:TTV_AGY_CLI --model $env:TTV_AGY_MODEL --sandbox --settings $env:TTV_SESSION_SETTINGS --output-format stream-json -p $p; exit $LASTEXITCODE"
        start=time.monotonic();events=queue.Queue();firstms=-1;final=-1;tool=0;count=0;answer=False;state="TIMEOUT";eof=False
        def reader(pipe):
            try:
                for line in pipe:events.put((time.monotonic(),line))
            finally:events.put((time.monotonic(),None))
        with (d/"stderr.txt").open("w",encoding="utf-8") as ef,(d/"stdout.jsonl").open("w",encoding="utf-8") as rf,(d/"arrivals.jsonl").open("w",encoding="utf-8") as tf:
            p=subprocess.Popen([ps,"-NoProfile","-NonInteractive","-Command",cmd],env=env,cwd=d,stdout=subprocess.PIPE,stderr=ef,text=True,encoding="utf-8",errors="replace",bufsize=1)
            threading.Thread(target=reader,args=(p.stdout,),daemon=True).start()
            while True:
                try:
                    t,line=events.get(timeout=.2)
                    if line is None:eof=True
                    else:
                        count+=1;v=ms(t,start)
                        if firstms<0:firstms=v
                        rf.write(line);rf.flush();tf.write(json.dumps({"ordinal":count,"elapsed_ms":v})+"\n");tf.flush()
                        try:e=json.loads(line)
                        except ValueError:e={}
                        if isinstance(e,dict):
                            st=e.get("step_update")
                            if isinstance(st,dict) and st.get("tool_name"):
                                tool+=1;state="UNEXPECTED_TOOL";break
                            r=e.get("result")
                            if e.get("event")=="result" and isinstance(r,dict) and isinstance(r.get("response"),str):
                                final=v;answer=r["response"].strip()=="READY"
                except queue.Empty:pass
                if p.poll() is not None and eof:
                    state="EXITED" if p.returncode==0 else "CLI_FAILED";break
                if time.monotonic()-start>=85:break
            if p.poll() is None:
                subprocess.run(["taskkill.exe","/PID",str(p.pid),"/T","/F"],capture_output=True,timeout=10,check=False)
                try:p.wait(timeout=10)
                except subprocess.TimeoutExpired:state="CLEANUP_UNVERIFIED"
        elapsed=ms(time.monotonic(),start)
        sample={"settings_variant":label,"local_mcp":local_mcp,"first_event_ms":firstms,"final_ms":final,"elapsed_ms":elapsed,"state":state,"tool_events":tool,"ready":answer,"event_count":count,"global_unchanged":hashes()==before}
        write(d/"metrics.json",sample)
        def pos(x):return str(x) if x>=0 else "UNKNOWN"
        lines.append(f"G21_FULL_R2_A{idx}=SETTINGS:{label},LOCAL_MCP:{int(local_mcp)},STATE:{state},FIRST_MS:{pos(firstms)},FINAL_MS:{pos(final)},TOTAL_MS:{elapsed},READY:{int(answer)},TOOLS:{tool},EVENTS:{count},GLOBAL_UNCHANGED:{int(hashes()==before)}")
        if state!="EXITED" or not answer or tool or hashes()!=before:break
    assert re.fullmatch("[a-f0-9]{32}",nonce)
    write(spool/"Receipts"/("g21-full-report-"+nonce+".json"),{"schema":"G21_TRAINING_FULL_REPORT_V1","nonce":nonce,"lines":lines})
    return "G21_SETTINGS_STUDY_READY" if changed else "G21_SETTINGS_NO_ELIGIBLE_DIFF"
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
