# Compare only the two exact completed Teacher reports. No provider call or raw output export.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$py=@'
import sys,pathlib,json,re
spool,root=map(pathlib.Path,sys.argv[1:])
def read(source,prefix):
    matches=[]
    for p in (spool/"History").glob("receipt-*.json"):
        try:
            if p.is_symlink() or not 0<p.stat().st_size<=2048:continue
            v=json.loads(p.read_text(encoding="utf-8-sig"))
            if v.get("source_commit")==source and v.get("operation")=="agy-native-browser-readout-1124" and v.get("result")=="SUCCESS" and re.fullmatch("[a-f0-9]{32}",str(v.get("nonce",""))):matches.append(v)
        except (OSError,ValueError):pass
    if len(matches)!=1:return "BIND"
    p=root/(prefix+matches[0]["nonce"])/"BRAIN_TEACHER_REPORT.json"
    if not p.is_file() or p.is_symlink() or not 0<p.stat().st_size<=32000000:return "MISS"
    r=json.loads(p.read_text(encoding="utf-8"))
    if r.get("source_commit")!=source or r.get("model")!="gemini-4-neon-high" or r.get("recipe_version")!="V3" or r.get("video_input",{}).get("release")!="Iron Man 2 2010 REPACK 1080p BluRay x264-nikt0":return "DRIFT"
    final="\n".join(v for v in r.get("final_response",[]) if isinstance(v,str))
    statuses={"NO_CONFIDENT_MATCH":"NCM","NO_MATCH":"NM","ACCESS_BLOCKED":"AB","ACCESS_DENIED":"AD","AUTH_REQUIRED":"AR","DOWNLOAD_FAILED":"DF","DOWNLOAD_BLOCKED":"DB","TOOL_UNAVAILABLE":"TU","DOWNLOADED_REPORTED":"DR","FOUND":"FD","ERROR":"ER","UNKNOWN":"UK"}
    found=re.search(r"""(?im)(?:^|\n|[,{])\s*["*]*status["*]*\s*[:=]\s*["*]*([A-Z_]+)""",final)
    status=statuses.get(found.group(1).upper(),"UK") if found else "UK"
    outputs=[v for v in r.get("tool_outcomes",[]) if isinstance(v,dict)]
    txt="\n".join(str(v.get("output","")) for v in outputs)
    film=int(bool(re.search(r"\biron[ ._-]*man[ ._-]*2\b",txt,re.I)))
    group=int(bool(re.search(r"\bnikt0\b",txt,re.I)))
    exact=int(bool(re.search(r"iron[ ._-]*man[ ._-]*2[ ._-]+2010[ ._-]+repack[ ._-]+1080p[ ._-]+blu[ ._-]*ray[ ._-]+x264[ ._-]+nikt0\b",txt,re.I)))
    bluray=int(bool(re.search(r"\bblu[ ._-]*ray\b",txt,re.I)))
    errors=sum(bool(v.get("error")) for v in outputs)
    # Text markers are not candidate-bound proof.
    return f"{status}K{len(outputs)}X{errors}F{film}G{group}E{exact}S{bluray}"
try:
    a=read("f476d92f05d28ab77be6fbcbd9daee8a46594af6","tr-ttv-06-ironman2-teacher-v3-")
    b=read("8a918c7bfa4d78478eaf8316098f355ebd56d537","tr-ttv-07b-ironman2-subtitlecat-neon-")
    print("TR07CMP_OS"+a+"_SC"+b)
except Exception:print("TR07CMP_PRIVATE_ERROR")
'@
$f=Join-Path $env:TEMP ('ttv-teacher-compare-'+[Guid]::NewGuid().ToString('N')+'.py')
try{
 [IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
 $out=@(& py -3 -I -B $f $spool $root 2>$null)
 $code='TR07CMP_READ_ERROR'
 if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
}finally{Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
