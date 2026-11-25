# BT19: targeted audio adjudication of retained Teacher/Student differences; no provider calls.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('bt19-targeted-audio-qa-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$py=@'
import sys,pathlib,json,re,hashlib,zipfile,html,collections,difflib,statistics
root,spool=map(pathlib.Path,sys.argv[1:3])
def obj(p):
    assert p.is_file() and not p.is_symlink() and p.stat().st_size<16777216
    return json.loads(p.read_text(encoding="utf-8-sig"))
def srt(dir,report,source):
    assert report["source_commit"]==source
    a=[x for x in report["artifacts"] if x.get("copied_to_job") and x.get("cues",0)>0]
    assert len(a)==1
    a=a[0]; name=a["filename"]; assert pathlib.Path(name).name==name
    p=dir/"browser-downloads"/name
    assert p.is_file() and not p.is_symlink() and 0<p.stat().st_size<2000000
    blob=p.read_bytes();assert hashlib.sha256(blob).hexdigest()==a["sha256"]
    if p.suffix.lower()==".zip":
        with zipfile.ZipFile(p) as z:
            infos=[i for i in z.infolist() if i.filename.lower().endswith(".srt") and 0<i.file_size<2000000 and not i.flag_bits&1]
            assert len(infos)==1
            blob=z.read(infos[0])
    assert len(blob)<2000000
    if blob.startswith((b"\xff\xfe",b"\xfe\xff")):raw=blob.decode("utf-16")
    else:
        try:raw=blob.decode("utf-8-sig")
        except UnicodeDecodeError:raw=blob.decode("cp1252")
    raw=raw.replace("\r\n","\n").replace("\r","\n")
    rx=re.compile(r"(?m)^(\d{2}:\d{2}:\d{2}[,.]\d{3})\s+-->\s+(\d{2}:\d{2}:\d{2}[,.]\d{3})[^\n]*\n")
    def ms(t):
        h,m,s,f=map(int,re.split(r"[:,.]",t));return ((h*60+m)*60+s)*1000+f
    matches=list(rx.finditer(raw)); rows=[]
    for i,m in enumerate(matches):
        text=raw[m.end():matches[i+1].start() if i+1<len(matches) else len(raw)]
        text=re.sub(r"\n\s*\n\s*\d+\s*$","",text).strip()
        norm=" ".join(re.findall(r"\w+",html.unescape(re.sub(r"<[^>]*>|\{\\[^}]*\}","",text)).casefold()))
        start,end=ms(m[1]),ms(m[2]);assert end>=start
        rows.append((start,end,norm))
    assert len(rows)==a["cues"] and len(rows)<5000
    return rows
import os,shutil,subprocess,time,urllib.request,urllib.parse,wave,math
run=pathlib.Path(sys.argv[3])
class Halt(Exception):pass
phase="INIT"
def h(code):raise Halt(code)
def cmd(args,tag,seconds):
    try:
        with (run/(tag+".out")).open("wb") as o,(run/(tag+".err")).open("wb") as e:
            return subprocess.run(args,stdout=o,stderr=e,timeout=seconds,check=False).returncode
    except subprocess.TimeoutExpired:return -99
def digest(p,kind):
    a=hashlib.new(kind)
    with p.open("rb") as f:
        for chunk in iter(lambda:f.read(1048576),b""):a.update(chunk)
    return a.hexdigest()
def fetch(url,path,size,algo,expected,seconds):
    if path.is_file() and path.stat().st_size==size and digest(path,algo)==expected:return
    temp=path.with_suffix(path.suffix+".part")
    end=time.monotonic()+seconds
    with urllib.request.urlopen(url,timeout=20) as f,temp.open("wb") as g:
        total=0
        for block in iter(lambda:f.read(1048576),b""):
            total+=len(block)
            if total>size or time.monotonic()>end:h("DOWNLOAD_BOUND")
            g.write(block)
    if total!=size or digest(temp,algo)!=expected:h("DOWNLOAD_HASH")
    os.replace(temp,path)
def words(x):
    return re.findall(r"\w+",html.unescape(re.sub(r"<[^>]*>|\{\\[^}]*\}","",x)).casefold())
