# Independent QA of the exact completed V4 artifact. No provider, playback or cache writes.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$py=@'
import sys,pathlib,json,re,hashlib,zipfile,urllib.parse
spool,root,owner=map(pathlib.Path,sys.argv[1:])
source="8570d25c3cc1d5f74774c5bd4703f278ef47a06f"
def main():
    receipts=[]
    for p in (spool/"History").glob("receipt-*.json"):
        try:
            if p.is_symlink() or not 0<p.stat().st_size<=2048:continue
            v=json.loads(p.read_text(encoding="utf-8-sig"))
            if v.get("source_commit")==source and v.get("operation")=="agy-native-browser-readout-1124" and v.get("result")=="SUCCESS" and re.fullmatch("[a-f0-9]{32}",str(v.get("nonce",""))):receipts.append(v)
        except (OSError,ValueError):pass
    if len(receipts)!=1:return "TR08QA_BIND"
    run=root/("tr-ttv-08-ironman2-subtitlecat-v4-"+receipts[0]["nonce"])
    p=run/"BRAIN_STUDENT_REPORT.json"
    if not p.is_file() or p.is_symlink() or not 0<p.stat().st_size<=32000000:return "TR08QA_REPORT"
    r=json.loads(p.read_text(encoding="utf-8"))
    if r.get("source_commit")!=source or r.get("model")!="gemini-4-hydrogen-low" or r.get("recipe_version")!="V4" or r.get("provider")!="SubtitleCat" or r.get("video_input",{}).get("release")!="Iron Man 2 2010 REPACK 1080p BluRay x264-nikt0":return "TR08QA_DRIFT"
    arts=r.get("artifacts",[])
    if len(arts)!=1:return "TR08QA_ARTIFACT"
    a=arts[0];name=a["filename"]
    if pathlib.Path(name).name!=name:return "TR08QA_PATH"
    f=run/"browser-downloads"/name
    if not f.is_file() or f.is_symlink() or not 0<f.stat().st_size<=10000000:return "TR08QA_COPY"
    raw=f.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=a["sha256"]:return "TR08QA_HASH"
    if f.suffix.lower()==".srt":blobs=[(name,raw)]
    elif f.suffix.lower()==".zip":
        with zipfile.ZipFile(f) as z:
            blobs=[(i.filename,z.read(i)) for i in z.infolist()[:100] if i.filename.lower().endswith(".srt") and 0<i.file_size<=2000000 and not i.flag_bits&1]
    else:return "TR08QA_FORMAT"
    sys.path[:0]=[str(owner/"app/poc/p2-sub-discovery"),str(owner/"app/poc/p2-aisub")]
    from opensubtitles import validate_timed_text
    from cue_pipeline import parse_cues
    matches=[]
    for n,b in blobs:
        try:
            count=validate_timed_text(b,"srt")
            cues=parse_cues(b,"srt")
            if count!=len(cues) or count!=a["cues"]:continue
            t=re.findall(rb"(?m)^(\d{2}):(\d{2}):(\d{2})[,.]\d{3}\s+-->\s+(\d{2}):(\d{2}):(\d{2})[,.]\d{3}",b)
            if len(t)!=count:continue
            first=min(int(h)*3600+int(m)*60+int(s) for h,m,s,_,_,_ in t)
            last=max(int(h)*3600+int(m)*60+int(s) for _,_,_,h,m,s in t)
            matches.append((n,b,count,first,last))
        except Exception:pass
    if len(matches)!=1:return "TR08QA_PARSE_NOT_UNIQUE"
    n,b,count,first,last=matches[0]
    # English language heuristic on actual cue text, never export dialogue.
    body=re.sub(r"(?m)^\s*\d+\s*$|^.*-->.*$","",b.decode("utf-8-sig",errors="replace"))
    words=re.findall(r"[a-z]+",body.lower())
    stop=set("the a an i you he she it we they to of and in is are was were for that this have has do did not my your me him her what why how with on be can will would".split())
    en=int(len(words)>1000 and sum(w in stop for w in words)/len(words)>.16)
    meta=" ".join([name,n]+[urllib.parse.unquote(str(x)) for x in a.get("candidate_refs",[])])
    film=int(bool(re.search(r"iron[ ._-]*man[ ._-]*2\b",meta,re.I)))
    year=int(bool(re.search(r"\b2010\b",meta)))
    group=int(bool(re.search(r"\bnikt0\b",meta,re.I)))
    repack=int(bool(re.search(r"\brepack\b",meta,re.I)))
    bluray=int(bool(re.search(r"\bblu[ ._-]*ray\b|\bbdrip\b",meta,re.I)))
    outputs=[v for v in r.get("tool_outcomes",[]) if isinstance(v,dict)]
    errors=sum(bool(v.get("error")) for v in outputs)
    return f"TR08QA_C{count}F{first}L{last}EN{en}M{film}Y{year}G{group}R{repack}B{bluray}K{len(outputs)}X{errors}"
try:print(main())
except Exception:print("TR08QA_PRIVATE_ERROR")
'@
$f=Join-Path $env:TEMP ('ttv-v4-qa-'+[Guid]::NewGuid().ToString('N')+'.py')
try{
 [IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
 $out=@(& py -3 -I -B $f $spool $root $owner 2>$null)
 $code='TR08QA_READ_ERROR'
 if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
}finally{Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
