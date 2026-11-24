# Read-only classification of the two exact prior AGY runs; no network/provider.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'AGY_OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
function Prior([string]$commit,[string]$operation){
 @(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -Filter 'receipt-*.json' -File | ForEach-Object {
  if($_.Length -le 2048 -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)){
   try{$r=Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
    if($r.source_commit -ceq $commit -and $r.operation -ceq $operation -and $r.nonce -cmatch '^[a-f0-9]{32}$'){$r}
   }catch{}
  }
 })
}
$a=@(Prior 'badb47b18d323d1dcedfe780625fd795239d24a7' 'agy-odyssey-direct-test-c-1124')
$b=@(Prior '8cda19a0d2ebed69a87bc5e3e85db5552991939d' 'agy-spiderman-model-compare-1124')
$code='TRACE_PRIOR_NOT_UNIQUE'
if($a.Count -eq 1 -and $b.Count -eq 1){
 $base=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\AGYWebsiteSmoke'
 $direct=Join-Path $base ('direct-c-'+$a[0].nonce)
 $search=Join-Path $base ('spiderman-ab-'+$b[0].nonce+'\H')
 $py=@'
import sys,json,pathlib,re
from urllib.parse import urlparse
def read(p,cap=16000000):
    if not p.is_file() or p.is_symlink() or p.stat().st_size>cap:return ""
    return p.read_text(encoding="utf-8",errors="replace")
def hosts(s):
    out=set()
    for u in re.findall(r"https?://[a-zA-Z0-9.-]+(?::[0-9]+)?",s,re.I):
        h=(urlparse(u).hostname or "").lower()
        if h=="dl.opensubtitles.org":out.add("DL")
        elif h=="opensubtitles.org" or h.endswith(".opensubtitles.org"):out.add("OS")
        elif h=="google.com" or h.endswith(".google.com"):out.add("G")
        elif h=="bing.com" or h.endswith(".bing.com"):out.add("B")
    return out
def tool(s):
    s=s.lower()
    for k,p in (("CURL",r"\bcurl(?:\.exe)?\b"),("IWR",r"invoke-webrequest"),("BROWSER",r"browser|playwright|navigate"),("SEARCH",r"web_search|google_search|search_web|websearch"),("FETCH",r"web_fetch|fetch_url|read_url|url_fetch"),("PY",r"urllib|requests\.get"),("SHELL",r"shell|powershell|terminal")):
        if re.search(p,s):return k
    return "UNK"
def trace(p):
    rows=[]
    for line in read(p/"agy-stdout.jsonl").splitlines():
        try:e=json.loads(line)
        except ValueError:continue
        if not isinstance(e,dict):continue
        typ=e.get("event")
        step=e.get("step",{})
        if (typ=="step_update" and isinstance(step,dict) and step.get("step_type")=="tool") or typ in ("tool_call","tool_result","tool_use","tool_response"):
            rows.append(json.dumps(step if typ=="step_update" else e,ensure_ascii=False))
    seen=set()
    for s in rows:seen.update(hosts(s))
    methods={tool(s) for s in rows}-{"UNK"}
    report=read(p/"result-private.json",16384)
    try:reason=json.loads(report).get("reason","")
    except Exception:reason=""
    if not isinstance(reason,str):reason=""
    rh=hosts(reason)
    # A named provider in the model report is weaker than a tool-response host.
    if not rh:
        if re.search(r"\bopensubtitles\b",reason,re.I):rh.add("OS")
        if re.search(r"\bgoogle\b",reason,re.I):rh.add("G")
        if re.search(r"\bbing\b",reason,re.I):rh.add("B")
    challenged=set()
    for s in rows:
        if re.search(r"captcha|challenge|cloudflare|\b(?:401|403|429|503)\b",s,re.I):challenged.update(hosts(s))
    return "_".join(["".join(sorted(seen)) or "NA","".join(sorted(methods))[:18] or "UNK","".join(sorted(challenged)) or "NA","".join(sorted(rh)) or "NA"])
try:
    d=trace(pathlib.Path(sys.argv[1]));s=trace(pathlib.Path(sys.argv[2]))
    print("D_"+d+"_S_"+s)
except Exception:print("TRACE_PRIVATE_ERROR")
'@
 $f=Join-Path $env:TEMP ('ttv-tooltrace-'+[Guid]::NewGuid().ToString('N')+'.py')
 try{
  [IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
  $out=@(& py -3 -I -B $f $direct $search 2>$null)
  if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}else{$code='TRACE_READ_ERROR'}
 }finally{Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue}
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
