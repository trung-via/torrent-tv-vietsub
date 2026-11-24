# Read the prior exact Neon attempt; never rerun the provider or modify its files.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'AGY_OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$prior=@(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -Filter 'receipt-*.json' -File | ForEach-Object {
 if($_.Length -le 2048 -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  try {$r=Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
   if($r.source_commit -ceq '63049a550c70cc8f066084bb61e7595888f15e7b' -and $r.operation -ceq 'agy-neon-indexed-search-1124' -and $r.nonce -cmatch '^[a-f0-9]{32}$'){$r}
  }catch{}
 }
})
$code='NEON_PRIOR_RECEIPT_NOT_UNIQUE'
if($prior.Count -eq 1){
 $run=Join-Path $env:LOCALAPPDATA ('TorrentTVVietsub\AGYWebsiteSmoke\neon-indexed-'+$prior[0].nonce)
 $owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
 $py=@'
import json, pathlib, re, sys
run,owner=map(pathlib.Path,sys.argv[1:])
def read(name,limit=16000000):
    f=run/name
    if f.is_symlink() or not f.is_file() or f.stat().st_size>limit: return ""
    return f.read_text(encoding="utf-8",errors="replace")
def main():
    fields={"status","release_name","source_page","download_url","reason","file_name"}
    result=[]
    for line in read("agy-stdout.jsonl").splitlines():
        try: e=json.loads(line)
        except ValueError: continue
        if isinstance(e,dict) and e.get("event")=="result": result.append(e.get("result"))
    if len(result)!=1 or not isinstance(result[0],dict): return "NEON_EVENT_MISSING"
    r=result[0].get("structured_output")
    shape="MISSING" if r is None else "STRING" if isinstance(r,str) else "OTHER"
    status="UNKNOWN"
    if isinstance(r,str):
        try: r=json.loads(r)
        except ValueError: pass
    if isinstance(r,dict):
        shape="EXTRA_KEYS" if set(r)-fields else "MISSING_KEYS" if fields-set(r) else "NONSTRING" if any(not isinstance(v,str) for v in r.values()) else "OBJECT_VALID"
        st=r.get("status")
        if st in ("FOUND","NO_MATCH","SEARCH_BLOCKED","DOWNLOAD_BLOCKED","ERROR"): status=st
        reason=str(r.get("reason",""))
        if re.search(r"\b401\b|captcha|challenge|cloudflare",reason,re.I): status="CHALLENGE"
    elif isinstance(r,str) and re.search(r"\b401\b|captcha|challenge|cloudflare",r,re.I): status="CHALLENGE"
    f=run/"english.srt"
    artifact="NO_FILE"
    if f.is_file() and not f.is_symlink():
        artifact="BAD_FILE"
        if 1000<=f.stat().st_size<=2000000:
            app=owner/"app/poc"
            sys.path[:0]=[str(app/"p2-sub-discovery"),str(app/"p2-aisub")]
            from opensubtitles import validate_timed_text
            from cue_pipeline import parse_cues
            try:
                raw=f.read_bytes(); count=validate_timed_text(raw,"srt")
                if count>=50 and len(parse_cues(raw,"srt"))==count: artifact="SRT_"+str(count)
            except Exception: pass
    return "NEON_"+shape+"_"+status+"_"+artifact
try: print(main())
except Exception: print("NEON_READOUT_PRIVATE_ERROR")
'@
 $f=Join-Path $env:TEMP ('ttv-neon-readout-'+[Guid]::NewGuid().ToString('N')+'.py')
 try{
  [IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
  $out=@(& py -3 -I -B $f $run $owner 2>$null)
  if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}else{$code='NEON_READOUT_ERROR'}
 }finally{Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue}
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
