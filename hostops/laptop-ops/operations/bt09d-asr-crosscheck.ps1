# BT09D: second local ASR on retained audio; verified model download only; no new film or subtitle downloads.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('bt09d-asr-crosscheck-'+$rq.nonce)
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
import math
run=pathlib.Path(sys.argv[3])
phase="INIT"
def prior(source,prefix):
    found=[]
    for f in (spool/"History").glob("receipt-*.json"):
        r=obj(f)
        if r.get("source_commit")==source and r.get("result")=="SUCCESS" and re.fullmatch("[a-f0-9]{32}",str(r.get("nonce",""))):
            found.append(r["nonce"])
    assert len(found)==1
    return root/(prefix+found[0]),found[0]
def words(x):
    return re.findall(r"\w+",html.unescape(re.sub(r"<[^>]*>|\{\\[^}]*\}","",x)).casefold())
def matched(aw,sw):
    return {m.a+i for m in difflib.SequenceMatcher(None,aw,sw,autojunk=False).get_matching_blocks() for i in range(m.size)}
def anchor(seg,rows):
    lo,hi,toks=seg
    if len(toks)<4:return None
    cand=[x for x in rows if x[1]>=lo-5000 and x[0]<=hi+5000 and x[2]]
    hits=[]
    for i in range(len(cand)):
        seq=[]
        for j in range(i,min(i+5,len(cand))):
            seq.extend(cand[j][2].split())
            if len(seq)>len(toks) or seq!=toks[:len(seq)]:break
            if seq==toks:
                hits.append((cand[i][0]-lo,cand[j][1]-hi))
                break
    return hits[0] if len(hits)==1 else None
def metric(values):
    if not values:return None
    absolute=sorted(abs(x) for x in values)
    return {"count":len(values),"median_signed_ms":round(statistics.median(values)),"median_abs_ms":round(statistics.median(absolute)),"p95_abs_ms":absolute[math.ceil(.95*len(absolute))-1]}
import os,subprocess,urllib.request,time,shutil,wave
def digest(p,kind):
    h=hashlib.new(kind)
    with p.open("rb") as f:
        for block in iter(lambda:f.read(1048576),b""):h.update(block)
    return h.hexdigest()
def segments(data,start):
    out=[]
    for seg in data.get("transcription",[]):
        o=seg.get("offsets",{})
        if not isinstance(o.get("from"),(float,int)) or not isinstance(o.get("to"),(float,int)):continue
        lo,hi=round(o["from"]),round(o["to"])
        if lo<1000 or hi>35000 or hi<=lo:continue
        toks=words(seg.get("text",""))
        if toks:out.append((start+lo,start+hi,toks))
    return out
def select(rows,lo,hi):
    return [w for x in rows if lo-500<(x[0]+x[1])/2<hi+500 for w in x[2].split()]
