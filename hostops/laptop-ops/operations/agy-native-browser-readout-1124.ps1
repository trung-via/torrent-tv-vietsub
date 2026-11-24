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
import json,re,sys,pathlib,os,shutil,subprocess
p=pathlib.Path(sys.argv[1])
records=[]
for l in p.read_text(encoding="utf-8").splitlines():
    try:
        x=json.loads(l)
        if isinstance(x,dict):records.append(x)
    except ValueError:pass
# Count actual structured event payloads, with recursive traversal, never disclose raw logs.
def visit(x):
    if isinstance(x,dict):
        yield x
        for v in x.values():yield from visit(v)
    elif isinstance(x,list):
        for v in x:yield from visit(v)
events=[r for r in records if r.get("event") not in ("user","result","assistant")]
nodes=[x for r in events for x in visit(r)]
names=[str(v).lower() for x in nodes for k,v in x.items() if k.lower() in ("name","tool_name","toolname","server_name","server","step_type","type") and isinstance(v,str)]
nav=int(any("navigate_page" in v for v in names))
snap=int(any("take_snapshot" in v for v in names))
mcp=int(any("torrent-tv-chrome" in v or "torrent_tv_chrome" in v for v in names))
# Cached tool schemas are independent evidence of MCP discovery.
cache=pathlib.Path.home()/".gemini"/"antigravity-cli"/"mcp"/"torrent-tv-chrome"
cached=int((cache/"navigate_page.json").is_file())+int((cache/"take_snapshot.json").is_file())
config=p.parent/".agents"/"mcp_config.json"
cfg=int(config.is_file())
stderr=p.parent/"agy-stderr.txt"
err=stderr.read_text(encoding="utf-8",errors="replace").lower() if stderr.is_file() else ""
trust=int(bool(re.search(r"untrusted workspace|workspace.{0,25}not trusted|workspace trust",err)))
spawn=int(bool(re.search(r"enoent|spawn.{0,45}(failed|error)|cannot find module|not recognized as",err)))
# Inspect CLI help without provider calls.
agy=shutil.which("agy.exe") or shutil.which("agy")
flags=0
if agy:
    try:
        z=subprocess.run([agy,"--help"],capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=15)
        txt=z.stdout+z.stderr
        flags=int("--allowed-mcp-server-names" in txt)+2*int("--mcp-config" in txt)+4*int("--add-dir" in txt)
    except Exception:pass
print(f"MCP_DIAG_CFG{cfg}_CACHE{cached}_EVENTS{min(len(events),999)}_NAV{nav}_SNAP{snap}_MCP{mcp}_TRUST{trust}_SPAWN{spawn}_FLAGS{flags}")
'@
   $out=@($py | & py -3 -I -B - $log 2>$null)
   if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}else{$code='MCP_READOUT_PARSE_ERROR'}
  }else{$code='MCP_READOUT_LOG_INVALID'}
 }
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
