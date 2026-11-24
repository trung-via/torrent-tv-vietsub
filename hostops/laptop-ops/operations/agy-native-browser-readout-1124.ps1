# Read-only diagnosis of the exact completed AGY stdio acquisition. No provider call.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$prior=@(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -Filter 'receipt-*.json' -File | ForEach-Object {
 if($_.Length -le 2048 -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  try{$r=Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
   if($r.source_commit -ceq '5f1a8f2e386ace6e08336402ce2c3570bad411ee' -and $r.operation -ceq 'agy-browser-headless-control-1124' -and $r.result -ceq 'SUCCESS' -and $r.nonce -cmatch '^[a-f0-9]{32}$'){$r}
  }catch{}
 }
})
$code='STDREAD_PRIOR_NOT_UNIQUE'
if($prior.Count -eq 1){
 $run=Join-Path $env:LOCALAPPDATA ('TorrentTVVietsub\NativeBrowserTest\agy-cdp9555-mcp-stdio-'+$prior[0].nonce)
 $py=@'
import sys,pathlib,json,re
p=pathlib.Path(sys.argv[1])
def read(name):
    q=p/name
    if q.is_symlink() or not q.is_file() or q.stat().st_size>4194304:return ""
    return q.read_text(encoding="utf-8-sig",errors="replace")
def rows(name):
    out=[]
    for line in read(name).splitlines():
        try:
            v=json.loads(line)
            if isinstance(v,dict):out.append(v)
        except ValueError:pass
    return out
try:
    rr=json.loads(read("RESULT.json"))
    if not isinstance(rr,dict):raise ValueError()
except (ValueError,TypeError):rr={}
trace=[x.get("tool") for x in rows("mcp-trace.jsonl") if x.get("ok") is True]
ev=rows("agy-stdout.jsonl")
term=[x for x in ev if x.get("event")=="result"]
def count(*names):return min(99,sum(trace.count(n) for n in names))
reported=str(rr.get("actual_test",""))+" "+str(rr.get("reason",""))
reason="UNSPEC"
for label,pattern in [("DENIAL",r"captcha|access denied|forbidden|login required"),("RELEASE",r"release.{0,50}(?:mismatch|not match|not found|different)|(?:no|not).{0,30}(?:selezen|matching release)"),("TIMING",r"timing|frame rate|fps"),("EMPTY",r"no (?:results|subtitles)|zero results"),("TIME",r"timeout|timed out")]:
    if re.search(pattern,reported,re.I):reason=label;break
print(f"STDREAD_R{int(bool(rr))}_T{min(len(term),9)}_NAV{count('navigate_page')}_SN{count('take_snapshot')}_CL{count('click')}_FL{count('fill','fill_form','type_text')}_END{count('close_page')}_{reason}")
'@
 $out=@($py | & py -3 -I -B - $run 2>$null)
 if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}else{$code='STDREAD_PARSE_ERROR'}
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
