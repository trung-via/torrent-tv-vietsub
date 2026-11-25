# BT09E: read retained reports and create private listening review; no provider or model call.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('bt09e-adjudication-readout-'+$rq.nonce)
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
    phase="INPUTS"
    ts="4cd3124ac8c7102028ff0b1f079a5b3b522b15c9"
    teacher,_=prior(ts,"bt04-neon-subtitlecat-")
    jobs=[("NC",teacher,ts),("HC",root/"bt07-hydrogen-subtitlecat-1e4e7ae677d74a01a1367273e1b1d225","ca4ccfb812bd05196b0e59c349c7b46b138789bd"),("NO",root/"bt05-neon-opensubtitles-0d2ff69cc151464fabe61e6f38fea339","01ab690a99839b006e3763fb7e1b9e7d36f47da8"),("HO",root/"bt08-hydrogen-opensubtitles-10920e6901704d2abb080cd8f808e66d","51a421398d6f3afe4ba350bb0509f28e2834c4b9")]
    src={k:srt(d,obj(d/"BRAIN_TEACHER_REPORT.json"),ref) for k,d,ref in jobs}
    assert [len(x) for x in src.values()]==[1018,919,1018,1018] and src["NO"]==src["HO"]
    old,on=prior("bde31e100e13f9a238415e2a6addb3a512a651c0","bt09-movie-audio-qa-")
    new,nn=prior("205a37fe39a3dc7e1b9da367da472ed29f8f8a77","bt09b-movie-audio-qa-")
    c,cn=prior("86f980548706a4102eca116e48a6b9c5fec1c095","bt09c-timeline-readout-")
    d,dn=prior("cd1ffbdecbda10d61ad210e9844a93fa90f04b4d","bt09d-asr-crosscheck-")
    qa=obj(c/"BRAIN_TIMELINE_QA.json");cross=obj(d/"BRAIN_ASR_CROSSCHECK.json");report=obj(new/"BRAIN_AUDIO_QA.json")
    assert qa["original_nonce"]==cross["baseline_nonce"]==on and qa["resume_nonce"]==cross["resume_nonce"]==nn
    assert cross["scored_regions"]==4 and cross["consensus_words"]==83 and cross["turbo_words"]==153 and qa["all_unmatched_words"]==16
    small=set(qa["speech_regions"])
    turbo={r["sample"] for r in cross["regions"] if r.get("turbo_words",0)>=12 and r.get("rc")==0}
    assert len(small)==len(turbo)==4
    duration=float(report["duration_seconds"])
    assert math.isfinite(duration) and 600<duration<14400
    phase="ANALYSIS"
    records=[]; totals={"small_words":0,"turbo_words":0,"agreement_words":0,"baseline_unmatched_compared":0,"baseline_unmatched_repeated":0}
    common={k:{"a":0,"b":0,"consensus":0} for k in src}
    page=["<!doctype html><html lang='en'><meta charset='utf-8'><title>BT09 private listening review</title><style>body{font:16px system-ui;margin:24px;max-width:1200px}section{margin:30px 0;border-top:1px solid #aaa;padding-top:12px}article{padding:10px;background:#f2f2f2;margin:8px 0;white-space:pre-wrap}audio{width:100%}</style><h1>BT09 private listening review</h1><p>Local evidence only. Listen independently first, then compare the two ASR transcripts and the candidate SRT. Relative times are approximate.</p>"]
    for j in range(5):
        a_dir=old if j==2 else new
        start=max(0,round(duration*(.10,.30,.50,.70,.90)[j]-18))*1000
        audio=a_dir/f"audio-{j}.wav"
        with wave.open(str(audio),"rb") as w:
            assert w.getframerate()==16000 and w.getnchannels()==1 and w.getsampwidth()==2
            assert 34*32000<=len(w.readframes(w.getnframes()))<=37*32000
        a_path=a_dir/f"asr-{j}.json"; b_path=d/f"asr-{j}.json"
        aa=segments(obj(a_path),start) if a_path.is_file() else []
        bb=segments(obj(b_path),start) if b_path.is_file() else []
        row={"sample":j,"pct":10+20*j,"small_scored":j in small,"turbo_scored":j in turbo}
        if j in small&turbo:
            aw=[w for x in aa for w in x[2]];bw=[w for x in bb for w in x[2]]
            assert aw and bw
            # Prior mismatch denominator and intersection, separate from common-window re-evaluation.
            original=[matched(aw,select(rows,aa[0][0],aa[-1][1])) for rows in src.values()]
            absent=set(range(len(aw)))-set.union(*original)
            blocks=difflib.SequenceMatcher(None,aw,bw,autojunk=False).get_matching_blocks()
            aligned=[(m.a+i,m.b+i) for m in blocks for i in range(m.size)]
            repeated=sum(a in absent for a,b in aligned)
            totals["baseline_unmatched_compared"]+=len(absent)
            totals["baseline_unmatched_repeated"]+=repeated
            row.update({"baseline_unmatched_compared":len(absent),"baseline_unmatched_repeated":repeated})
            lo=max(aa[0][0],bb[0][0]);hi=min(aa[-1][1],bb[-1][1])
            # Compare only complete ASR segments in the shared interval. Do not invent word timing.
            ca=[w for l,h,t in aa if lo<=l and h<=hi for w in t]
            cb=[w for l,h,t in bb if lo<=l and h<=hi for w in t]
            pairs=[(m.a+i,m.b+i) for m in difflib.SequenceMatcher(None,ca,cb,autojunk=False).get_matching_blocks() for i in range(m.size)]
            cc=[ca[a] for a,b in pairs]
            totals["small_words"]+=len(ca);totals["turbo_words"]+=len(cb);totals["agreement_words"]+=len(cc)
            row.update({"common_interval_ms":max(0,hi-lo),"small_words":len(ca),"turbo_words":len(cb),"consensus_words":len(cc),"providers":{}})
            for k,rows in src.items():
                sw=select(rows,lo,hi) if hi>lo else []
                values={"a":len(matched(ca,sw)),"b":len(matched(cb,sw)),"consensus":len(matched(cc,sw))}
                for key,v in values.items():common[k][key]+=v
                row["providers"][k]=values
        records.append(row)
        rel=pathlib.PurePosixPath("..",audio.parent.name,audio.name).as_posix()
        page.append(f"<section><h2>Window {10+20*j}%</h2><audio controls preload='none' src='{html.escape(rel,quote=True)}'></audio>")
        def show(label,rows):
            text="\n".join(f"{(l-start)/1000:.2f} - {(h-start)/1000:.2f} | {' '.join(t) if isinstance(t,list) else t}" for l,h,t in rows)
            page.append("<h3>"+html.escape(label)+"</h3><article>"+html.escape(text or "(no retained speech)")+"</article>")
        show("ASR Small.en",aa);show("ASR Large-v3-turbo",bb)
        for k in ("HO","HC"):
            show("Subtitle "+k,[x for x in src[k] if x[1]>=start and x[0]<=start+36000])
        page.append("</section>")
    phase="OUTPUT"
    den={"a":totals["small_words"],"b":totals["turbo_words"],"consensus":totals["agreement_words"]}
    scores={k:{key:round(1000*v/den[key]) if den[key] else None for key,v in x.items()} for k,x in common.items()}
    summary={"schema":"BT09E_ADJUDICATION_V1","crosscheck_nonce":dn,"small_scored":sorted(small),"turbo_scored":sorted(turbo),"both_scored":sorted(small&turbo),"totals":totals,"common_interval_permille":scores,"regions":records,"verdict":"HOLD_ABSOLUTE_QUALITY_UNVERIFIED","method":"Compare complete ASR segments contained in the same shared interval. Consensus is a selected subset, not independent ground truth. Private listening review provides a direct adjudication route."}
    (run/"BRAIN_ADJUDICATION_QA.json").write_text(json.dumps(summary,indent=2),encoding="utf-8")
    (run/"PRIVATE_LISTENING_REVIEW.html").write_text("".join(page)+"</html>",encoding="utf-8")
    ho=scores["HO"]
    def n(v):return v if v is not None else 9999
    print(f"BT09E_R{len(small&turbo)}_U{totals['baseline_unmatched_compared']}_X{totals['baseline_unmatched_repeated']}_A{totals['small_words']}_B{totals['turbo_words']}_C{totals['agreement_words']}_Q{n(ho['a'])}_T{n(ho['b'])}_K{n(ho['consensus'])}_H1")
try:main()
except Exception as e:
    (run/"private-error-type.txt").write_text(type(e).__name__+" "+phase,encoding="utf-8")
    print("BT09E_HOLD_"+phase+"_ERROR")
'@
$f=Join-Path $run 'compare.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run 2> (Join-Path $run 'stderr.txt'))
$code='BT09E_HOLD_READOUT_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^BT09E_[A-Z0-9_]{3,83}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