def main():
    global phase
    phase="ARTIFACTS"
    jobs=[("TEACHER",root/"bt11-neon-opensubtitles-d3132c2bbc0c442a8bb1e12950ab1ed2","d4ade6fda6045597267e61f9439bf3635aef2b19"),("STUDENT",root/"bt18-hydrogen-opensubtitles-25e73e80cfce49728e4f6c1402e6cefb","ad010d992cd69cec1dc28185d538392efe8e04fe")]
    def normalized(x):return re.sub(r"[^a-z0-9]","",str(x).casefold())
    target="0c57a7ebb1d8c09b29b6642d48af57701ca4479e6d6d9f63fa8ae3c26a615b5e"
    src={};artifact_hashes={}
    for k,d,source in jobs:
        r=obj(d/"BRAIN_TEACHER_REPORT.json")
        assert hashlib.sha256(normalized(r["video_input"]["release"]).encode()).hexdigest()==target
        assert r["video_input"]["fps"]==24 and abs(r["video_input"]["duration"]-6705)<2
        src[k]=srt(d,r,source)
        artifact_hashes[k]=next(x["sha256"] for x in r["artifacts"] if x.get("copied_to_job") and x.get("cues",0)>0)
    assert [len(src[k]) for k in ("TEACHER","STUDENT")]==[2398,2394]
    def flatten(rows):return [(w,i) for i,x in enumerate(rows) for w in x[2].split()]
    aa=flatten(src["TEACHER"]);bb=flatten(src["STUDENT"])
    assert [len(aa),len(bb)]==[17063,17025]
    changes=[];joined=0
    for tag,i,j,k,l in difflib.SequenceMatcher(None,[x[0] for x in aa],[x[0] for x in bb],autojunk=False).get_opcodes():
        if tag=="equal":continue
        old=[x[0] for x in aa[i:j]];new=[x[0] for x in bb[k:l]]
        if "".join(old)=="".join(new):joined+=1;continue
        assert tag=="delete" and old and not new
        rows=src["TEACHER"]
        changes.append({"start_ms":rows[aa[i][1]][0],"end_ms":rows[aa[j-1][1]][1],"teacher_words":old,"student_words":new})
    assert joined==5 and [len(x["teacher_words"]) for x in changes]==[5,7,4,13,4]
    (run/"BRAIN_BT19_PLAN.json").write_text(json.dumps({"artifact_hashes":artifact_hashes,"joined_only":joined,"changes":changes},indent=2),encoding="utf-8")
    phase="FIXTURE"
    owner=root.parent/"OwnerBridge"
    sys.path.insert(0,str(owner/"app/poc/p2-sub-discovery"))
    from owner_torrserver_readonly import OwnerLocalTorrServer,OwnerTorrServerReader,_local_post
    policy=obj(owner/"p3-p4-policy.json")
    cfg=OwnerLocalTorrServer(policy["profile_id"],policy["torrserver_port"])
    listing=json.loads(_local_post(cfg.url,b'{"action":"list"}',6.0))
    assert isinstance(listing,list) and len(listing)<=256
    target="0c57a7ebb1d8c09b29b6642d48af57701ca4479e6d6d9f63fa8ae3c26a615b5e"
    def matchrelease(x):return hashlib.sha256(re.sub(r"[^a-z0-9]","",str(x).casefold()).encode()).hexdigest()==target
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
            name=str(x.get("path","")).replace("\\","/").rsplit("/",1)[-1]
            idx=x.get("id")
            if type(idx) is not int or not 0<=idx<4096 or not re.search(r"\.(mkv|mp4|avi|m4v|ts|m2ts)$",name,re.I):continue
            if not (matchrelease(pathlib.PurePosixPath(name).stem) or matchrelease(v.get("title",""))):continue
            if type(x.get("length")) is int and x["length"]>100000000:found[(tor,idx)]=name
    if len(found)!=1:h("FIXTURE_AMBIGUOUS")
    (tor,idx),name=next(iter(found.items()))
    actual=OwnerTorrServerReader(cfg)(cfg.profile_id,tor,idx)
    assert actual.path.replace("\\","/").rsplit("/",1)[-1]==name
    url=f"http://127.0.0.1:{cfg.localhost_port}/play/{tor}/{idx}"
    ff=shutil.which("ffmpeg");fp=shutil.which("ffprobe")
    if not ff or not fp:h("FFMPEG_UNAVAILABLE")
    phase="PROBE"
    rc=cmd([fp,"-v","error","-rw_timeout","12000000","-protocol_whitelist","http,tcp","-show_streams","-show_format","-of","json",url],"ffprobe",35)
    if rc!=0:h("MEDIA_PROBE_FAILED")
    meta=obj(run/"ffprobe.out")
    duration=float(meta.get("format",{}).get("duration",0))
    if not math.isfinite(duration) or not 600<duration<14400:h("DURATION_UNKNOWN")
    aud=[x for x in meta.get("streams",[]) if x.get("codec_type")=="audio" and str(x.get("tags",{}).get("language","")).lower() in ("en","eng","english")]
    if not aud:h("NO_TAGGED_EN_AUDIO")
    aud.sort(key=lambda x:(-int(x.get("disposition",{}).get("default",0)),int(x["index"])))
    ai=int(aud[0]["index"])
    phase="BINDING"
    prior=[]
    for f in (spool/"History").glob("receipt-*.json"):
        r=obj(f)
        if r.get("source_commit")=="17b7acb8d5ffbf0dfeb74961bf75d57c9d5cc716" and r.get("result")=="SUCCESS" and re.fullmatch("[a-f0-9]{32}",str(r.get("nonce",""))):prior.append(r["nonce"])
    assert len(prior)==1
    fixture=obj(root/("bt10-human-fixture-preflight-"+prior[0])/"BRAIN_HUMAN_FIXTURE.json")
    assert fixture["schema"]=="BT10_HUMAN_FIXTURE_V1" and fixture["selection_fingerprint"]==target and fixture["exact_file_verified"] is True
    assert fixture["hash"]==tor and fixture["file_index"]==idx and fixture["filename"]==name and fixture["size_bytes"]==actual.length and abs(fixture["duration_seconds"]-duration)<1
    assert any(x["index"]==ai and str(x["language"]).lower() in ("en","eng","english") for x in fixture["audio_tracks"])
    phase="ASR_SETUP"
    tools=root/"BT09ASRPortable"
    archive=tools/"whisper-bin-x64-b5454.zip"
    assert archive.is_file() and archive.stat().st_size==8928640 and digest(archive,"sha256")=="6ba69e3482d7826214f90a6a9c84ca07782aec1e1d0c6a7c30c994fd5d816ccb"
    model=tools/"ggml-large-v3-turbo-q5_0.bin"
    expected="e050f7970618a659205450ad97eb95a18d69c9ee"
    if not (model.is_file() and 0<model.stat().st_size<650000000 and digest(model,"sha1")==expected):h("PINNED_MODEL_UNAVAILABLE")
    bindir=run/"whisper-b5454";bindir.mkdir()
    with zipfile.ZipFile(archive) as z:
        infos=z.infolist()
        assert len(infos)<2000 and sum(v.file_size for v in infos)<150000000
        for v in infos:
            p=pathlib.PurePosixPath(v.filename.replace("\\","/"))
            assert not p.is_absolute() and ".." not in p.parts and ":" not in v.filename
            if v.is_dir():continue
            dest=bindir.joinpath(*p.parts);dest.parent.mkdir(parents=True,exist_ok=True)
            with z.open(v) as f,dest.open("xb") as g:shutil.copyfileobj(f,g)
    cli=list(bindir.rglob("whisper-cli.exe"))
    if len(cli)!=1:h("ASR_CLI_MISSING")
    phase="TARGETED_ASR"
    results=[]
    def save():
        out={"schema":"BT19_TARGETED_ASR_QA_V1","fixture_nonce":prior[0],"artifact_hashes":artifact_hashes,"model_sha1":expected,"runtime_sha256":digest(archive,"sha256"),"joined_only":joined,"target_count":len(changes),"regions":results,"limits":"ASR-only corroboration, exact phrase plus time overlap is evidence, not human ground truth. Missing ASR phrase does not prove absence. No provider calls or model downloads."}
        (run/"BRAIN_BT19_QA.json").write_text(json.dumps(out,indent=2),encoding="utf-8")
    for j,gap in enumerate(changes):
        lo,hi=gap["start_ms"],gap["end_ms"]
        start=max(0,math.floor(lo/1000)-8)
        end=min(math.floor(duration),math.ceil(hi/1000)+8)
        length=end-start
        assert 16<=length<=24
        pcm=run/f"audio-{j}.pcm";audio=run/f"audio-{j}.wav"
        rec={"sample":j,"window_start_seconds":start,"window_seconds":length,"gap":gap,"extraction_ok":False,"asr_ok":False,"classification":"UNRESOLVED"}
        results.append(rec)
        rc=cmd([ff,"-nostdin","-hide_banner","-loglevel","error","-rw_timeout","45000000","-protocol_whitelist","http,tcp","-ss",str(start),"-i",url,"-map",f"0:{ai}","-vn","-sn","-dn","-t",str(length),"-ar","16000","-ac","1","-c:a","pcm_s16le","-f","s16le","-n",str(pcm)],f"extract-{j}",120)
        n=pcm.stat().st_size if pcm.is_file() else 0
        rec["extraction_rc"]=rc;rec["pcm_bytes"]=n
        if rc!=0 or n%2 or not (length-1)*32000<=n<=(length+1)*32000:save();continue
        with wave.open(str(audio),"wb") as w:
            w.setnchannels(1);w.setsampwidth(2);w.setframerate(16000);w.writeframes(pcm.read_bytes())
        rec["extraction_ok"]=True
        dest=run/f"asr-{j}"
        rc=cmd([str(cli[0]),"-m",str(model),"-f",str(audio),"-l","en","-t","8","-oj","-of",str(dest),"-np"],f"asr-process-{j}",140)
        rec["asr_rc"]=rc
        if rc!=0 or not dest.with_suffix(".json").is_file():save();continue
        segs=[]
        for seg in obj(dest.with_suffix(".json")).get("transcription",[]):
            o=seg.get("offsets",{})
            if type(o.get("from")) not in (float,int) or type(o.get("to")) not in (float,int):continue
            a,b=start*1000+round(o["from"]),start*1000+round(o["to"])
            toks=words(seg.get("text",""))
            if a>=start*1000 and a<b<=end*1000+1000 and toks:segs.append((a,b,toks))
        if not segs:save();continue
        rec["asr_ok"]=True;rec["asr_segments"]=segs
        # Entire ordered phrase must occur exactly once and overlap the original cue window.
        observed=[(w,a,b) for a,b,ws in segs for w in ws]
        wanted=gap["teacher_words"]
        exact=[]
        for i in range(len(observed)-len(wanted)+1):
            block=observed[i:i+len(wanted)]
            if [x[0] for x in block]!=wanted:continue
            a,b=block[0][1],block[-1][2]
            if a<=hi+1500 and b>=lo-1500 and b-a<=max(15000,hi-lo+10000):exact.append((a,b))
        nearby=[w for w,a,b in observed if a<=hi+1500 and b>=lo-1500]
        match=sum(x.size for x in difflib.SequenceMatcher(None,wanted,nearby,autojunk=False).get_matching_blocks())
        rec["exact_hits"]=exact;rec["matched_words"]=match;rec["target_words"]=len(wanted)
        rec["classification"]="ASR_CORROBORATED" if len(exact)==1 else "PARTIAL" if match>=max(2,math.ceil(.6*len(wanted))) else "UNRESOLVED"
        save()
    c=collections.Counter(x["classification"] for x in results)
    print(f"BT19_W{len(changes)}_E{sum(x['extraction_ok'] for x in results)}_A{sum(x['asr_ok'] for x in results)}_C{c['ASR_CORROBORATED']}_P{c['PARTIAL']}_U{c['UNRESOLVED']}")

try:main()
except Halt as e:print("BT19_HOLD_"+str(e))
except Exception as e:
    (run/"private-error-type.txt").write_text(type(e).__name__+" "+phase,encoding="utf-8")
    print("BT19_HOLD_"+phase+"_ERROR")
'@
$f=Join-Path $run 'compare.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run 2> (Join-Path $run 'stderr.txt'))
$code='BT19_HOLD_READOUT_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^BT19_[A-Z0-9_]{3,83}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
