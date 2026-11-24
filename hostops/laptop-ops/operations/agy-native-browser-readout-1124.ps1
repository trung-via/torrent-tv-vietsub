# TR-TTV.04a exact prior smoke readout, no provider or browser actions.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('tr-ttv-04b-denial-audit-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$py=@'
import sys,pathlib,os,json,re
root,run=map(pathlib.Path,sys.argv[1:])
def read(p):
    if not p.is_file() or p.is_symlink() or p.stat().st_size>16777216:return ""
    return p.read_text(encoding="utf-8-sig",errors="replace")
def probe():
    history=pathlib.Path(os.environ["ProgramData"])/"TorrentTVVietsub"/"LaptopHostOps"/"History"
    hits=[]
    for f in history.glob("receipt-*.json"):
        try:
            q=json.loads(read(f))
            if q.get("source_commit")=="36856caeae0fc30ab8e09d5ecda97aff2a50791a" and q.get("operation")=="agy-native-browser-readout-1124" and q.get("result")=="SUCCESS" and re.fullmatch(r"[a-f0-9]{32}",q.get("nonce","")):hits.append(q["nonce"])
        except (ValueError,TypeError,OSError):pass
    if len(hits)!=1:return "TR04AR_PRIOR_HOLD"
    p=root/("tr-ttv-04b-teacher-"+hits[0])
    report=json.loads(read(p/"BRAIN_TEACHER_REPORT.json"))
    acq=report.get("verified_acquisition",{})
    rr=report.get("reported_result",{})
    sel=report.get("selection",{})
    recipe=report.get("teacher_recipe",{})
    final=report.get("final_response",[])
    raw=read(p/"agy-stdout.jsonl")
    err=read(p/"agy-stderr.txt")
    helptext=read(p/"cli-help.txt")
    # Match explicit denial text, not prompt instructions or a generic permission mention.
    def leaves(x):
        if isinstance(x,dict):
            for k,v in x.items():
                if k.lower() not in {"prompt","input","arguments","thinking","reasoning","thought","signature","instructions","system","user","env","credentials"}:yield from leaves(v)
        elif isinstance(x,list):
            for v in x:yield from leaves(v)
        elif isinstance(x,str):yield x
    denial=r"permission check failed|user denied permission|auto-denied|permission denied|not permitted"
    tools=("list_pages","new_page","select_page","navigate_page","take_snapshot","click","fill","press_key","wait_for","close_page","evaluate_script","get_network_request","list_network_requests")
    mask=0;filemask=0;other=0;rows=[];hits=0
    for n,line in enumerate(raw.splitlines()):
        try:e=json.loads(line)
        except ValueError:continue
        if not isinstance(e,dict):continue
        for s in leaves(e):
            if not re.search(denial,s,re.I):continue
            hits+=1
            names=[]
            for match in re.finditer(r"(?:mcp\s*[(\"']?\s*ttv-browser[/\\]|ttv-browser[/\\])([a-z_]+)",s,re.I):
                name=match.group(1).lower();names.append(name)
                if name in tools:mask|=1<<tools.index(name)
                else:other|=1
            if re.search(r"\b(?:write_file|write|save_file|create_file|replace)\b",s,re.I):filemask|=1
            if re.search(r"\b(?:read_file|read|view_file)\b",s,re.I):filemask|=2
            if re.search(r"\b(?:run_command|shell|terminal|exec|execute_command)\b",s,re.I):filemask|=4
            if re.search(r"wake-browser|9444",s,re.I):other|=2
            if re.search(r"SELECTION\.json",s,re.I):filemask|=8
            if re.search(r"RESULT\.json",s,re.I):filemask|=16
            if re.search(r"TEACHER_RECIPE\.json",s,re.I):filemask|=32
            if not names and not re.search(r"write_file|read_file|run_command|shell|terminal|wake-browser|9444",s,re.I):other|=4
            rows.append({"event":n,"tool_names":names,"denial":s[:2000]})
    # Stderr is separate from event text; keep local exact excerpts only.
    if re.search(denial,err,re.I):
        rows.append({"event":"stderr","denial":err[:4000]})
    # Inspect enrolled helper's execution ceiling without running or altering it.
    helper=pathlib.Path(os.environ["LOCALAPPDATA"])/"TorrentTVVietsub"/"OwnerBridge"/"Maintenance"/"owner-laptop-ops-helper.ps1"
    h=read(helper)
    relevant=[line.strip() for line in h.splitlines() if re.search(r"timeout|deadline|WaitForExit|Wait-Process|Stop-Process|ExecutionTimeLimit|Start-Process",line,re.I)]
    helperkill=int(bool(re.search(r"\.Kill\s*\(|\bStop-Process\b",h,re.I)))
    helperwait=int(bool(re.search(r"WaitForExit\s*\(\s*[^)\s]+|Wait-Process[^\r\n]*-Timeout|Wait-Job[^\r\n]*-Timeout",h,re.I)))
    (run/"denial-and-helper-audit.json").write_text(json.dumps({"source":str(p.name),"denials":rows,"tool_map":tools,"tool_mask":mask,"file_mask":filemask,"other_mask":other,"helper_found":bool(h),"helper_relevant_lines":relevant,"helper_kill":bool(helperkill),"helper_bounded_wait":bool(helperwait)},ensure_ascii=False,indent=2),encoding="utf-8")
    return f"TR04P_N{min(hits,999)}_M{mask:X}_F{filemask:X}_O{other:X}_H{int(bool(h))}K{helperkill}W{helperwait}"

try:print(probe())
except Exception as e:
    (run/"readout-error.txt").write_text(type(e).__name__+": "+str(e),encoding="utf-8")
    print("TR04AR_LOCAL_ERROR")
'@
$f=Join-Path $run 'control.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $run 2> (Join-Path $run 'python-stderr.txt'))
$code='TR04AR_LOCAL_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,65}$'){$code=[string]$out[0]}
$task=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-Laptop-HostOps' -TaskPath '\' -ErrorAction SilentlyContinue
$lim=if($task){[string]$task.Settings.ExecutionTimeLimit}else{''}
$lm=if($lim -eq 'PT0S'){0}elseif($lim -match '^PT(\d+)H'TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
){[int]$Matches[1]*60}elseif($lim -match '^PT(\d+)M'TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
){[int]$Matches[1]}else{999}
$code=$code+'_L'+$lm
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
