# Verify exact prior interactive browser SRT in place. No provider, network, cache, or TV change.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$prior=@(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -Filter 'receipt-*.json' -File | ForEach-Object {
 if($_.Length -le 2048 -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  try{$r=Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
   if($r.source_commit -ceq '0ce22e9b66d785b6cc8d1ec09990681b2337f54f' -and $r.operation -ceq 'agy-native-browser-interactive-1124' -and $r.nonce -cmatch '^[a-f0-9]{32}$'){$r}
  }catch{}
 }
})
$code='NATIVE_PRIOR_NOT_UNIQUE'
if($prior.Count -eq 1){
 $root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
 $profile=Join-Path $root 'ChromeProfile'
 $run=Join-Path $root ('spiderman-'+$prior[0].nonce)
 $owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
 $py=@'
import sys,pathlib,re
run,owner=map(pathlib.Path,sys.argv[1:])
f=run/"english.srt"
if not f.is_file() or f.is_symlink():
    print("SRT_NOT_FOUND");sys.exit(0)
if f.stat().st_size>2000000:
    print("SRT_TOO_LARGE");sys.exit(0)
raw=f.read_bytes()
sys.path[:0]=[str(owner/"app/poc/p2-sub-discovery"),str(owner/"app/poc/p2-aisub")]
try:
    from opensubtitles import validate_timed_text
    from cue_pipeline import parse_cues
    count=validate_timed_text(raw,"srt")
    assert count>=50 and len(parse_cues(raw,"srt"))==count
    times=re.findall(rb"(?m)^\d{2}:\d{2}:\d{2},\d{3}\s+-->\s+(\d{2}):(\d{2}):(\d{2}),\d{3}",raw)
    last=max(int(h)*3600+int(m)*60+int(s) for h,m,s in times)
    print(f"SRT_VALID_{count}C_{len(raw)}B_LAST{last}S")
except Exception:print("SRT_VALIDATION_FAILED")
'@
 $f=Join-Path $env:TEMP ('ttv-native-srt-qa-'+[Guid]::NewGuid().ToString('N')+'.py')
 try{
  [IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
  $out=@(& py -3 -I -B $f $run $owner 2>$null)
  if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}else{$code='SRT_QA_READ_ERROR'}
 }finally{Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue}
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
