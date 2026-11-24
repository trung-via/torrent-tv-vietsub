# Read only the exact prior isolated MCP attempt, output sanitized evidence.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$prior=@(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -Filter 'receipt-*.json' -File | ForEach-Object {
 if($_.Length -le 2048 -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  try{$r=Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
   if($r.source_commit -ceq 'a9eb7453551cdf10a59ee108f1a0fd612e671de4' -and $r.operation -ceq 'agy-browser-headless-control-1124' -and $r.nonce -cmatch '^[a-f0-9]{32}$'){$r}
  }catch{}
 }
})
$code='MCP_READOUT_PRIOR_NOT_UNIQUE'
if($prior.Count -eq 1){
 $root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
 $run=Join-Path $root ('agy-cdp9555-mcp-repair-'+$prior[0].nonce)
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
ev=[x for x in records if x.get("event") not in ("user","assistant","result")]
names=[str(v).lower() for x in walk(ev) for k,v in x.items() if k.lower() in ("name","tool_name","toolname","step_type") and isinstance(v,str)]
final=[x for x in records if x.get("event")=="result"]
raw=json.dumps(ev,ensure_ascii=False).lower()
end=json.dumps(final,ensure_ascii=False).lower()
debug=read("mcp-debug.log").lower()
stderr=read("agy-stderr.txt").lower()
alltext=raw+" "+end+" "+debug+" "+stderr
def flag(s,p):return int(bool(re.search(p,s)))
patterns=[("QUOTA",r"resource.exhausted|quota.exceeded|rate.limit.exceeded|insufficient.quota"),("PERM",r"approval required|permission required|permission denied|not allowed|user consent|sandbox.violation"),("TIMEOUT",r"timed out|deadline.exceeded|timeout exceeded|navigation timeout"),("TRANSPORT",r"econnrefused|econnreset|connection closed|failed to connect|transport closed|broken pipe"),("TOOL",r"tool not found|unknown tool|no such tool|invalid (?:arguments|parameters)|schema.validation"),("AUTH",r"err_invalid_auth_credentials|401 unauthorized|403 forbidden"),("NODE",r"cannot find module|npm err|enoent|not recognized as an internal"),("ABORT",r"aborted|cancelled|canceled|interrupted")]
flags=[name for name,pattern in patterns if flag(alltext,pattern)]
new=int(any("new_page" in v for v in names))
snap=int(any("take_snapshot" in v for v in names))
err=int(any(x.get("isError") is True or x.get("is_error") is True for x in walk(ev+final)))
# Distinguish terminal result from step/tool names, never emit private log content.
kind="NONE" if not final else ("ERROR" if flag(end,r'"(?:is_error|iserror)"\s*:\s*true|"status"\s*:\s*"(?:error|failed|failure)"') else "PRESENT")
reason="_".join(flags[:3]) if flags else "UNSPEC"
print(f"MCPFIX_{kind}_{reason}_EVENT{min(len(records),99)}_NEW{new}_SNAP{snap}_ERR{err}_LOG{int(bool(debug))}_STDERR{int(bool(stderr))}")
'@
   $out=@($py | & py -3 -I -B - $log 2>$null)
   if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}else{$code='MCP_READOUT_PARSE_ERROR'}
  }else{$code='MCP_READOUT_LOG_INVALID'}
 }
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
