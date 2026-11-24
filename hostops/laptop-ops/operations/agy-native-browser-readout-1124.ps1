# TR-TTV.04a exact prior smoke readout, no provider or browser actions.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('tr-ttv-04a-readout-'+$rq.nonce)
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
            if q.get("source_commit")=="58d67750746e404a228d135ccdb7f27b9c06f62b" and q.get("operation")=="agy-native-browser-readout-1124" and q.get("result")=="SUCCESS" and re.fullmatch(r"[a-f0-9]{32}",q.get("nonce","")):hits.append(q["nonce"])
        except (ValueError,TypeError,OSError):pass
    if len(hits)!=1:return "TR04AR_PRIOR_HOLD"
    p=root/("tr-ttv-04a-"+hits[0])
    summary=json.loads(read(p/"smoke-summary.json"))
    raw=read(p/"agy-stdout.jsonl")
    err=read(p/"agy-stderr.txt")
    helptext=read(p/"cli-help.txt")
    events=[]
    for line in raw.splitlines():
        try:
            v=json.loads(line)
            if isinstance(v,dict):events.append(v)
        except ValueError:pass
    # Never export raw logs or page data. Classify observable errors and CLI option description.
    combined=raw+"\n"+err
    patterns=[
      ("U",r"unknown (?:argument|option|flag)|unrecognized (?:argument|option)|unexpected argument"),
      ("S",r"(?:settings|config).{0,100}(?:invalid|failed|cannot|error|not found)|(?:failed|invalid|error).{0,100}(?:settings|config)"),
      ("P",r"permission|auto.denied|not permitted"),
      ("T",r"timeout|timed out|deadline exceeded"),
      ("Q",r"quota|rate limit|resource.exhausted|429"),
      ("M",r"(?:mcp|ttv-browser).{0,100}(?:failed|unavailable|not found|error|denied)"),
      ("B",r"sandbox.{0,100}(?:error|failed|invalid)|non-absolute file path"),
      ("N",r"no output produced|no response|no final"),
      ("A",r"authentication|unauthorized|login required|not signed in")]
    flags="".join(k+str(int(bool(re.search(rx,combined,re.I)))) for k,rx in patterns)
    # Examine tool result status structurally, not model claims.
    steps=sum(e.get("event")=="step_update" for e in events)
    results=[e for e in events if e.get("event")=="result"]
    settingsline=[x.strip() for x in helptext.splitlines() if re.match(r"^\s*--?settings(?:[ =\t]|$)",x)]
    sl=" ".join(settingsline).lower()
    kind=1 if re.search(r"json|file|path",sl) else 2 if sl else 0
    # Preserve relevant text in a local report for owner if needed.
    report={"source":str(p.name),"summary":summary,"event_shapes":[{"event":e.get("event"),"keys":sorted(e.keys()),"nested_keys":{k:sorted(v.keys()) for k,v in e.items() if isinstance(v,dict)}} for e in events],"settings_help":settingsline,"error_flags":flags,"stderr":err}
    (run/"readout.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
    return f"TR04AR_E{int(summary.get('exit',255))}_N{min(len(events),999)}_S{min(steps,999)}_R{len(results)}_H{kind}_{flags}"
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
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
