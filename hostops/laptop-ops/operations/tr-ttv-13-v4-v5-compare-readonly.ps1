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
def load(source,version,prefix):
    receipts=[]
    for p in (spool/"History").glob("receipt-*.json"):
        try:
            if p.is_symlink() or not 0<p.stat().st_size<=2048:continue
            v=json.loads(p.read_text(encoding="utf-8-sig"))
            if v.get("source_commit")==source and v.get("operation")=="agy-native-browser-readout-1124" and v.get("result")=="SUCCESS" and re.fullmatch("[a-f0-9]{32}",str(v.get("nonce",""))):receipts.append(v)
        except (OSError,ValueError):pass
    if len(receipts)!=1:return "TR13QA_BIND"
    run=root/(prefix+receipts[0]["nonce"])
    p=run/"BRAIN_STUDENT_REPORT.json"
    if not p.is_file() or p.is_symlink() or not 0<p.stat().st_size<=32000000:return "TR13QA_REPORT"
    r=json.loads(p.read_text(encoding="utf-8"))
    if r.get("source_commit")!=source or r.get("model")!="gemini-4-hydrogen-low" or r.get("recipe_version")!=version or r.get("provider")!="SubtitleCat" or r.get("video_input",{}).get("release")!="Kalki.2898.AD.2024.1080p.WEB-DL.ViruseProject":return "TR13QA_DRIFT"
    arts=r.get("artifacts",[])
    if len(arts)!=1:return "TR13QA_ARTIFACT"
    a=arts[0];name=a["filename"]
    if pathlib.Path(name).name!=name:return "TR13QA_PATH"
    f=run/"browser-downloads"/name
    if not f.is_file() or f.is_symlink() or not 0<f.stat().st_size<=10000000:return "TR13QA_COPY"
    raw=f.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=a["sha256"]:return "TR13QA_HASH"
    if f.suffix.lower()==".srt":blobs=[(name,raw)]
    elif f.suffix.lower()==".zip":
        with zipfile.ZipFile(f) as z:
            blobs=[(i.filename,z.read(i)) for i in z.infolist()[:100] if i.filename.lower().endswith(".srt") and 0<i.file_size<=2000000 and not i.flag_bits&1]
    else:return "TR13QA_FORMAT"
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
    if len(matches)!=1:return "TR13QA_PARSE_NOT_UNIQUE"
    n,b,count,first,last=matches[0]
    parsed=parse_cues(b,"srt")
    normalized=[(c.start_ms,c.end_ms,c.text) for c in parsed]
    digest=hashlib.sha256(json.dumps(normalized,ensure_ascii=False,separators=(",",":")).encode("utf-8")).hexdigest()
    outputs=[v for v in r.get("tool_outcomes",[]) if isinstance(v,dict)]
    names=[str(v.get("tool","")).lower() for v in outputs]
    return dict(raw=hashlib.sha256(raw).hexdigest(),srt=hashlib.sha256(b).hexdigest(),digest=digest,count=count,first=first,last=last,k=len(names),e=sum("evaluate_script" in t for t in names),n=sum("navigate_page" in t for t in names),s=sum("take_snapshot" in t for t in names),x=sum(bool(v.get("error")) for v in outputs))
def main():
    a=load("9cbdbd4459f5db009c960164bcf4b8d9d254a91d","V4","tr-ttv-11-kalki2898ad-subtitlecat-v4-")
    b=load("7929ef249419698007aa8ee0948e2fe92cb093cf","V5","tr-ttv-13-kalki2898ad-subtitlecat-v5-")
    if isinstance(a,str):return "TR13CMP_V4_"+a
    if isinstance(b,str):return "TR13CMP_V5_"+b
    return f"TR13CMP_H{int(a['raw']==b['raw'])}S{int(a['srt']==b['srt'])}Q{int(a['digest']==b['digest'])}C{b['count']}L{b['last']}_V4K{a['k']}E{a['e']}N{a['n']}X{a['x']}_V5K{b['k']}E{b['e']}N{b['n']}X{b['x']}"

try:print(main())
except Exception:print("TR13QA_PRIVATE_ERROR")
'@
$f=Join-Path $env:TEMP ('ttv-v4-qa-'+[Guid]::NewGuid().ToString('N')+'.py')
try{
 [IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
 $out=@(& py -3 -I -B $f $spool $root $owner 2>$null)
 $code='TR13QA_READ_ERROR'
 if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
}finally{Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
