# Exact media metadata comparison for the already downloaded V4 artifact; no provider or playback.
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
    # Resolve only the owner-supplied exact release using installed localhost reader.
    from owner_torrserver_readonly import OwnerLocalTorrServer,OwnerTorrServerReader,_local_post,_NoRedirect
    from urllib.request import build_opener,ProxyHandler,Request
    from fractions import Fraction
    policy=json.loads((owner/"p3-p4-policy.json").read_text("utf-8"))
    cfg=OwnerLocalTorrServer(policy["profile_id"],policy["torrserver_port"])
    listing=json.loads(_local_post(cfg.url,b'{"action":"list"}',6.0))
    if not isinstance(listing,list) or len(listing)>256:return "TR08MEDIA_LIST_INVALID"
    def norm(x):return re.sub(r"[^a-z0-9]","",str(x).casefold())
    target="ironman22010repack1080pblurayx264nikt0"
    found={}
    for t in listing:
        if not isinstance(t,dict):continue
        tor=t.get("hash")
        if not isinstance(tor,str) or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}",tor):continue
        files=t.get("file_stats")
        if not files:
            try:files=json.loads(t.get("data","{}"))["TorrServer"]["Files"]
            except (TypeError,ValueError,KeyError):continue
        if not isinstance(files,list) or len(files)>4096:continue
        for x in files:
            if not isinstance(x,dict):continue
            name=str(x.get("path","")).replace("\\","/").rsplit("/",1)[-1]
            idx=x.get("id")
            if type(idx) is not int or not 0<=idx<4096 or not re.search(r"\.(mkv|mp4|avi|m4v|ts|m2ts)$",name,re.I):continue
            if norm(pathlib.PurePosixPath(name).stem)!=target and norm(t.get("title",""))!=target:continue
            if type(x.get("length")) is int and x["length"]>100000000:found[(tor,idx)]=name
    if len(found)!=1:return f"TR08MEDIA_MATCHES{len(found)}"
    (tor,idx),name=next(iter(found.items()))
    actual=OwnerTorrServerReader(cfg)(cfg.profile_id,tor,idx)
    if actual.path.replace("\\","/").rsplit("/",1)[-1]!=name:return "TR08MEDIA_DRIFT"
    exact=int(norm(pathlib.PurePosixPath(name).stem)==target)
    size=round(actual.length/1048576)
    # Metadata endpoint only; no play/range request or torrent modification.
    fps=dur=embedded=0
    state='UNKNOWN'
    from urllib.error import HTTPError,URLError
    from socket import timeout
    try:
        endpoint=f"http://127.0.0.1:{cfg.localhost_port}/ffp/{tor}/{idx}"
        opener=build_opener(ProxyHandler({}),_NoRedirect())
        with opener.open(Request(endpoint,headers={"Accept":"application/json","Cache-Control":"no-store"}),timeout=6) as resp:
            data=resp.read(131073)
            if len(data)>131072:raise ValueError("metadata too large")
            doc=json.loads(data)
        if not isinstance(doc,dict):return "TR08FFP_RESPONSE_NOT_OBJECT"
        streams=doc.get("streams",[])
        if not isinstance(streams,list) or len(streams)>128:raise ValueError("streams")
        v=next((s for s in streams if isinstance(s,dict) and s.get("codec_type")=="video"),{})
        state="VIDEO" if v else "NO_VIDEO"
        for x in (v.get("avg_frame_rate"),v.get("r_frame_rate")):
            try:
                rate=float(Fraction(str(x)))
                if 1<=rate<=120:fps=round(rate*1000);break
            except (ValueError,ZeroDivisionError):pass
        for x in (doc.get("format",{}).get("duration"),v.get("duration")):
            try:
                d=float(x)
                if 0<d<86400:dur=round(d);break
            except (TypeError,ValueError):pass
        embedded=sum(isinstance(s,dict) and s.get("codec_type")=="subtitle" and str(s.get("tags",{}).get("language","")).lower() in ("en","eng","english") for s in streams)
    except HTTPError as e:state="HTTP"+str(e.code)
    except URLError as e:state="TIMEOUT" if isinstance(e.reason,TimeoutError) else "URLERROR"
    except (TimeoutError,timeout):state="TIMEOUT"
    except (ValueError,TypeError,AttributeError):state="INVALID"
    except OSError:state="IOERROR"
    delta=dur-last if dur else 0
    # duration may be unknown; avoid interpreting it as zero-length film.
    sign="P" if delta>=0 else "N"
    return f"TR08FFP_{state}_EX{exact}FPS{fps}D{dur}L{last}EN{embedded}"

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
