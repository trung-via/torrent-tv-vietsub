# BT27: retained Teacher/Student plus bounded audio and embedded EN sample QA on exact verified fixture.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('bt27-odyssey-quality-qa-'+$rq.nonce)
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
    rows=parse_srt(blob)
    assert len(rows)==a["cues"] and len(rows)<5000
    return rows
def parse_srt(blob):
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
    return rows
import os,shutil,subprocess,time,urllib.parse,wave,math
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
def words(x):
    return re.findall(r"\w+",html.unescape(re.sub(r"<[^>]*>|\{\\[^}]*\}","",x)).casefold())
def main():
    global phase
    phase="ARTIFACTS"
    jobs=[("T",root/"bt25-neon-opensubtitles-5572fba3e6544320a2c9f74492213971","dd108b58a1e6477bc7854a69b8c74dd72b05b476"),("H",root/"bt26-hydrogen-opensubtitles-c3f0255dc29b45fda98e9f3d718b2311","f42af2a2494681d9c867d91c9db179e466af294c")]
    def normalized(x):return re.sub(r"[^a-z0-9]","",str(x).casefold())
    target="7f9ecde8125748e03a53989a4b2651bf5290849339dfd1fdf9b5d3fbe8914038"
    src={};artifact_hashes={};reports={}
    for k,d,source in jobs:
        r=obj(d/"BRAIN_TEACHER_REPORT.json")
        assert r["provider"]=="OpenSubtitles" and hashlib.sha256(normalized(r["video_input"]["release"]).encode()).hexdigest()==target
        assert abs(r["video_input"]["fps"]-29.994)<.01 and abs(r["video_input"]["duration"]-10356)<2
        if k=="H":assert r["filter_gate"]["accepted"] is True and r["filter_gate"]["download_verified"] is True
        src[k]=srt(d,r,source);reports[k]=r
        artifact_hashes[k]=next(x["sha256"] for x in r["artifacts"] if x.get("copied_to_job") and x.get("cues",0)>0)
    assert [len(src[k]) for k in ("T","H")]==[1909,1909]
    eq=src["T"]==src["H"]
    text_equal=[x[2] for x in src["T"]]==[x[2] for x in src["H"]]
    token_equal=" ".join(x[2] for x in src["T"])==" ".join(x[2] for x in src["H"])
    (run/"BRAIN_BT27_ARTIFACT_QA.json").write_text(json.dumps({"normalized_cue_tuples_equal":eq,"cue_text_equal":text_equal,"token_stream_equal":token_equal,"artifact_hashes":artifact_hashes},indent=2),encoding="utf-8")
    phase="FIXTURE"
    owner=root.parent/"OwnerBridge"
    sys.path.insert(0,str(owner/"app/poc/p2-sub-discovery"))
    from owner_torrserver_readonly import OwnerLocalTorrServer,OwnerTorrServerReader,_local_post
    policy=obj(owner/"p3-p4-policy.json")
    cfg=OwnerLocalTorrServer(policy["profile_id"],policy["torrserver_port"])
    listing=json.loads(_local_post(cfg.url,b'{"action":"list"}',6.0))
    assert isinstance(listing,list) and len(listing)<=256
    target="7f9ecde8125748e03a53989a4b2651bf5290849339dfd1fdf9b5d3fbe8914038"
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
        if r.get("source_commit")=="29c8dac83ed663b137a39c666d242258cd93c848" and r.get("result")=="SUCCESS" and re.fullmatch("[a-f0-9]{32}",str(r.get("nonce",""))):prior.append(r["nonce"])
    assert len(prior)==1
    fixture=obj(root/("bt24-human-fixture-preflight-"+prior[0])/"BRAIN_HUMAN_FIXTURE.json")
    assert fixture["schema"]=="BT10_HUMAN_FIXTURE_V1" and fixture["selection_fingerprint"]==target and fixture["exact_file_verified"] is True
    assert fixture["hash"]==tor and fixture["file_index"]==idx and fixture["filename"]==name and fixture["size_bytes"]==actual.length and abs(fixture["duration_seconds"]-duration)<1
    assert any(x["index"]==ai and str(x["language"]).lower() in ("en","eng","english") for x in fixture["audio_tracks"])
    subs=[x for x in meta["streams"] if x.get("codec_type")=="subtitle" and str(x.get("tags",{}).get("language","")).lower() in ("en","eng","english")]
    assert len(subs)==1 and fixture["english_subtitle_count"]==1
    si=int(subs[0]["index"]);codec=subs[0].get("codec_name","")
    assert any(x["index"]==si and x["codec"]==codec for x in fixture["subtitle_tracks"])
    text_codec=codec in ("subrip","ass","ssa","webvtt","mov_text","text")
    assert all(abs(reports[k]["video_input"]["duration"]-duration)<1 and reports[k]["video_input"]["size_bytes"]==actual.length for k in src)
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
    phase="SAMPLES"
    regions=[];scores={k:[] for k in ("T","H","E")};anchors={k:[] for k in ("T","H","E")};embedded_scores={k:[] for k in src};embedded_anchors={k:[] for k in src}
    def metric(vals):
        if not vals:return None
        ab=sorted(abs(x) for x in vals)
        return {"count":len(vals),"median_signed_ms":round(statistics.median(vals)),"median_abs_ms":round(statistics.median(ab)),"p95_abs_ms":ab[math.ceil(.95*len(ab))-1]}
    def timeline(aa):
        result={}
        for k,v in aa.items():
            groups={j:metric([x["onset"] for x in v if x["sample"]==j]) for j in set(x["sample"] for x in v)}
            med=[x["median_signed_ms"] for x in groups.values()]
            result[k]={"onset":metric([x["onset"] for x in v]),"offset":metric([x["offset"] for x in v]),"sample_median_range_ms":max(med)-min(med) if len(med)>1 else None,"regions":groups}
        return result
    def aggregate(ss,k):
        r=ss[k];total=sum(x["ref_words"] for x in r)
        return round(1000*sum(x["matched"] for x in r)/total) if total else None
    def compare(ref,rows,j):
        aw=[w for a,b,t in ref for w in t]
        if not aw:return None,[]
        lo,hi=ref[0][0],ref[-1][1]
        sw=[w for a,b,t in rows if lo-500<(a+b)/2<hi+500 for w in t.split()]
        m=sum(x.size for x in difflib.SequenceMatcher(None,aw,sw,autojunk=False).get_matching_blocks())
        aa=[]
        for a,b,t in ref:
            if len(t)<4:continue
            near=[x for x in rows if x[1]>=a-5000 and x[0]<=b+5000]
            hits=[]
            for u in range(len(near)):
                seq=[]
                for v in range(u,min(u+5,len(near))):
                    seq.extend(near[v][2].split())
                    if len(seq)>len(t) or seq!=t[:len(seq)]:break
                    if seq==t:hits.append((near[u][0]-a,near[v][1]-b));break
            if len(hits)==1:aa.append({"sample":j,"onset":hits[0][0],"offset":hits[0][1]})
        return {"sample":j,"ref_words":len(aw),"srt_words":len(sw),"matched":m,"coverage_permille":round(1000*m/len(aw)),"agreement_permille":round(1000*m/max(1,len(sw)))},aa
    def save():
        report={"schema":"BT27_ODYSSEY_QUALITY_QA_V1","fixture_nonce":prior[0],"duration_seconds":duration,"audio_index":ai,"embedded_index":si,"embedded_codec":codec,"artifact_hashes":artifact_hashes,"normalized_cue_tuples_equal":eq,"cue_text_equal":text_equal,"token_stream_equal":token_equal,"regions":regions,"asr_scores":scores,"asr_coverage_permille":{k:aggregate(scores,k) for k in scores},"asr_timeline":timeline(anchors),"embedded_reference_scores":embedded_scores,"embedded_reference_coverage_permille":{k:aggregate(embedded_scores,k) for k in embedded_scores},"embedded_reference_timeline":timeline(embedded_anchors),"model_sha1":expected,"runtime_sha256":digest(archive,"sha256"),"limitations":"Five bounded 36-second regions, not full-film ground truth. Embedded subtitle extraction uses seek-relative timestamps, validated against window and independent ASR; embedded track may itself contain errors. ASR phrase anchors are estimates, unscored samples are missing evidence."}
        (run/"BRAIN_BT27_QA.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
    for j,pct in enumerate((.10,.30,.50,.70,.90)):
        start=max(0,round(duration*pct-18));length=36
        pcm=run/f"audio-{j}.pcm";audio=run/f"audio-{j}.wav";sub=run/f"embedded-{j}.srt"
        rec={"sample":j,"start":start,"length":length,"audio_ok":False,"embedded_ok":False,"asr_scored":False}
        regions.append(rec)
        rc=cmd([ff,"-nostdin","-hide_banner","-loglevel","error","-rw_timeout","45000000","-protocol_whitelist","http,tcp","-ss",str(start),"-i",url,"-map",f"0:{ai}","-vn","-sn","-dn","-t",str(length),"-ar","16000","-ac","1","-c:a","pcm_s16le","-f","s16le","-n",str(pcm)],f"extract-{j}",60)
        n=pcm.stat().st_size if pcm.is_file() else 0
        rec["audio_rc"]=rc;rec["pcm_bytes"]=n
        rec["audio_ok"]=rc==0 and n%2==0 and 35*32000<=n<=37*32000
        em=[]
        if text_codec:
            rc=cmd([ff,"-nostdin","-hide_banner","-loglevel","error","-rw_timeout","45000000","-protocol_whitelist","http,tcp","-ss",str(start),"-i",url,"-map",f"0:{si}","-vn","-an","-dn","-t",str(length),"-c:s","srt","-n",str(sub)],f"embedded-extract-{j}",60)
            rec["embedded_rc"]=rc
            if rc==0 and sub.is_file():
                local=parse_srt(sub.read_bytes())
                # Reject unexpected non-window-relative timestamps; omit cut-edge cues.
                if local and all(0<=a<=b<=38000 for a,b,t in local):
                    rec["embedded_ok"]=True
                    em=[(start*1000+a,start*1000+b,t) for a,b,t in local if 1000<=a<b<=35000 and t]
                    rec["embedded_cues"]=len(em)
        else:rec["embedded_rc"]="NON_TEXT_CODEC"
        eref=[(a,b,t.split()) for a,b,t in em]
        if sum(len(x[2]) for x in eref)>=12:
            for k,rows in src.items():
                rr,aa=compare(eref,rows,j);embedded_scores[k].append(rr);embedded_anchors[k].extend(aa)
        if rec["audio_ok"]:
            with wave.open(str(audio),"wb") as w:
                w.setnchannels(1);w.setsampwidth(2);w.setframerate(16000);w.writeframes(pcm.read_bytes())
            dest=run/f"asr-{j}"
            rc=cmd([str(cli[0]),"-m",str(model),"-f",str(audio),"-l","en","-t","8","-oj","-of",str(dest),"-np"],f"asr-process-{j}",110)
            rec["asr_rc"]=rc
            if rc==0 and dest.with_suffix(".json").is_file():
                segs=[]
                for seg in obj(dest.with_suffix(".json")).get("transcription",[]):
                    o=seg.get("offsets",{})
                    if type(o.get("from")) not in (float,int) or type(o.get("to")) not in (float,int):continue
                    a,b=round(o["from"]),round(o["to"]);t=words(seg.get("text",""))
                    if 1000<=a<b<=35000 and t:segs.append((start*1000+a,start*1000+b,t))
                if sum(len(x[2]) for x in segs)>=12:
                    rec["asr_scored"]=True
                    for k,rows in src.items():
                        rr,aa=compare(segs,rows,j);scores[k].append(rr);anchors[k].extend(aa)
                    if em:
                        # Compare ASR only where the embedded sample has non-edge coverage.
                        ref=[x for x in segs if em[0][0]<=x[0] and x[1]<=em[-1][1]]
                        if sum(len(x[2]) for x in ref)>=12:
                            rr,aa=compare(ref,em,j);scores["E"].append(rr);anchors["E"].extend(aa)
        save()
    def val(x):return str(x) if x is not None else "X"
    m=timeline(anchors)["H"]["onset"]
    print(f"BT27_I{int(eq)}{int(text_equal)}{int(token_equal)}S{len(regions)}A{sum(x['audio_ok'] for x in regions)}V{len(scores['H'])}E{sum(x['embedded_ok'] for x in regions)}Q{val(aggregate(scores,'H'))}T{val(aggregate(scores,'T'))}R{val(aggregate(embedded_scores,'H'))}K{m['count'] if m else 0}M{m['median_abs_ms'] if m else 'X'}P{m['p95_abs_ms'] if m else 'X'}")

try:main()
except Halt as e:print("BT27_HOLD_"+str(e))
except Exception as e:
    (run/"private-error-type.txt").write_text(type(e).__name__+" "+phase,encoding="utf-8")
    print("BT27_HOLD_"+phase+"_ERROR")
'@
$f=Join-Path $run 'compare.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run 2> (Join-Path $run 'stderr.txt'))
$code='BT27_HOLD_READOUT_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^BT27_[A-Z0-9_]{3,83}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
