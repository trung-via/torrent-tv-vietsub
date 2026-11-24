# Read only the exact prior isolated MCP attempt, output sanitized evidence.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$prior=@(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -Filter 'receipt-*.json' -File | ForEach-Object {
 if($_.Length -le 2048 -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  try{$r=Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
   if($r.source_commit -ceq 'dc55c5566dec8d11d2cb77ac6c8476254360f2a5' -and $r.operation -ceq 'agy-browser-headless-control-1124' -and $r.nonce -cmatch '^[a-f0-9]{32}$'){$r}
  }catch{}
 }
})
$code='MCP_READOUT_PRIOR_NOT_UNIQUE'
if($prior.Count -eq 1){
 $root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
 $run=Join-Path $root ('agy-cdp9555-live-'+$prior[0].nonce)
 $log=Join-Path $run 'RESULT.json'
 $code='MCP_READOUT_LOG_MISSING'
 if(Test-Path -LiteralPath $log -PathType Leaf){
  $file=Get-Item -LiteralPath $log
  if($file.Length -gt 0 -and $file.Length -le 4194304 -and -not ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){
   $py=@'
import json,re,sys,pathlib
p=pathlib.Path(sys.argv[1])
r=json.loads(p.read_text(encoding="utf-8-sig"))
if not isinstance(r,dict):raise ValueError("invalid report")
def text(k):return json.dumps(r.get(k,""),ensure_ascii=False).lower()
def f(t,p):return int(bool(re.search(p,t)))
method=text("method")
test=text("actual_test")
pw=f(method,r"playwright")
cdp=f(method,r"cdp|9555")
login=f(test,r"log.in|sign.in|authentication required|login")
challenge=f(test,r"captcha|cloudflare|challenge|turnstile|bot protection")
www=f(test,r"www.authenticate|basic authentication|bearer")
unauth=f(test,r"\b401\b|unauthorized")
body=f(test,r"response body|page content|page text|page title")
dom=f(test,r"page\.goto|navigation response|main.document|document response")
home=int(r.get("stage")=="HOME")
# Read only the exact saved agent report; flags are reported observations, not a new network probe.
print(f"9555_READ_PW{pw}_CDP{cdp}_HOME{home}_H401{unauth}_LOGIN{login}_CHAL{challenge}_WWW{www}_BODY{body}_NAV{dom}")
'@
   $out=@($py | & py -3 -I -B - $log 2>$null)
   if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}else{$code='MCP_READOUT_PARSE_ERROR'}
  }else{$code='MCP_READOUT_LOG_INVALID'}
 }
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
