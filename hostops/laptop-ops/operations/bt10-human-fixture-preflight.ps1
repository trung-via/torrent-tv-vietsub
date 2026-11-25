# BT10H: Human-selected exact release preflight, no provider or production call.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('bt10-human-fixture-preflight-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$py=@'
import sys,pathlib,json,re,hashlib,zipfile,html,collections,difflib,statistics
root,spool=map(pathlib.Path,sys.argv[1:3])
def obj(p):
    assert p.is_file() and not p.is_symlink() and p.stat().st_size<16777216
    return json.loads(p.read_text(encoding="utf-8-sig"))
import shutil,subprocess,math
run=pathlib.Path(sys.argv[3])
phase="LIBRARY"
def main():
    global phase
    owner=root.parent/"OwnerBridge"
    sys.path.insert(0,str(owner/"app/poc/p2-sub-discovery"))
    from owner_torrserver_readonly import OwnerLocalTorrServer,OwnerTorrServerReader,_local_post
    policy=obj(owner/"p3-p4-policy.json")
    cfg=OwnerLocalTorrServer(policy["profile_id"],policy["torrserver_port"])
    listing=json.loads(_local_post(cfg.url,b'{"action":"list"}',6.0))
    assert isinstance(listing,list) and len(listing)<=256
    target="0c57a7ebb1d8c09b29b6642d48af57701ca4479e6d6d9f63fa8ae3c26a615b5e"
    def matches(x):
        x=pathlib.PurePosixPath(str(x).replace("\\","/")).name
        if re.search(r"\.(mkv|mp4|avi|m4v|ts|m2ts)$",x,re.I):x=pathlib.PurePosixPath(x).stem
        return hashlib.sha256(re.sub(r"[^a-z0-9]","",x.casefold()).encode()).hexdigest()==target
    found={}
    for v in listing:
        if not isinstance(v,dict):continue
        tor=v.get("hash")
        if not isinstance(tor,str) or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}",tor):continue
        files=v.get("file_stats")
        if not files:
            try:files=json.loads(v.get("data","{}"))["TorrServer"]["Files"]
            except (ValueError,TypeError,KeyError):continue
        if not isinstance(files,list) or len(files)>4096:continue
        for x in files:
            if not isinstance(x,dict):continue
            name=str(x.get("path","")).replace("\\","/").rsplit("/",1)[-1]
            idx=x.get("id")
            if type(idx) is not int or not 0<=idx<4096 or not re.search(r"\.(mkv|mp4|avi|m4v|ts|m2ts)$",name,re.I):continue
            if not (matches(name) or matches(v.get("title",""))):continue
            if type(x.get("length")) is int and x["length"]>100000000:found[(tor,idx)]=(name,x["length"])
    if len(found)!=1:
        print(f"BT10H_HOLD_MATCHES{min(len(found),999)}");return
    phase="EXACT_FILE"
    (tor,idx),(name,size)=next(iter(found.items()))
    actual=OwnerTorrServerReader(cfg)(cfg.profile_id,tor,idx)
    assert actual.path.replace("\\","/").rsplit("/",1)[-1]==name
    phase="PROBE"
    doc={};kind="NONE"
    try:
        from owner_torrserver_ffp_tracks import _read_local_ffp
        doc=json.loads(_read_local_ffp(f"http://127.0.0.1:{cfg.localhost_port}/ffp/{tor}/{idx}",8.0))
        if isinstance(doc.get("streams"),list) and doc["streams"]:kind="FFP"
    except Exception:pass
    # The earlier FFP endpoint could not return tracks; bounded local ffprobe only, no provider.
    if kind=="NONE" or not doc.get("format",{}).get("duration"):
        fp=shutil.which("ffprobe")
        if fp:
            url=f"http://127.0.0.1:{cfg.localhost_port}/play/{tor}/{idx}"
            try:
                with (run/"ffprobe.out").open("wb") as out,(run/"ffprobe.err").open("wb") as err:
                    rc=subprocess.run([fp,"-v","error","-rw_timeout","12000000","-protocol_whitelist","http,tcp","-show_streams","-show_format","-of","json",url],stdout=out,stderr=err,timeout=45,check=False).returncode
                if rc==0:
                    p=obj(run/"ffprobe.out")
                    if isinstance(p.get("streams"),list) and p["streams"]:doc=p;kind="FFPROBE"
            except (OSError,ValueError,subprocess.TimeoutExpired):pass
    streams=doc.get("streams",[])
    assert isinstance(streams,list) and len(streams)<=128
    aud=[x for x in streams if isinstance(x,dict) and x.get("codec_type")=="audio"]
    vids=[x for x in streams if isinstance(x,dict) and x.get("codec_type")=="video"]
    en=[x for x in aud if str(x.get("tags",{}).get("language","")).lower() in ("en","eng","english")]
    try:dur=float(doc.get("format",{}).get("duration",0))
    except (ValueError,TypeError):dur=0
    if not math.isfinite(dur) or not 0<dur<14400:dur=0
    fps=0
    if vids:
        try:
            from fractions import Fraction
            fps=float(Fraction(vids[0].get("avg_frame_rate","0/1")))
            if not math.isfinite(fps) or not 0<fps<240:fps=0
        except (ValueError,ZeroDivisionError,TypeError):fps=0
    report={"schema":"BT10_HUMAN_FIXTURE_V1","selection_fingerprint":target,"source":"HUMAN_SELECTED_CURRENT_BENCHMARK","exact_file_verified":True,"hash":tor,"file_index":idx,"filename":name,"size_bytes":size,"probe":kind,"duration_seconds":dur,"fps":fps,"audio_tracks":[{"index":x.get("index"),"language":x.get("tags",{}).get("language"),"default":x.get("disposition",{}).get("default")} for x in aud],"english_track_count":len(en),"note":"Private binding only; revalidate before provider. No subtitle lookup, translation or TV operation."}
    (run/"BRAIN_HUMAN_FIXTURE.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
    print(f"BT10H_T1_P{int(kind!='NONE')}_V{len(vids)}_A{len(aud)}_E{len(en)}_D{round(dur)}_F{round(fps*1000)}")
try:main()
except Exception as e:
    (run/"private-error-type.txt").write_text(type(e).__name__+" "+phase,encoding="utf-8")
    print("BT10H_HOLD_"+phase+"_ERROR")
'@
$f=Join-Path $run 'compare.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run 2> (Join-Path $run 'stderr.txt'))
$code='BT10H_HOLD_READOUT_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^BT10H_[A-Z0-9_]{3,83}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
