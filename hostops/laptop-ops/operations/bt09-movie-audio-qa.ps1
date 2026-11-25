# BT30: shared-window adjudication, private listening review and arrival latency readout.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('bt30-adjudication-qa-'+$rq.nonce)
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
import wave,math
run=pathlib.Path(sys.argv[3])
class Halt(Exception):pass
phase="INIT"
def h(code):raise Halt(code)
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
    phase="RETAINED"
    def prior(source,prefix):
        found=[]
        for f in (spool/"History").glob("receipt-*.json"):
            r=obj(f)
            if r.get("source_commit")==source and r.get("result")=="SUCCESS" and re.fullmatch("[a-f0-9]{32}",str(r.get("nonce",""))):found.append(r["nonce"])
        assert len(found)==1
        return root/(prefix+found[0]),found[0]
    d27,n27=prior("811dca676313adf55af7780a54626459d52b89b7","bt27-odyssey-quality-qa-")
    d28,n28=prior("33a3a0d7bcc187260dc7cd6bf0f9eebc64788b92","bt28-odyssey-recovery-qa-")
    q27=obj(d27/"BRAIN_BT27_QA.json");q28=obj(d28/"BRAIN_BT28_QA.json")
    assert q27["schema"]=="BT27_ODYSSEY_QUALITY_QA_V1" and q28["schema"]=="BT28_ODYSSEY_RECOVERY_QA_V1"
    assert q27["artifact_hashes"]==q28["artifact_hashes"]==artifact_hashes and q27["fixture_nonce"]==q28["fixture_nonce"]
    fixture=obj(root/("bt24-human-fixture-preflight-"+q28["fixture_nonce"])/"BRAIN_HUMAN_FIXTURE.json")
    assert fixture["selection_fingerprint"]==target and fixture["exact_file_verified"] is True
    assert q27["model_sha1"]==q28["model_sha1"]=="e050f7970618a659205450ad97eb95a18d69c9ee"
    assert len(q28["asr_scores"]["H"])==4 and q28["asr_coverage_permille"]["H"]==955
    assert text_equal and token_equal
    samples=[]
    for directory,records in ((d27,q27["regions"]),(d28,q28["recovery_regions"])):
        for rec in records:
            j=rec["sample"]
            if rec.get("asr_scored") is not True:continue
            audio=directory/f"audio-{j}.wav";asr=directory/f"asr-{j}.json"
            assert audio.is_file() and not audio.is_symlink() and asr.is_file()
            with wave.open(str(audio),"rb") as w:
                assert w.getnchannels()==1 and w.getsampwidth()==2 and w.getframerate()==16000 and 35*16000<=w.getnframes()<=37*16000
            samples.append((j,rec["start"],audio,asr))
    assert len(samples)==len({x[0] for x in samples})==4
    phase="ADJUDICATION"
    d29,n29=prior("551c0bdb6013b36c53619cfe747ecc7d6bf731d5","bt29-dual-asr-qa-")
    q29=obj(d29/"BRAIN_BT29_QA.json")
    assert q29["schema"]=="BT29_RETAINED_DUAL_ASR_V1" and q29["prior_nonces"]==[n27,n28] and q29["artifact_hashes"]==artifact_hashes and q29["fixture_nonce"]==q28["fixture_nonce"]
    assert q29["small_coverage_permille"]==933 and len(q29["common_exact_phrase_anchors"])==15
    def segments(p,start):
        out=[]
        for seg in obj(p).get("transcription",[]):
            o=seg.get("offsets",{})
            if type(o.get("from")) not in (int,float) or type(o.get("to")) not in (int,float):continue
            a,b=round(o["from"]),round(o["to"]);t=words(seg.get("text",""))
            if 1000<=a<b<=35000 and t:out.append((start*1000+a,start*1000+b,t))
        return out
    def matched(a,b):
        return {m.a+i for m in difflib.SequenceMatcher(None,a,b,autojunk=False).get_matching_blocks() for i in range(m.size)}
    def select(rows,lo,hi):
        return [w for a,b,t in rows if lo-500<(a+b)/2<hi+500 for w in t.split()]
    totals={"small":0,"turbo":0,"consensus":0,"small_unmatched":0,"small_unmatched_repeated":0,"turbo_unmatched":0,"turbo_unmatched_repeated":0}
    counts={k:{"small":0,"turbo":0,"consensus":0} for k in src}
    regions=[]
    page=["<!doctype html><html lang='en'><meta charset='utf-8'><title>BT30 local listening review</title><style>body{font:16px system-ui;margin:24px;max-width:1000px}section{border-top:1px solid #aaa;padding:16px 0}pre{white-space:pre-wrap;background:#eee;color:#222;padding:10px}audio{width:100%}</style><h1>BT30 private listening review</h1><p>Listen to the original sample before revealing the transcript. Relative cue boundaries are not word-level ground truth.</p>"]
    for j,start,audio,asr in sorted(samples):
        check=next(x for x in q29["samples"] if x["sample"]==j)
        assert check["scored"] and check["audio_sha256"]==digest(audio,"sha256") and check["turbo_json_sha256"]==digest(asr,"sha256")
        small=segments(d29/f"small-{j}.json",start);turbo=segments(asr,start)
        assert small and turbo
        lo=max(small[0][0],turbo[0][0]);hi=min(small[-1][1],turbo[-1][1])
        assert hi>lo
        aw=[w for a,b,t in small if lo<=a and b<=hi for w in t]
        bw=[w for a,b,t in turbo if lo<=a and b<=hi for w in t]
        pairs=[(m.a+i,m.b+i) for m in difflib.SequenceMatcher(None,aw,bw,autojunk=False).get_matching_blocks() for i in range(m.size)]
        cw=[aw[a] for a,b in pairs]
        vals={"small":aw,"turbo":bw,"consensus":cw}
        for k,v in vals.items():totals[k]+=len(v)
        rec={"sample":j,"interval_ms":hi-lo,"words":{k:len(v) for k,v in vals.items()},"providers":{}}
        for k,rows in src.items():
            sw=select(rows,lo,hi)
            matches={v:len(matched(t,sw)) for v,t in vals.items()}
            rec["providers"][k]=matches
            for v,x in matches.items():counts[k][v]+=x
        sw=select(src["H"],lo,hi)
        absent_a=set(range(len(aw)))-matched(aw,sw);absent_b=set(range(len(bw)))-matched(bw,sw)
        repeated_a=sum(a in absent_a for a,b in pairs);repeated_b=sum(b in absent_b for a,b in pairs)
        for key,val in (("small_unmatched",len(absent_a)),("small_unmatched_repeated",repeated_a),("turbo_unmatched",len(absent_b)),("turbo_unmatched_repeated",repeated_b)):totals[key]+=val
        rec["small_unmatched"]=len(absent_a);rec["turbo_unmatched"]=len(absent_b);rec["small_unmatched_repeated"]=repeated_a;rec["turbo_unmatched_repeated"]=repeated_b
        anchors=[x for x in q29["common_exact_phrase_anchors"] if x["sample"]==j]
        rec["anchors"]=len(anchors)
        for key in ("small_onset","turbo_onset","small_offset","turbo_offset"):
            rec[key+"_median_signed_ms"]=round(statistics.median([x[key] for x in anchors])) if anchors else None
        regions.append(rec)
        rel=pathlib.PurePosixPath("..",audio.parent.name,audio.name).as_posix()
        page.append(f"<section><h2>Region {j+1}</h2><audio controls preload='none' src='{html.escape(rel,quote=True)}'></audio><details><summary>Show evidence</summary>")
        for title,rows in (("Small.en",small),("Turbo",turbo),("Student SRT",[(a,b,t) for a,b,t in src["H"] if b>=start*1000 and a<=(start+36)*1000])):
            content="\n".join(f"{(a-start*1000)/1000:.3f}–{(b-start*1000)/1000:.3f} | {' '.join(t) if isinstance(t,list) else t}" for a,b,t in rows)
            page.append("<h3>"+html.escape(title)+"</h3><pre>"+html.escape(content)+"</pre>")
        page.append("</details></section>")
    coverage={k:{v:round(1000*n/totals[v]) if totals[v] else None for v,n in vals.items()} for k,vals in counts.items()}
    # Use arrival evidence only; do not attribute silence to the model without backend timestamps.
    d=jobs[1][1];timing=obj(d/"stream-timing.json");assert timing["schema"]=="TTV-STREAM-ARRIVAL-V1"
    times=timing["event_arrival_seconds"]
    assert len(times)==reports["H"]["event_count"] and all(isinstance(x,(int,float)) for x in times)
    gaps=[(round((b-a)*1000),i) for i,(a,b) in enumerate(zip(times,times[1:])) if b>=a]
    largest=max(gaps,default=(0,0))
    drift={}
    for k in ("small_onset","turbo_onset"):
        med=[x[k+"_median_signed_ms"] for x in regions if x[k+"_median_signed_ms"] is not None]
        drift[k+"_regional_median_range_ms"]=max(med)-min(med) if len(med)>1 else None
    report={"schema":"BT30_ADJUDICATION_V1","fixture_nonce":q28["fixture_nonce"],"bt29_nonce":n29,"artifact_hashes":artifact_hashes,"regions":regions,"totals":totals,"common_interval_permille":coverage,"regional_drift":drift,"latency":{"largest_event_arrival_gap_ms":largest[0],"after_event_index":largest[1],"interpretation":"Host arrival gap; cannot distinguish model thinking, CLI buffering or transport from this alone."},"limitations":"Selected four speech samples; shared complete segment and ASR consensus may omit uncertain words and both ASRs can be wrong. Listening review not yet performed. No provider, ASR or media calls, no subtitle edits."}
    (run/"BRAIN_BT30_QA.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
    (run/"PRIVATE_LISTENING_REVIEW.html").write_text("".join(page)+"</html>",encoding="utf-8")
    def val(x):return x if x is not None else "X"
    c=coverage["H"]
    print(f"BT30_R{len(regions)}A{totals['small']}B{totals['turbo']}C{totals['consensus']}Q{val(c['small'])}T{val(c['turbo'])}K{val(c['consensus'])}U{totals['small_unmatched_repeated']}V{totals['turbo_unmatched_repeated']}D{val(drift['small_onset_regional_median_range_ms'])}J{val(drift['turbo_onset_regional_median_range_ms'])}L{largest[0]}H1")

try:main()
except Halt as e:print("BT30_HOLD_"+str(e))
except Exception as e:
    (run/"private-error-type.txt").write_text(type(e).__name__+" "+phase,encoding="utf-8")
    print("BT30_HOLD_"+phase+"_ERROR")
'@
$f=Join-Path $run 'compare.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run 2> (Join-Path $run 'stderr.txt'))
$code='BT30_HOLD_READOUT_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^BT30_[A-Z0-9_]{3,83}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
