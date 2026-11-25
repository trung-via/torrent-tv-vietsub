# TR18-R: read exact archived Teacher run; no provider invocation.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$prior='3bb10cf1bdb345eea4cdbb7439da4ae4'
$run=Join-Path $root ('tr-ttv-18-neon-teacher-v1-'+$prior)
if((Get-Item -LiteralPath $run -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'TR18R_RUN_LINK'}
$env:TTV_READOUT_NONCE=[string]$rq.nonce
$py=@'
import json,re,pathlib,sys,os
run,spool=map(pathlib.Path,sys.argv[1:])
source="db9d7d8af8d05556014950745c4666bb038ca799"
prior="3bb10cf1bdb345eea4cdbb7439da4ae4"
nonce=os.environ["TTV_READOUT_NONCE"]
assert re.fullmatch("[a-f0-9]{32}",nonce)
def read(path,cap=33554432):
    if not path.is_file() or path.is_symlink() or path.stat().st_size>cap:raise ValueError("READ_BOUND")
    return path.read_text(encoding="utf-8-sig",errors="replace")
report=json.loads(read(run/"BRAIN_TEACHER_REPORT.json"))
timing=json.loads(read(run/"stream-timing.json"))
assert report["source_commit"]==source and report["model"]=="gemini-4-neon-high" and report["elapsed_seconds"]==235
assert timing["schema"]=="TTV-STREAM-ARRIVAL-V1"
raw=read(run/"agy-stdout.jsonl")
err=read(run/"agy-stderr.txt")
records=[];invalid=0
for line in raw.splitlines():
    try:
        v=json.loads(line)
        if isinstance(v,dict):records.append(v)
        else:invalid+=1
    except ValueError:invalid+=1
assert len(records)==len(timing["event_arrival_seconds"])==report["event_count"]
# Full event scan, but no raw arguments, outputs, messages, URLs, or text sent to public GitHub.
tools={"list_pages","select_page","navigate_page","take_snapshot","click","fill","press_key","wait_for","evaluate_script","read_file","write_file","run_shell_command","execute_command","shell","list_directory","search_file_content","replace","glob","grep","save_memory","write_todos","read_many_files","call_mcp_tool"}
events={"init","step_update","result","error","message","assistant","tool_use","tool_result","content_block_delta","content_block_start","content_block_stop","done","warning","finish","usage","session_start","session_end"}
deny=re.compile(r"permission check failed|auto.denied|user denied permission|permission denied|not allowed|denied by",re.I)
flags={"DENY":deny,"FILE":re.compile(r"read_file|write_file|file permission",re.I),"SHELL":re.compile(r"run_shell_command|execute_command|shell command",re.I),"QUOTA":re.compile(r"quota.exceeded|rate.limit|resource_exhausted|429",re.I),"AUTH":re.compile(r"authentication required|unauthorized|login required",re.I),"CANCEL":re.compile(r"cancelled|canceled|aborted|interrupted",re.I),"TIMEOUT":re.compile(r"timed.out|deadline.exceeded",re.I),"DOWNLOAD":re.compile(r"download",re.I),"RECIPE":re.compile(r"recipe_v5|TEACHER_RECIPE",re.I),"RESULT":re.compile(r"final.response|final answer",re.I),"SANDBOX":re.compile(r"sandbox|permission rule",re.I),"CHALLENGE":re.compile(r"captcha|anti.bot challenge|access denied",re.I)}
def bits(text):
    return ",".join(k for k,p in flags.items() if p.search(text)) or "NONE"
def enum(v,allowed):
    return str(v).upper() if isinstance(v,str) and v in allowed else "OTHER"
trace=[];result_events=0;response_fields=0;alternative_fields=0;deny_events=0
for i,e in enumerate(records):
    event=e.get("event")
    st=e.get("step_update")
    if not isinstance(st,dict):st={}
    info=st.get("tool_info")
    if not isinstance(info,dict):info={}
    params=info.get("parameters")
    if not isinstance(params,dict):params={}
    tool=st.get("tool_name")
    if tool=="call_mcp_tool":tool=params.get("ToolName",tool)
    if tool is None:tool=e.get("tool_name")
    kind=enum(event,events) if event is not None else ("STEP_UPDATE" if st else "OTHER")
    r=e.get("result")
    if kind=="RESULT" or isinstance(r,dict):
        result_events+=1
        if isinstance(r,dict):
            response_fields+=int(isinstance(r.get("response"),str) and bool(r["response"].strip()))
            alternative_fields+=sum(int(isinstance(r.get(k),str) and bool(r[k].strip())) for k in ("text","message","content","output","answer","final_response"))
    raw_event=json.dumps(e,ensure_ascii=False)
    # Classify explicit errors/statuses separately from mentions in prompt, browser DOM, or model text.
    errors=[info.get("error"),st.get("error"),e.get("error"),e.get("message") if kind in ("ERROR","WARNING") else None]
    if isinstance(r,dict):errors.extend([r.get("error"),r.get("status"),r.get("message")])
    err_text=json.dumps(errors,ensure_ascii=False)
    outcome="ERROR" if any(x not in (None,"",False,[],{}) for x in errors[:3]) else ("OUTPUT" if "output" in info else ("RESULT" if kind=="RESULT" else "OTHER"))
    b=bits(err_text)
    deny_events+=int("DENY" in b.split(","))
    # Also count literal denial matches anywhere, but distinguish from explicit error field.
    mention=int(bool(deny.search(raw_event)))
    trace.append(f"{i}:{round(timing['event_arrival_seconds'][i]*1000)}:{kind}:{enum(tool,tools)}:{outcome}:{b}:{mention}")
# Read stored full markdown and recipe presence without exporting subtitle or private narrative.
full=read(run/"BRAIN_TEACHER_FULL_RESPONSE.md")
recipe=run/"TEACHER_RECIPE_V5_PRIVATE.json"
summary={"schema":"TTV-TR18-TRACE-V1","nonce":nonce,"source":source,"events":len(records),"invalid":invalid,"exit":report.get("exit") if type(report.get("exit")) is int else -999,"result_events":result_events,"response_fields":response_fields,"alternative_fields":alternative_fields,"deny_events":deny_events,"stdout_chars":len(raw),"stderr_chars":len(err),"report_chars":len(full),"final_count":len(report["final_response"]),"recipe_exists":int(recipe.is_file()),"stderr_flags":bits(err),"trace":trace}
assert len(trace)<=512
(spool/"Receipts"/("tr18-trace-"+nonce+".json")).write_text(json.dumps(summary,separators=(",",":")),encoding="utf-8")
'@
# Python code is fixed, no local source or logs sent as executable instructions.
$tmp=Join-Path $env:TEMP ('ttv-tr18-readout-'+$rq.nonce+'.py')
[IO.File]::WriteAllText($tmp,$py,[Text.UTF8Encoding]::new($false))
try{
  & py -3 -I -B $tmp $run $spool 2> (Join-Path $env:TEMP ('ttv-tr18-readout-'+$rq.nonce+'.err'))
  if($LASTEXITCODE -ne 0){throw 'TR18_TRACE_READ_FAILED'}
}finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
Write-Output 'TR18_TRACE_READ_SUCCESS'
