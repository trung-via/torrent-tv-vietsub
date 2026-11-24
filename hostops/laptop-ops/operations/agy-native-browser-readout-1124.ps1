# Ask AGY for a diagnosis of its exact failed local helper attempts.
# No shell/browser/provider actions requested; no settings or permission changes.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('agy-teacher-full-readout-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$py=@'
import sys,pathlib,os,json,re,hashlib
owner,run=map(pathlib.Path,sys.argv[1:])
def read(p):
    try:
        if p.is_file() and not p.is_symlink() and p.stat().st_size<=16777216:return p.read_text(encoding="utf-8-sig",errors="replace")
    except OSError:pass
    return ""
history=pathlib.Path(os.environ["ProgramData"])/"TorrentTVVietsub"/"LaptopHostOps"/"History"
hits=[]
for f in history.glob("receipt-*.json"):
    try:
        q=json.loads(read(f))
        if q.get("source_commit")=="3e848e623b3d2a9b86d7e1796ed9037f4ac6d66c" and q.get("operation")=="agy-browser-headless-control-1124" and q.get("result")=="SUCCESS" and re.fullmatch(r"[a-f0-9]{32}",q.get("nonce","")):hits.append(q["nonce"])
    except (ValueError,TypeError):pass
if len(hits)!=1:
    print("TRFULL_PRIOR_HOLD");sys.exit(0)
p=run.parent/("agy-spiderman-native-teacher-"+hits[0])
raw=read(p/"agy-stdout.jsonl")
events=[];bad=0
for l in raw.splitlines():
    try:
        x=json.loads(l)
        if isinstance(x,dict):events.append(x)
    except ValueError:bad+=1
# Preserve original output in place. Reconstruct user-facing answer and error records
# independently of the compact status. Never export raw output to public GitHub.
final=[];assistant=[];errors=[];tools=[];types={}
def walk(v,out,depth=0):
    if depth>12:return
    if isinstance(v,dict):
        if str(v.get("role","")).lower() in ("user","system","developer"):return
        if str(v.get("type","")).lower() in ("thinking","reasoning","thought"):return
        for k,val in v.items():
            if k.lower() in ("prompt","instructions","input","arguments","command","env","credentials","config","thinking","reasoning","thought","signature"):continue
            if isinstance(val,str) and k.lower() in ("text","message","content","result","error","output","reason","delta","value","response"):out.append(val)
            elif isinstance(val,(dict,list)):walk(val,out,depth+1)
    elif isinstance(v,list):
        for x in v:walk(x,out,depth+1)
    elif isinstance(v,str):out.append(v)
for e in events:
    ev=str(e.get("event",e.get("type",""))).lower()
    types[ev]=types.get(ev,0)+1
    if ev in ("user","system","init","session_start") or str(e.get("role","")).lower() in ("user","system","developer"):continue
    out=[];walk(e,out)
    if ev in ("result","final","final_response"):final.extend(out)
    elif ev in ("tool_error","error","assistant_error","tool_result","tool_response","function_response"):errors.extend(out);tools.append(ev)
    elif ev in ("tool_call","tool_use","tool_start","function_call"):tools.append(ev)
    else:assistant.extend(out)
ftext="".join(final)
atext="".join(assistant)
etext="\n".join(errors)
# All available final/assistant output, errors, and explicit result/recipe files.
# Local owner report retains actual text; no external upload.
report="\n".join(["# Neon High Spider-Man Teacher - complete recovered response","Run 45431777374 | source 3e848e623b3d2a9b86d7e1796ed9037f4ac6d66c","## Final response",ftext or "[No final text recovered]","## Assistant text stream",atext or "[No assistant text recovered]","## Tool outcomes / errors",etext or "[No tool error text recovered]","## stderr",read(p/"agy-stderr.txt"),"## RESULT.json",read(p/"RESULT.json"),"## SELECTION.json",read(p/"SELECTION.json"),"## TEACHER_RECIPE.json",read(p/"TEACHER_RECIPE.json"),"## Event inventory",json.dumps(types,indent=2)])
(p/"BRAIN_TEACHER_FULL_RESPONSE.md").write_text(report,encoding="utf-8")
# Only bounded classifications from real output leave the machine.
answer=ftext+"\n"+atext+"\n"+etext
patterns=[("M",r"(?:ttv-browser|mcp server|mcp tool).{0,100}(?:not available|unavailable|not found|not registered|not configured|not accessible|failed to (?:connect|initialize))|(?:unavailable|not found|not registered).{0,100}(?:ttv-browser|mcp server)"),("D",r"permission denied|access denied|sandbox.{0,80}(?:denied|blocked)|approval required|not permitted"),("A",r"login required|sign in required|captcha|authentication required|access denied|403 forbidden|429 too many"),("P",r"(?:page|tab).{0,80}(?:not found|closed|unavailable|cannot|failed)"),("S",r"(?:no|cannot find|could not find).{0,60}(?:matching subtitle|compatible subtitle|english subtitle)"),("W",r"(?:cannot|unable to|failed to).{0,60}(?:write|save|create).{0,60}(?:file|json)")]
flags="".join(k+str(int(bool(re.search(rx,answer,re.I|re.S)))) for k,rx in patterns)
print(f"TRFULL_N{min(len(events),999)}_F{min(len(ftext),99999)}_A{min(len(atext),99999)}_E{min(len(etext),99999)}_T{min(len(tools),99)}_{flags}")
'@
$f=Join-Path $run 'control.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $owner $run 2> (Join-Path $run 'python-stderr.txt'))
$code='AGYASK_LOCAL_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,65}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
