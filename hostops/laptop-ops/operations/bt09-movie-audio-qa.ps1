# BT09A: independent local audio ASR benchmark; no production changes.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('bt09b-movie-audio-qa-'+$rq.nonce)
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
    ts="4cd3124ac8c7102028ff0b1f079a5b3b522b15c9"
    prior=[]
    for f in (spool/"History").glob("receipt-*.json"):
        q=obj(f)
        if q.get("source_commit")==ts and q.get("result")=="SUCCESS" and re.fullmatch("[a-f0-9]{32}",str(q.get("nonce",""))):prior.append(q["nonce"])
    assert len(prior)==1
    jobs=[("N_CAT",root/("bt04-neon-subtitlecat-"+prior[0]),ts),("H_CAT",root/"bt07-hydrogen-subtitlecat-1e4e7ae677d74a01a1367273e1b1d225","ca4ccfb812bd05196b0e59c349c7b46b138789bd"),("N_OS",root/"bt05-neon-opensubtitles-0d2ff69cc151464fabe61e6f38fea339","01ab690a99839b006e3763fb7e1b9e7d36f47da8"),("H_OS",root/"bt08-hydrogen-opensubtitles-10920e6901704d2abb080cd8f808e66d","51a421398d6f3afe4ba350bb0509f28e2834c4b9")]
    src={label:srt(d,obj(d/"BRAIN_TEACHER_REPORT.json"),source) for label,d,source in jobs}
    assert [len(x) for x in src.values()]==[1018,919,1018,1018]
    phase="FIXTURE"
    owner=root.parent/"OwnerBridge"
    sys.path.insert(0,str(owner/"app/poc/p2-sub-discovery"))
    from owner_torrserver_readonly import OwnerLocalTorrServer,OwnerTorrServerReader,_local_post
    policy=obj(owner/"p3-p4-policy.json")
    cfg=OwnerLocalTorrServer(policy["profile_id"],policy["torrserver_port"])
    listing=json.loads(_local_post(cfg.url,b'{"action":"list"}',6.0))
    assert isinstance(listing,list) and len(listing)<=256
    target="8af4f744c246ab341688e00eb919df53fe7c48c540910d66659b6c659ae11b89"
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
    phase="RESUME"
    source="bde31e100e13f9a238415e2a6addb3a512a651c0"
    prior=[]
    for f in (spool/"History").glob("receipt-*.json"):
        r=obj(f)
        if r.get("source_commit")==source and r.get("result")=="SUCCESS" and re.fullmatch("[a-f0-9]{32}",str(r.get("nonce",""))):prior.append(r["nonce"])
    assert len(prior)==1
    previous=root/("bt09-movie-audio-qa-"+prior[0])
    prev=obj(previous/"BRAIN_AUDIO_QA.json")
    assert prev["schema"]=="BT09_AUDIO_QA_V1" and prev["speech_sample_count"]==1 and prev["sample_count"]==1
    assert abs(float(prev["duration_seconds"])-duration)<.01 and prev["audio_index"]==ai
    assert all(len(prev["scores"][k])==1 and prev["scores"][k][0]["sample"]==2 for k in src)
    phase="SAMPLE"
    samples=[]
    extraction=[]
    for j,pct in enumerate((.10,.30,.50,.70,.90)):
        start=max(0,round(duration*pct-18))
        if j==2:continue
        pcm=run/f"audio-{j}.pcm"
        out=run/f"audio-{j}.wav"
        began=time.monotonic()
        # Raw PCM cannot carry the unfinished RIFF header seen after a killed FFmpeg.
        rc=cmd([ff,"-nostdin","-hide_banner","-loglevel","error","-rw_timeout","45000000","-protocol_whitelist","http,tcp","-ss",str(start),"-i",url,"-map",f"0:{ai}","-vn","-sn","-dn","-t","36","-ar","16000","-ac","1","-c:a","pcm_s16le","-f","s16le","-n",str(pcm)],f"extract-{j}",120)
        n=pcm.stat().st_size if pcm.is_file() else 0
        err=(run/f"extract-{j}.err").read_text(encoding="utf-8",errors="replace")[:200000].lower()
        kind="OK" if rc==0 and 34*32000<=n<=37*32000 and n%2==0 else "TIMEOUT" if rc==-99 or re.search(r"timed? ?out|timeout|10060",err) else "SEEK" if re.search(r"seek|range|partial file",err) else "MEDIA" if re.search(r"invalid data|ebml|matroska",err) else "IO" if re.search(r"http error|server returned|connection|input/output error|i/o error",err) else "SHORT" if rc==0 else "OTHER"
        extraction.append({"sample":j,"rc":rc,"pcm_bytes":n,"seconds":round(n/32000,3),"wall_seconds":round(time.monotonic()-began,3),"classification":kind})
        (run/"BRAIN_EXTRACTION_QA.json").write_text(json.dumps(extraction,indent=2),encoding="utf-8")
        if kind!="OK":continue
        with wave.open(str(out),"wb") as w:
            w.setnchannels(1);w.setsampwidth(2);w.setframerate(16000);w.writeframes(pcm.read_bytes())
        samples.append((j,start,out))
    phase="ASR_SETUP"
    tools=root/"BT09ASRPortable"
    tools.mkdir(exist_ok=True)
    archive=tools/"whisper-bin-x64-b5454.zip"
    fetch("https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-bin-x64.zip",archive,8928640,"sha256","6ba69e3482d7826214f90a6a9c84ca07782aec1e1d0c6a7c30c994fd5d816ccb",90)
    bindir=run/"whisper-b5454"
    bindir.mkdir()
    with zipfile.ZipFile(archive) as z:
        infos=z.infolist()
        assert len(infos)<2000 and sum(v.file_size for v in infos)<150000000
        for v in infos:
            p=pathlib.PurePosixPath(v.filename.replace("\\","/"))
            assert not p.is_absolute() and ".." not in p.parts and ":" not in v.filename
            if v.is_dir():continue
            dest=bindir.joinpath(*p.parts)
            dest.parent.mkdir(parents=True,exist_ok=True)
            with z.open(v) as f,dest.open("xb") as g:shutil.copyfileobj(f,g)
    cli=list(bindir.rglob("whisper-cli.exe"))
    if len(cli)!=1:h("ASR_CLI_MISSING")
    model=tools/"ggml-small.en.bin"
    # Upstream lists SHA-1; size is checked against the pinned upstream blob.
    expected="db8a495a91d927739e50b3fc1cc4c6b8f6c2d022"
    if not (model.is_file() and digest(model,"sha1")==expected):
        temp=model.with_suffix(".bin.part")
        end=time.monotonic()+300
        with urllib.request.urlopen("https://huggingface.co/ggerganov/whisper.cpp/resolve/fb5ed9369c26eaf08392504d8446da431e0fffb9/ggml-small.en.bin",timeout=30) as f,temp.open("wb") as g:
            total=0
            for block in iter(lambda:f.read(1048576),b""):
                total+=len(block)
                if total>500000000 or time.monotonic()>end:h("MODEL_DOWNLOAD_BOUND")
                g.write(block)
        if digest(temp,"sha1")!=expected:h("MODEL_HASH")
        os.replace(temp,model)
    phase="ASR"
    scores={k:list(prev["scores"][k]) for k in src}; successful=1
    for j,start,audio in samples:
        dest=run/f"asr-{j}"
        rc=cmd([str(cli[0]),"-m",str(model),"-f",str(audio),"-l","en","-t","6","-oj","-of",str(dest),"-np"],f"asr-process-{j}",75)
        if rc!=0 or not dest.with_suffix(".json").is_file():continue
        data=obj(dest.with_suffix(".json"))
        segs=[]
        for seg in data.get("transcription",[]):
            o=seg.get("offsets",{})
            if not isinstance(o.get("from"),(float,int)) or not isinstance(o.get("to"),(float,int)):continue
            lo,hi=round(o["from"]),round(o["to"])
            if lo<1000 or hi>35000:continue
            toks=words(seg.get("text",""))
            if toks:segs.append((start*1000+lo,start*1000+hi,toks))
        if sum(len(v[2]) for v in segs)<12:continue
        successful+=1
        for k,rows in src.items():
            # Compare text in the same audio interval; segment-midpoint timing is an estimate, not word alignment.
            aw=[w for x in segs for w in x[2]]
            lo,hi=segs[0][0],segs[-1][1]
            subset=[x for x in rows if lo-500<((x[0]+x[1])/2)<hi+500]
            sw=[w for x in subset for w in x[2].split()]
            match=sum(x.size for x in difflib.SequenceMatcher(None,aw,sw,autojunk=False).get_matching_blocks())
            scores[k].append({"sample":j,"asr_words":len(aw),"srt_words":len(sw),"matched":match,"asr_coverage":round(1000*match/len(aw)),"srt_agreement":round(1000*match/max(1,len(sw)))})
    summary={"schema":"BT09_AUDIO_QA_V1","duration_seconds":duration,"audio_index":ai,"sample_count":len(samples)+1,"speech_sample_count":successful,"resumed_original_nonce":prior[0],"extraction":extraction,"scores":scores,"method":"ASR lexical agreement, not word-level timing or certified ground truth","model_sha1":expected,"runtime_sha256":digest(archive,"sha256")}
    (run/"BRAIN_AUDIO_QA.json").write_text(json.dumps(summary,indent=2),encoding="utf-8")
    if not successful:h("NO_SPEECH_SAMPLE")
    def agg(k):
        x=scores[k]
        return round(1000*sum(y["matched"] for y in x)/sum(y["asr_words"] for y in x))
    print(f"BT09B_S{len(samples)+1}_V{successful}_NC{agg('N_CAT')}_HC{agg('H_CAT')}_NO{agg('N_OS')}_HO{agg('H_OS')}_"+ "".join({"OK":"O","TIMEOUT":"T","SEEK":"S","MEDIA":"M","IO":"I","SHORT":"H","OTHER":"X"}[x["classification"]] for x in extraction))
try:main()
except Halt as e:print("BT09B_HOLD_"+str(e))
except Exception as e:
    (run/"private-error-type.txt").write_text(type(e).__name__+" "+phase,encoding="utf-8")
    print("BT09B_HOLD_"+phase+"_ERROR")
'@
$f=Join-Path $run 'compare.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run 2> (Join-Path $run 'stderr.txt'))
$code='BT09B_HOLD_READOUT_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^BT09B_[A-Z0-9_]{3,83}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
