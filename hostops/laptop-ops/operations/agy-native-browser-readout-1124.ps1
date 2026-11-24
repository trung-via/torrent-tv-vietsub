# Read only the exact prior isolated MCP attempt, output sanitized evidence.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$prior=@(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -Filter 'receipt-*.json' -File | ForEach-Object {
 if($_.Length -le 2048 -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  try{$r=Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
   if($r.source_commit -ceq '677608fbd0a6c50993a0d81ba20fe384add8cd65' -and $r.operation -ceq 'agy-browser-headless-control-1124' -and $r.nonce -cmatch '^[a-f0-9]{32}$'){$r}
  }catch{}
 }
})
$code='MCP_READOUT_PRIOR_NOT_UNIQUE'
if($prior.Count -eq 1){
 $root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
 $run=Join-Path $root ('agy-cdp9555-mcp-auth-'+$prior[0].nonce)
 $log=Join-Path $run 'agy-stdout.jsonl'
 $code='MCP_READOUT_LOG_MISSING'
 if(Test-Path -LiteralPath $log -PathType Leaf){
  $file=Get-Item -LiteralPath $log
  if($file.Length -gt 0 -and $file.Length -le 4194304 -and -not ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){
   $py=@'
import json,re,sys,pathlib
root=pathlib.Path(sys.argv[1]).parent
def read(name):
    p=root/name
    if p.is_symlink() or not p.is_file() or p.stat().st_size>4194304:return ""
    return p.read_text(encoding="utf-8-sig",errors="replace")
records=[]
for l in read("agy-stdout.jsonl").splitlines():
    try:
        x=json.loads(l)
        if isinstance(x,dict):records.append(x)
    except ValueError:pass
def walk(x):
    if isinstance(x,dict):
        yield x
        for v in x.values():yield from walk(v)
    elif isinstance(x,list):
        for v in x:yield from walk(v)
ev=[x for x in records if x.get("event") not in ("user","result","assistant")]
names=[str(v).lower() for x in walk(ev) for k,v in x.items() if k.lower() in ("name","tool_name","toolname","step_type") and isinstance(v,str)]
raw=json.dumps(ev,ensure_ascii=False).lower()
debug=read("mcp-debug.log").lower()
stderr=read("agy-stderr.txt").lower()
report=read("RESULT.json")
try:r=json.loads(report);valid=int(isinstance(r,dict))
except Exception:valid=0
def flag(s,p):return int(bool(re.search(p,s)))
new=int(any("new_page" in v for v in names))
nav=int(any("navigate_page" in v for v in names))
snap=int(any("take_snapshot" in v for v in names))
click=int(any("click" in v for v in names))
connecterr=flag(debug+" "+stderr+" "+raw,r"econnrefused|failed to connect|connection refused|failed to fetch browser|websocket error")
missing=flag(debug+" "+stderr+" "+raw,r"tool not found|unknown tool|no such tool|tool.{0,20}not available")
auth=flag(raw,r"net::err_invalid_auth_credentials|http.{0,8}401|401 unauthorized")
den=flag(raw,r"http.{0,8}403|403 forbidden|access denied")
perm=flag(raw+" "+stderr,r"approval required|permission required|permission denied|not allowed|user consent")
# Output only fixed, sanitized labels. Absence is not proof of success.
print(f"MCPREAD_NEW{new}_NAV{nav}_SNAP{snap}_CLICK{click}_CONN{connecterr}_TOOL{missing}_AUTH{auth}_DEN{den}_PERM{perm}_LOG{int(bool(debug))}_JSON{valid}")
'@
   $out=@($py | & py -3 -I -B - $log 2>$null)
   if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}else{$code='MCP_READOUT_PARSE_ERROR'}
  }else{$code='MCP_READOUT_LOG_INVALID'}
 }
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
