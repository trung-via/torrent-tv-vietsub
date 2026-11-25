# BT09C: read-only exact prior audio transcripts and SRT alignment; no new model or network call.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('bt09c-timeline-readout-'+$rq.nonce)
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
def main():
    global phase
    phase="SELFTEST"
    assert anchor((1000,3000,["one","two","three","four"]),[(1200,3200,"one two three four")])==(200,200)
    assert anchor((1000,3000,["one","two","three","four"]),[(1200,1800,"one two"),(1800,3200,"three four")])==(200,200)
    assert anchor((1000,3000,["one","two","three","four"]),[(1200,3200,"one two three four"),(4000,5000,"one two three four")]) is None
    assert matched(["a","b","c"],["a","c"])=={0,2}
    phase="ARTIFACTS"
    ts="4cd3124ac8c7102028ff0b1f079a5b3b522b15c9"
    teacher,_=prior(ts,"bt04-neon-subtitlecat-")
    jobs=[("NC",teacher,ts),("HC",root/"bt07-hydrogen-subtitlecat-1e4e7ae677d74a01a1367273e1b1d225","ca4ccfb812bd05196b0e59c349c7b46b138789bd"),("NO",root/"bt05-neon-opensubtitles-0d2ff69cc151464fabe61e6f38fea339","01ab690a99839b006e3763fb7e1b9e7d36f47da8"),("HO",root/"bt08-hydrogen-opensubtitles-10920e6901704d2abb080cd8f808e66d","51a421398d6f3afe4ba350bb0509f28e2834c4b9")]
    src={label:srt(d,obj(d/"BRAIN_TEACHER_REPORT.json"),source) for label,d,source in jobs}
    assert [len(x) for x in src.values()]==[1018,919,1018,1018] and src["NO"]==src["HO"]
    phase="ASR_REPORT"
    old,old_nonce=prior("bde31e100e13f9a238415e2a6addb3a512a651c0","bt09-movie-audio-qa-")
    new,new_nonce=prior("205a37fe39a3dc7e1b9da367da472ed29f8f8a77","bt09b-movie-audio-qa-")
    report=obj(new/"BRAIN_AUDIO_QA.json");oldreport=obj(old/"BRAIN_AUDIO_QA.json")
    assert report["schema"]==oldreport["schema"]=="BT09_AUDIO_QA_V1"
    assert report["resumed_original_nonce"]==old_nonce and report["sample_count"]==5 and report["speech_sample_count"]==4
    duration=float(report["duration_seconds"])
    assert math.isfinite(duration) and 600<duration<14400 and abs(duration-float(oldreport["duration_seconds"]))<.01
    assert report["audio_index"]==oldreport["audio_index"]
    samples=set(x["sample"] for x in report["scores"]["H_OS"])
    assert len(samples)==4 and 2 in samples and samples.issubset(set(range(5)))
    assert all(x["classification"]=="OK" for x in report["extraction"]) and len(report["extraction"])==4
    expected={"NC":914,"HC":908,"NO":914,"HO":914}
    accum={k:{"matched":0,"words":0,"anchors":[],"samples":[]} for k in src}
    details=[];all_absent=0;disputed=0;total=0
    phase="ALIGNMENT"
    for j in sorted(samples):
        d=old if j==2 else new
        transcript=obj(d/f"asr-{j}.json")
        start=max(0,round(duration*(.10,.30,.50,.70,.90)[j]-18))*1000
        segs=[]
        for seg in transcript.get("transcription",[]):
            o=seg.get("offsets",{})
            if not isinstance(o.get("from"),(float,int)) or not isinstance(o.get("to"),(float,int)):continue
            lo,hi=round(o["from"]),round(o["to"])
            if lo<1000 or hi>35000:continue
            toks=words(seg.get("text",""))
            if toks:segs.append((start+lo,start+hi,toks))
        aw=[w for seg in segs for w in seg[2]]
        assert 12<=len(aw)<500
        lo,hi=segs[0][0],segs[-1][1]
        sets={};wide_sets={}
        for k,rows in src.items():
            original=[w for x in rows if lo-500<(x[0]+x[1])/2<hi+500 for w in x[2].split()]
            wide=[w for x in rows if lo-5000<(x[0]+x[1])/2<hi+5000 for w in x[2].split()]
            m=matched(aw,original);wm=matched(aw,wide)
            ref=[x for x in report["scores"][{"NC":"N_CAT","HC":"H_CAT","NO":"N_OS","HO":"H_OS"}[k]] if x["sample"]==j]
            assert len(ref)==1 and len(m)==ref[0]["matched"] and len(aw)==ref[0]["asr_words"] and len(original)==ref[0]["srt_words"]
            sets[k]=m;wide_sets[k]=wm
            anchors=[]
            for seg in segs:
                hit=anchor(seg,rows)
                if hit is not None:anchors.append({"sample":j,"start_delta_ms":hit[0],"end_delta_ms":hit[1]})
            accum[k]["matched"]+=len(m);accum[k]["words"]+=len(aw)
            accum[k]["anchors"].extend(anchors)
            accum[k]["samples"].append({"sample":j,"asr_words":len(aw),"tight_matched":len(m),"wide_matched":len(wm),"onset":metric([x["start_delta_ms"] for x in anchors]),"offset":metric([x["end_delta_ms"] for x in anchors])})
        union=set.union(*sets.values());intersection=set.intersection(*sets.values())
        wunion=set.union(*wide_sets.values())
        absent=set(range(len(aw)))-union
        all_absent+=len(absent);disputed+=len(union-intersection);total+=len(aw)
        details.append({"sample":j,"asr_words":len(aw),"all_matched":len(intersection),"candidate_dependent":len(union-intersection),"all_unmatched":len(absent),"unmatched_recovered_by_wider_window":len(absent&wunion)})
    phase="SUMMARY"
    metrics={}
    for k,x in accum.items():
        coverage=round(1000*x["matched"]/x["words"])
        assert coverage==expected[k]
        onset=metric([a["start_delta_ms"] for a in x["anchors"]])
        offset=metric([a["end_delta_ms"] for a in x["anchors"]])
        medians=[s["onset"]["median_signed_ms"] for s in x["samples"] if s["onset"]]
        metrics[k]={"baseline_coverage_permille":coverage,"onset":onset,"offset":offset,"anchor_regions":len(medians),"sample_median_range_ms":max(medians)-min(medians) if len(medians)>=2 else None,"samples":x["samples"],"anchors":x["anchors"]}
    out={"schema":"BT09C_TIMELINE_QA_V1","original_nonce":old_nonce,"resume_nonce":new_nonce,"speech_regions":sorted(samples),"unscored_regions":sorted(set(range(5))-samples),"asr_words":total,"all_unmatched_words":all_absent,"candidate_dependent_words":disputed,"mismatch_by_region":details,"providers":metrics,"method":"Unique exact ASR segment to full consecutive SRT cues within 5s; signed onset/offset differences are approximate ASR segment boundaries, not human verified word timing. All-unmatched words remain unresolved (ASR error, paraphrase, shared omission, or alignment). No new audio or model call."}
    (run/"BRAIN_TIMELINE_QA.json").write_text(json.dumps(out,indent=2),encoding="utf-8")
    def enc(k):
        x=metrics[k]["onset"]
        return f"{k}{min(99,x['count'])}D{min(9999,x['median_abs_ms'])}P{min(9999,x['p95_abs_ms'])}" if x else k+"0D9999P9999"
    code="BT09C_V4_"+"_".join(enc(k) for k in src)
    suffix=f"_U{all_absent}X{disputed}"
    print(code+suffix if len(code+suffix)<=89 else code)
try:main()
except Exception as e:
    (run/"private-error-type.txt").write_text(type(e).__name__+" "+phase,encoding="utf-8")
    print("BT09C_HOLD_"+phase+"_ERROR")
'@
$f=Join-Path $run 'compare.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run 2> (Join-Path $run 'stderr.txt'))
$code='BT09C_HOLD_READOUT_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^BT09C_[A-Z0-9_]{3,83}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
