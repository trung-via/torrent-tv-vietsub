# Read only the exact prior isolated MCP attempt, output sanitized evidence.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$prior=@(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -Filter 'receipt-*.json' -File | ForEach-Object {
 if($_.Length -le 2048 -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  try{$r=Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
   if($r.source_commit -ceq '7055333ef72925ef3875f80e409f00e910df2a68' -and $r.operation -ceq 'agy-browser-headless-control-1124' -and $r.nonce -cmatch '^[a-f0-9]{32}$'){$r}
  }catch{}
 }
})
$code='MCP_READOUT_PRIOR_NOT_UNIQUE'
if($prior.Count -eq 1){
 $root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
 $run=Join-Path $root ('mcp-headless-'+$prior[0].nonce)
 $log=Join-Path $run 'agy-stdout.jsonl'
 $code='MCP_READOUT_LOG_MISSING'
 if(Test-Path -LiteralPath $log -PathType Leaf){
  $file=Get-Item -LiteralPath $log
  if($file.Length -gt 0 -and $file.Length -le 4194304 -and -not ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){
   $py=@'
import json,re,sys,pathlib
p=pathlib.Path(sys.argv[1])
records=[]
for l in p.read_text(encoding="utf-8").splitlines():
    try:
        x=json.loads(l)
        if isinstance(x,dict):records.append(x)
    except ValueError:pass
init=[r.get("init",{}) for r in records if r.get("event")=="init"]
tools=json.dumps([x.get("tools",[]) for x in init]).lower()
updates=[r.get("step_update",{}) for r in records if r.get("event")=="step_update"]
steps=[x for x in updates if isinstance(x,dict) and re.search(r"mcp|tool",str(x.get("step_type","")),re.I)]
done=[x for x in steps if str(x.get("state","")).upper()=="DONE"]
# Inspect structured tool step types, not user or assistant prose.
st=json.dumps(done,ensure_ascii=False).lower()
nav=int("navigate_page" in st)
snap=int("take_snapshot" in st)
mcp=int(bool(re.search(r"torrent[-_]tv[-_]chrome",st)))
initnav=int("navigate_page" in tools)
initsnap=int("take_snapshot" in tools)
results=[r.get("result",{}) for r in records if r.get("event")=="result"]
result=results[0] if len(results)==1 and isinstance(results[0],dict) else {}
final=str(result.get("response","")).lower()
status=int(result.get("status")=="SUCCESS")
denial=int(bool(re.search(r"denied|approval required|permission required|not available|unavailable|blocked|failed|could not|unable",final)))
error=int(bool(re.search(r'"(?:is_error|isError)"\s*:\s*true|"status"\s*:\s*"error"',st)))
print(f"MCP_READOUT_INIT{initnav}{initsnap}_DONE{min(len(done),999)}_NAV{nav}_SNAP{snap}_MCP{mcp}_OK{status}_DEN{denial}_ERR{error}")
'@
   $out=@($py | & py -3 -I -B - $log 2>$null)
   if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}else{$code='MCP_READOUT_PARSE_ERROR'}
  }else{$code='MCP_READOUT_LOG_INVALID'}
 }
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