def main():
    global phase
    phase="ARTIFACTS"
    ts="4cd3124ac8c7102028ff0b1f079a5b3b522b15c9"
    teacher,_=prior(ts,"bt04-neon-subtitlecat-")
    jobs=[("NC",teacher,ts),("HC",root/"bt07-hydrogen-subtitlecat-1e4e7ae677d74a01a1367273e1b1d225","ca4ccfb812bd05196b0e59c349c7b46b138789bd"),("NO",root/"bt05-neon-opensubtitles-0d2ff69cc151464fabe61e6f38fea339","01ab690a99839b006e3763fb7e1b9e7d36f47da8"),("HO",root/"bt08-hydrogen-opensubtitles-10920e6901704d2abb080cd8f808e66d","51a421398d6f3afe4ba350bb0509f28e2834c4b9")]
    src={k:srt(d,obj(d/"BRAIN_TEACHER_REPORT.json"),ref) for k,d,ref in jobs}
    assert [len(x) for x in src.values()]==[1018,919,1018,1018] and src["NO"]==src["HO"]
    old,on=prior("bde31e100e13f9a238415e2a6addb3a512a651c0","bt09-movie-audio-qa-")
    new,nn=prior("205a37fe39a3dc7e1b9da367da472ed29f8f8a77","bt09b-movie-audio-qa-")
    readout,_=prior("86f980548706a4102eca116e48a6b9c5fec1c095","bt09c-timeline-readout-")
    qa=obj(readout/"BRAIN_TIMELINE_QA.json");report=obj(new/"BRAIN_AUDIO_QA.json")
    assert qa["original_nonce"]==on and qa["resume_nonce"]==nn and qa["all_unmatched_words"]==16 and qa["candidate_dependent_words"]==1
    duration=float(report["duration_seconds"])
    assert math.isfinite(duration) and 600<duration<14400
    samples=set(qa["speech_regions"])
    assert len(samples)==4 and 2 in samples
    phase="ASR_SETUP"
    tools=root/"BT09ASRPortable"
    archive=tools/"whisper-bin-x64-b5454.zip"
    assert archive.stat().st_size==8928640 and digest(archive,"sha256")=="6ba69e3482d7826214f90a6a9c84ca07782aec1e1d0c6a7c30c994fd5d816ccb"
    bindir=run/"whisper-b5454";bindir.mkdir()
    with zipfile.ZipFile(archive) as z:
        infos=z.infolist()
        assert len(infos)<2000 and sum(x.file_size for x in infos)<150000000
        for v in infos:
            p=pathlib.PurePosixPath(v.filename.replace("\\","/"))
            assert not p.is_absolute() and ".." not in p.parts and ":" not in v.filename
            if v.is_dir():continue
            dest=bindir.joinpath(*p.parts);dest.parent.mkdir(parents=True,exist_ok=True)
            with z.open(v) as f,dest.open("xb") as g:shutil.copyfileobj(f,g)
    cli=list(bindir.rglob("whisper-cli.exe"));assert len(cli)==1
    model=tools/"ggml-large-v3-turbo-q5_0.bin"
    expected="e050f7970618a659205450ad97eb95a18d69c9ee"
    phase="MODEL_DOWNLOAD"
    if not (model.is_file() and 0<model.stat().st_size<650000000 and digest(model,"sha1")==expected):
        temp=model.with_suffix(".bin.part")
        end=time.monotonic()+420
        with urllib.request.urlopen("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin",timeout=30) as f,temp.open("wb") as g:
            total=0
            for block in iter(lambda:f.read(1048576),b""):
                total+=len(block)
                if total>650000000 or time.monotonic()>end:raise ValueError("download bound")
                g.write(block)
        assert digest(temp,"sha1")==expected
        os.replace(temp,model)
    phase="SECOND_ASR"
    results=[];counts={k:{"turbo":0,"consensus":0,"onsets":[]} for k in src}
    tw=0;cw=0;unresolved=0;covered=0
    for j in range(5):
        d=old if j==2 else new
        audio=d/f"audio-{j}.wav"
        with wave.open(str(audio),"rb") as w:
            assert w.getframerate()==16000 and w.getnchannels()==1 and w.getsampwidth()==2
            frames=w.readframes(w.getnframes())
            assert 34*32000<=len(frames)<=37*32000
        dest=run/f"asr-{j}"
        try:
            with (run/f"asr-{j}.out").open("wb") as o,(run/f"asr-{j}.err").open("wb") as e:
                rc=subprocess.run([str(cli[0]),"-m",str(model),"-f",str(audio),"-l","en","-t","8","-oj","-of",str(dest),"-np"],stdout=o,stderr=e,timeout=140,check=False).returncode
        except subprocess.TimeoutExpired:rc=-99
        row={"sample":j,"rc":rc,"previous_scored":j in samples}
        if rc!=0 or not dest.with_suffix(".json").is_file():
            results.append(row);continue
        start=max(0,round(duration*(.10,.30,.50,.70,.90)[j]-18))*1000
        turbo=segments(obj(dest.with_suffix(".json")),start)
        tt=[w for x in turbo for w in x[2]]
        row["turbo_words"]=len(tt)
        if len(tt)<12:
            results.append(row);continue
        # Full turbo score and exact transcript agreement are separate; no substitution for independent human reference.
        oldsegs=segments(obj(d/f"asr-{j}.json"),start) if (d/f"asr-{j}.json").is_file() else []
        aa=[w for x in oldsegs for w in x[2]]
        if j in samples:
            base_lo,base_hi=oldsegs[0][0],oldsegs[-1][1]
            # Pair each ASR's transcript against the same widened region; count baseline unmatched words that persist in both ASRs.
            blocks=difflib.SequenceMatcher(None,aa,tt,autojunk=False).get_matching_blocks()
            aligned=[(m.a+i,m.b+i) for m in blocks for i in range(m.size)]
            agree=[tt[b] for a,b in aligned]
            oldsets=[matched(aa,select(rows,base_lo,base_hi)) for rows in src.values()]
            oldabs=set(range(len(aa)))-set.union(*oldsets)
            assert len(oldabs)==next(x["all_unmatched"] for x in qa["mismatch_by_region"] if x["sample"]==j)
            still=sum(a in oldabs for a,b in aligned)
            row.update({"baseline_words":len(aa),"baseline_all_unmatched":len(oldabs),"unmatched_repeated_by_turbo":still,"consensus_words":len(agree)})
        else:
            agree=[];still=0
            row["consensus_words"]=0
        row["providers"]={}
        for k,rows in src.items():
            sw=select(rows,turbo[0][0],turbo[-1][1])
            m=len(matched(tt,sw))
            cm=len(matched(agree,sw)) if agree else 0
            anchors=[v[0] for seg in turbo if (v:=anchor(seg,rows)) is not None]
            row["providers"][k]={"turbo_matched":m,"consensus_matched":cm,"onset":metric(anchors)}
            counts[k]["turbo"]+=m;counts[k]["consensus"]+=cm;counts[k]["onsets"].extend(anchors)
        tw+=len(tt);cw+=len(agree);unresolved+=still;covered+=1
        results.append(row)
        (run/"BRAIN_ASR_CROSSCHECK_PARTIAL.json").write_text(json.dumps(results,indent=2),encoding="utf-8")
    phase="SUMMARY"
    assert tw>0 and cw>0
    summary={k:{"turbo_permille":round(1000*x["turbo"]/tw),"consensus_permille":round(1000*x["consensus"]/cw),"onset":metric(x["onsets"])} for k,x in counts.items()}
    out={"schema":"BT09D_ASR_CROSSCHECK_V1","model":"large-v3-turbo-q5_0","model_sha1":expected,"baseline_nonce":on,"resume_nonce":nn,"scored_regions":covered,"turbo_words":tw,"consensus_words":cw,"baseline_unmatched_repeated_by_turbo":unresolved,"providers":summary,"regions":results,"limitations":"Two related Whisper models; consensus may share ASR error. Lexical overlap, not human verified coverage. Exact phrase anchors are approximate. No new film or subtitle downloads."}
    (run/"BRAIN_ASR_CROSSCHECK.json").write_text(json.dumps(out,indent=2),encoding="utf-8")
    print(f"BT09D_V{covered}_T{tw}_C{cw}_U{unresolved}_NC{summary['NC']['turbo_permille']}_HC{summary['HC']['turbo_permille']}_NO{summary['NO']['turbo_permille']}_HO{summary['HO']['turbo_permille']}_K{summary['HO']['consensus_permille']}")
try:main()
except Exception as e:
    (run/"private-error-type.txt").write_text(type(e).__name__+" "+phase,encoding="utf-8")
    print("BT09D_HOLD_"+phase+"_ERROR")
'@
$f=Join-Path $run 'compare.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run 2> (Join-Path $run 'stderr.txt'))
$code='BT09D_HOLD_READOUT_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^BT09D_[A-Z0-9_]{3,83}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
