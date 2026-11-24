# Read the exact Iron Man 2 V3 report without provider calls or raw report export.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
$prior=@(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -Filter 'receipt-*.json' -File|ForEach-Object {
 if($_.Length -le 2048 -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  try{$r=Get-Content -LiteralPath $_.FullName -Raw|ConvertFrom-Json
   if($r.source_commit -ceq 'b8384755853b8a069795bf9f4257624725a54b7d' -and $r.operation -ceq 'agy-native-browser-readout-1124' -and $r.result -ceq 'SUCCESS' -and $r.nonce -cmatch '^[a-f0-9]{32}$'){$r}
  }catch{}
 }
})
$code='TR06IM_PRIOR_NOT_UNIQUE'
if($prior.Count -eq 1){
 $run=Join-Path $env:LOCALAPPDATA ('TorrentTVVietsub\NativeBrowserTest\tr-ttv-06-ironman2-v3-'+$prior[0].nonce)
 $owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
 $py=@'
import sys,pathlib,json,hashlib,re,zipfile
run,owner=map(pathlib.Path,sys.argv[1:])
def main():
    p=run/"BRAIN_STUDENT_REPORT.json"
    if not p.is_file() or p.is_symlink() or not 0<p.stat().st_size<=16000000:return "TR06IM_REPORT_MISSING"
    r=json.loads(p.read_text(encoding="utf-8"))
    if r.get("source_commit")!="b8384755853b8a069795bf9f4257624725a54b7d" or r.get("recipe_version")!="V3" or r.get("model")!="gemini-4-hydrogen-low":return "TR06IM_BINDING_MISMATCH"
    if r.get("video_input",{}).get("release")!="Iron Man 2 2010 REPACK 1080p BluRay x264-nikt0":return "TR06IM_INPUT_MISMATCH"
    final="\n".join(v for v in r.get("final_response",[]) if isinstance(v,str))
    statuses={"NO_CONFIDENT_MATCH":"NCM","NO_MATCH":"NM","ACCESS_BLOCKED":"AB","ACCESS_DENIED":"AD","AUTH_REQUIRED":"AR","DOWNLOAD_FAILED":"DF","DOWNLOAD_BLOCKED":"DB","TOOL_UNAVAILABLE":"TU","DOWNLOADED_REPORTED":"DR","FOUND":"FD","ERROR":"ER","UNKNOWN":"UK"}
    found=re.search(r"""(?im)(?:^|\n|[,{])\s*["*]*status["*]*\s*[:=]\s*["*]*([A-Z_]+)""",final)
    status=statuses.get(found.group(1).upper(),"UK") if found else "UK"
    outputs=[v for v in r.get("tool_outcomes",[]) if isinstance(v,dict)]
    text="\n".join(str(v.get("output","")) for v in outputs)
    # Presence of release words is only an observation, not candidate or timing proof.
    exact=int(bool(re.search(r"iron[ ._-]*man[ ._-]*2[ ._-]+2010[ ._-]+repack[ ._-]+1080p[ ._-]+blu[ ._-]*ray[ ._-]+x264[ ._-]+nikt0\b",text,re.I)))
    group=int(bool(re.search(r"\bnikt0\b",text,re.I)))
    film=int(bool(re.search(r"\biron[ ._-]*man[ ._-]*2\b",text,re.I)))
    bluray=int(bool(re.search(r"\bblu[ ._-]*ray\b",text,re.I)))
    errors=sum(bool(v.get("error")) for v in outputs)
    # Separate tool errors and normal access state from reported selection status.
    e="\n".join(str(v.get("error") or "") for v in outputs)
    blocked=int(bool(re.search(r"\b(?:401|403|429)\b|captcha|access denied|rate limit",e,re.I)))
    dl=int(bool(re.search(r"download (?:failed|blocked|denied)|failed to download",final,re.I)))
    return f"TR06IM_{status}_K{len(outputs)}X{errors}B{blocked}F{film}G{group}E{exact}S{bluray}D{dl}P{len(r.get('physical_files',[]))}A{len(r.get('artifacts',[]))}"

try: print(main())
except Exception: print("TR06IM_PRIVATE_ERROR")
'@
 $f=Join-Path $env:TEMP ('ttv-student-v2-qa-'+[Guid]::NewGuid().ToString('N')+'.py')
 try{
  [IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
  $out=@(& py -3 -I -B $f $run $owner 2>$null)
  if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}else{$code='TR06IM_READ_ERROR'}
 }finally{Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue}
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
