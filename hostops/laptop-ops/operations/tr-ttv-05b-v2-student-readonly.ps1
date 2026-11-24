# Read only the exact completed Student V2 report and copied artifact. No provider call.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
$prior=@(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -Filter 'receipt-*.json' -File|ForEach-Object {
 if($_.Length -le 2048 -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  try{$r=Get-Content -LiteralPath $_.FullName -Raw|ConvertFrom-Json
   if($r.source_commit -ceq 'c5f56e07dfc71b1f778e346a2ba6de16508810c0' -and $r.operation -ceq 'agy-native-browser-readout-1124' -and $r.result -ceq 'SUCCESS' -and $r.nonce -cmatch '^[a-f0-9]{32}$'){$r}
  }catch{}
 }
})
$code='TR05QA_PRIOR_NOT_UNIQUE'
if($prior.Count -eq 1){
 $run=Join-Path $env:LOCALAPPDATA ('TorrentTVVietsub\NativeBrowserTest\tr-ttv-05b-hailmary-v2-'+$prior[0].nonce)
 $owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
 $py=@'
import sys,pathlib,json,hashlib,re,zipfile
run,owner=map(pathlib.Path,sys.argv[1:])
def main():
    p=run/"BRAIN_STUDENT_REPORT.json"
    if not p.is_file() or p.is_symlink() or not 0<p.stat().st_size<=16000000:return "TR05QA_REPORT_MISSING"
    r=json.loads(p.read_text(encoding="utf-8"))
    if r.get("source_commit")!="c5f56e07dfc71b1f778e346a2ba6de16508810c0" or r.get("model")!="gemini-4-hydrogen-low" or r.get("recipe_version")!="V2":return "TR05QA_BINDING_MISMATCH"
    arts=r.get("artifacts",[])
    if len(arts)!=1:return "TR05QA_ARTIFACT_NOT_UNIQUE"
    a=arts[0]; name=a["filename"]
    if pathlib.Path(name).name!=name:return "TR05QA_PATH_INVALID"
    f=run/"browser-downloads"/name
    if not f.is_file() or f.is_symlink() or not 0<f.stat().st_size<=10000000:return "TR05QA_COPY_MISSING"
    raw=f.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=a["sha256"]:return "TR05QA_HASH_MISMATCH"
    if f.suffix.lower()==".srt": blobs=[raw]
    elif f.suffix.lower()==".zip":
        with zipfile.ZipFile(f) as z:
            blobs=[z.read(i) for i in z.infolist()[:100] if i.filename.lower().endswith(".srt") and 0<i.file_size<=2000000 and not i.flag_bits&1]
    else:return "TR05QA_FORMAT_UNKNOWN"
    sys.path[:0]=[str(owner/"app/poc/p2-sub-discovery"),str(owner/"app/poc/p2-aisub")]
    from opensubtitles import validate_timed_text
    from cue_pipeline import parse_cues
    matches=[]
    for b in blobs:
        try:
            count=validate_timed_text(b,"srt")
            if count!=a["cues"] or count!=len(parse_cues(b,"srt")):continue
            t=re.findall(rb"(?m)^(\d{2}):(\d{2}):(\d{2})[,.]\d{3}\s+-->\s+(\d{2}):(\d{2}):(\d{2})[,.]\d{3}",b)
            if len(t)!=count:continue
            first=min(int(h)*3600+int(m)*60+int(s) for h,m,s,_,_,_ in t)
            last=max(int(h)*3600+int(m)*60+int(s) for _,_,_,h,m,s in t)
            matches.append((count,first,last))
        except Exception:pass
    if len(matches)!=1:return "TR05QA_SRT_NOT_UNIQUE_VALID"
    count,first,last=matches[0]
    clues=[str(v.get("observed_release_text","")) for v in r.get("observed_release_candidates",[]) if isinstance(v,dict)]
    exact=int(any(re.search(r"project[ ._-]+hail[ ._-]+mary[ ._-]+2026[ ._-]+webrip[ ._-]+720p[ ._-]+new[ ._-]+team",v,re.I) for v in clues))
    final=r.get("final_response",[])
    final_present=int(isinstance(final,list) and any(isinstance(v,str) and v.strip() for v in final))
    full=run/"BRAIN_STUDENT_FULL_RESPONSE.md"
    full_present=int(full.is_file() and not full.is_symlink() and full.stat().st_size>0)
    tools=r.get("tool_names",[])
    # Only public-safe scalar/boolean observations; never export dialogue, path, IDs, URLs or raw tool outputs.
    return f"TR05QA_C{count}F{first}L{last}E{exact}R{final_present}M{full_present}K{len(tools)}Q{int(r.get('title_language_evidence',False))}"
try: print(main())
except Exception: print("TR05QA_PRIVATE_ERROR")
'@
 $f=Join-Path $env:TEMP ('ttv-student-v2-qa-'+[Guid]::NewGuid().ToString('N')+'.py')
 try{
  [IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
  $out=@(& py -3 -I -B $f $run $owner 2>$null)
  if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}else{$code='TR05QA_READ_ERROR'}
 }finally{Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue}
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
