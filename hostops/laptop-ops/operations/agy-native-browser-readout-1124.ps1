# Read only the exact prior isolated MCP attempt, output sanitized evidence.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$prior=@(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -Filter 'receipt-*.json' -File | ForEach-Object {
 if($_.Length -le 2048 -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  try{$r=Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
   if($r.source_commit -ceq '64e4df93194ca7f4b609d2b47cc213af0ddc6b53' -and $r.operation -ceq 'agy-browser-headless-control-1124' -and $r.nonce -cmatch '^[a-f0-9]{32}$'){$r}
  }catch{}
 }
})
$code='MCP_READOUT_PRIOR_NOT_UNIQUE'
if($prior.Count -eq 1){
 $root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
 $run=Join-Path $root ('agy-self-setup-'+$prior[0].nonce)
 $log=Join-Path $run 'RESULT.json'
 $code='MCP_READOUT_LOG_MISSING'
 if(Test-Path -LiteralPath $log -PathType Leaf){
  $file=Get-Item -LiteralPath $log
  if($file.Length -gt 0 -and $file.Length -le 4194304 -and -not ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){
   $py=@'
import sys,json,pathlib,re
root=pathlib.Path(sys.argv[1]).parent
def read(name):
    p=root/name
    if p.is_symlink() or not p.is_file() or p.stat().st_size>1000000:return ""
    return p.read_text(encoding="utf-8-sig",errors="replace")
setup=read("SETUP.md").lower()
raw=read("RESULT.json")
try:r=json.loads(raw)
except Exception:r={}
if not isinstance(r,dict):r={}
# Only emit fixed classifications; no raw private paths, URLs, or logs.
report=json.dumps(r,ensure_ascii=False).lower()
method_values=[]
def walk(v):
    if isinstance(v,dict):
        for k,x in v.items():
            if re.search(r"method|approach|mechanism|browser_tool|implementation|technique",str(k),re.I) and isinstance(x,str):method_values.append(x.lower())
            walk(x)
    elif isinstance(v,list):
        for x in v:walk(x)
walk(r)
methods=" ".join(method_values)
def classify(t):
    flags=[n for n,pat in [("PLAYWRIGHT",r"playwright"),("PUPPETEER",r"puppeteer"),("SELENIUM",r"selenium"),("MCP",r"chrome.devtools.mcp"),("CDP",r"\bcdp\b|remote.debugging.port"),("CHROMECLI",r"dump.dom|chrome.exe.*headless")] if re.search(pat,t)]
    return flags[0] if len(flags)==1 else ("MULTI" if flags else "UNKNOWN")
method=classify(methods)
if method=="UNKNOWN":method=classify(setup)
# Reported categories may coexist; do not mistake them for direct observations.
checks=[("HTTP403",r"\b403\b|forbidden"),("HTTP429",r"\b429\b|too many requests"),("CAPTCHA",r"captcha|human verification|turnstile"),("CLOUDFLARE",r"cloudflare"),("LOGIN",r"login required|sign.in required|authentication required"),("DENIED",r"access denied|access blocked|blocked by"),("NO_MATCH",r"no matching|no exact match|not found")]
flags=[n for n,pat in checks if re.search(pat,report)]
block="_".join(flags[:3]) if flags else "UNSPECIFIED"
print(f"AGY_READ_{method}_{block}_JSON{int(bool(r))}_SETUP{int(bool(setup))}")
'@
   $out=@($py | & py -3 -I -B - $log 2>$null)
   if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}else{$code='MCP_READOUT_PARSE_ERROR'}
  }else{$code='MCP_READOUT_LOG_INVALID'}
 }
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
