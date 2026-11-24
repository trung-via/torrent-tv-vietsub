# Read only the exact prior isolated MCP attempt, output sanitized evidence.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$prior=@(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -Filter 'receipt-*.json' -File | ForEach-Object {
 if($_.Length -le 2048 -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  try{$r=Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
   if($r.source_commit -ceq '6739c0c27e347e69e2049a474fe5ed9a8c942a79' -and $r.operation -ceq 'agy-browser-headless-control-1124' -and $r.nonce -cmatch '^[a-f0-9]{32}$'){$r}
  }catch{}
 }
})
$code='MCP_READOUT_PRIOR_NOT_UNIQUE'
if($prior.Count -eq 1){
 $root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
 $run=Join-Path $root ('agy-access-diagnosis-'+$prior[0].nonce)
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
# Only fixed, sanitized labels; never output raw AGY report, private paths or secrets.
def text(k):
    return json.dumps(r.get(k,""),ensure_ascii=False).lower()
method=text("method")
cause=text("cause")
test=text("actual_test")
next_action=text("next_action")
def f(t,p):return int(bool(re.search(p,t)))
api=f(method,r"\bapi\b|rest")
web=f(method,r"website|browser|playwright|web interface")
cli=f(method,r"opensubs.cli|command.line|\bcli\b")
key=f(method+" "+next_action,r"api.key|developer.key")
login=f(method+" "+next_action,r"login|log.in|sign.in|account|username|password")
unknown=f(cause,r"unknown|not (?:confirmed|known|determined|explicit)|uncertain|unconfirmed")
bot=f(cause,r"cloudflare|bot|captcha|challenge|waf")
no_test=f(test,r"not (?:tested|performed|attempted|executed|run)|no (?:live|new|additional|test|request)|documentation.only|skipped|none")
paid=f(next_action,r"paid|payment|subscription|vip")
docs=r.get("official_sources",[])
doc=len(docs) if isinstance(docs,list) else 0
print(f"ACCESS_READ_API{api}_WEB{web}_CLI{cli}_KEY{key}_LOGIN{login}_UNK{unknown}_BOT{bot}_NOTEST{no_test}_PAID{paid}_DOC{min(doc,99)}")
'@
   $out=@($py | & py -3 -I -B - $log 2>$null)
   if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}else{$code='MCP_READOUT_PARSE_ERROR'}
  }else{$code='MCP_READOUT_LOG_INVALID'}
 }
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
