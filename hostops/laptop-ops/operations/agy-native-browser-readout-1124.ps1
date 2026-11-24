# Ask AGY for a diagnosis of its exact failed local helper attempts.
# No shell/browser/provider actions requested; no settings or permission changes.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('agy-direct-readout-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$py=@'
import sys,pathlib,os,json,re
owner,run=map(pathlib.Path,sys.argv[1:])
def read(p):
    try:
        if p.is_file() and not p.is_symlink() and p.stat().st_size<=4194304:return p.read_text(encoding="utf-8-sig",errors="replace")
    except OSError:pass
    return ""
history=pathlib.Path(os.environ["ProgramData"])/"TorrentTVVietsub"/"LaptopHostOps"/"History"
hits=[]
for f in history.glob("receipt-*.json"):
    try:
        q=json.loads(read(f))
        if q.get("source_commit")=="05a7d383d6cb58f3dff0f471dc9dbb69d8d8ea38" and q.get("operation")=="agy-native-browser-readout-1124" and q.get("result")=="SUCCESS" and re.fullmatch(r"[a-f0-9]{32}",q.get("nonce","")):hits.append(q["nonce"])
    except (ValueError,TypeError):pass
if len(hits)!=1:
    print("ASKREAD_PRIOR_HOLD");sys.exit(0)
p=run.parent/("agy-direct-question-"+hits[0])
events=[]
for l in read(p/"agy-stdout.jsonl").splitlines():
    try:
        x=json.loads(l)
        if isinstance(x,dict):events.append(x)
    except ValueError:pass
# Gather only assistant/final text, allow stream deltas to be split across records.
parts=[]; final=[]; leaves=[]
def walk(v,out,depth=0):
    if depth>12:return
    if isinstance(v,dict):
        if str(v.get("role","")).lower() in ("user","system","developer"):return
        if str(v.get("event","")).lower() in ("user","system","init","session_start"):return
        for k,val in v.items():
            if k.lower() in ("prompt","system_prompt","instructions","input","arguments","command","env","credentials","config"):continue
            if isinstance(val,str) and k.lower() in ("text","message","content","result","error","output","reason","delta","value","response"):out.append(val)
            elif isinstance(val,(dict,list)):walk(val,out,depth+1)
    elif isinstance(v,list):
        for x in v:walk(x,out,depth+1)
    elif isinstance(v,str):out.append(v)
for e in events:
    ev=str(e.get("event","")).lower()
    if ev in ("user","system","init","session_start"):continue
    x=[];walk(e,x);parts+=x
    if ev=="result":final+=x
saved=read(p/"answer-private.txt")
def codes(text):
    return set(re.findall(r"AGY_ANSWER_C([0-7])_F([0-7])_E([0-3])",re.sub(r"[\s\x60*]+","",text)))
for mode,text in [("FINAL","".join(final)),("PARTS","".join(parts)),("SAVED",saved)]:
    matches=codes(text)
    if len(matches)==1:
        c,f,e=next(iter(matches));print(f"ASKREAD_C{c}_F{f}_E{e}_{mode}");sys.exit(0)
# If no unique exact code, report only factual presence of answer and coarse categories.
text=" ".join(parts)
tests=[("U",r"(?:tool|shell|terminal).{0,80}(?:unavailable|not available|not exposed|not registered)"),("D",r"(?:sandbox|permission).{0,80}(?:denied|blocked|restriction|reject)"),("M",r"(?:text|response).{0,80}(?:instead of|rather than).{0,60}(?:tool|execut)"),("P",r"(?:path|command).{0,80}(?:invalid|not found|syntax)"),("K",r"(?:unknown|insufficient evidence|cannot determine|cannot conclusively)")]
flags="".join(k+str(int(bool(re.search(rx,text,re.I)))) for k,rx in tests)
print(f"ASKREAD_UNPARSED_N{len(events)}_P{min(len(parts),99)}_L{min(len(text),99999)}_{flags}")

'@
$f=Join-Path $run 'control.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $owner $run 2> (Join-Path $run 'python-stderr.txt'))
$code='AGYASK_LOCAL_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,65}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
