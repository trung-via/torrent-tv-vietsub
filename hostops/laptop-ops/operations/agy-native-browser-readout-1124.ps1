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
    # Use exact event-scoped matches, excluding prompt/input/config echoes.
    # Never export raw text, page content, paths or credentials to public logs.
    def leaves(v, trail=()):
        if isinstance(v,dict):
            for k,x in v.items():
                if k.lower() not in ("prompt","input","arguments","command","env","credentials","config","thinking","reasoning","thought","signature","instructions","system","user"):
                    yield from leaves(x,trail+(k,))
        elif isinstance(v,list):
            for x in v:yield from leaves(x,trail)
        elif isinstance(v,str):yield (trail,v)
    outcome=[]
    steptext=[]
    results=[]
    for e in events:
        ev=e.get("event",e.get("type",""))
        if ev=="result":results.extend(v for _,v in leaves(e))
        elif ev=="step_update":steptext.extend(v for _,v in leaves(e))
    body="\n".join(steptext+results+[err])
    checks=[
      ("D",r"user denied permission|permission check failed|auto.denied|permission denied|not permitted"),
      ("W",r"waiting for (?:a |the )?(?:user |tool )?(?:permission|approval|confirmation)|permission.{0,45}(?:timed out|timeout)|(?:timed out|timeout).{0,45}permission"),
      ("A",r"approval required|permission required|requires.{0,40}permission|request.{0,25}permission"),
      ("H",r"headless mode cannot prompt|headless.{0,50}(?:permission|approval)|non.interactive.{0,50}(?:permission|approval)"),
      ("L",r"ttv-browser[/\\]list_pages|ttv-browser__list_pages|ttv-browser\.list_pages"),
      ("C",r"(?:mcp|server).{0,80}(?:connect|initialize|startup|handshake).{0,50}(?:timeout|timed out|failed)|(?:timeout|timed out).{0,60}(?:connect|initialize|handshake)"),
      ("T",r"print.timeout|response timeout|timed out waiting for (?:the )?(?:response|model)|deadline exceeded|(?:timed out|timeout).{0,25}45\s*(?:s|seconds)"),
      ("X",r"tool.{0,45}(?:execution|call).{0,45}(?:timeout|timed out)|(?:timeout|timed out).{0,45}tool"),
      ("F",r"failed to read|failed to load|invalid settings|settings.{0,30}not found"),
      ("V",r"non-absolute file path|sandbox configuration error")]
    flags="".join(k+str(int(bool(re.search(rx,body,re.I)))) for k,rx in checks)
    def hit(v,rx):
        return int(bool(re.search(rx,v,re.I)))
    timeout_rx=r"timeout|timed out|deadline exceeded"
    perm_rx=r"permission|approval|auto.denied"
    st="\n".join(steptext);rt="\n".join(results)
    # Split where the permission/timeout text appears (step, result, stderr).
    scopes="".join(str(hit(v,rx)) for v in (st,rt,err) for rx in (perm_rx,timeout_rx))
    # Preserve exact original user-facing errors in Owner-local report.
    # Exclude reasoning, prompts and unrelated raw payloads.
    lines=[]
    for name,vals in (("STEP",steptext),("RESULT",results),("STDERR",[err])):
        for v in vals:
            if re.search(perm_rx+"|"+timeout_rx+"|ttv-browser",v,re.I):
                lines.append(name+": "+v[:3000])
    (run/"TR04A_PERMISSION_TIMEOUT_REPORT.txt").write_text("\n".join(lines),encoding="utf-8")
    return "TR04D_"+flags+"_S"+scopes

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
