# BT21: compare BT20 retained artifact with Teacher and existing ASR; no provider or media calls.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('bt21-v13-readout-'+$rq.nonce)
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
import datetime,sqlite3,urllib.parse,math
run=pathlib.Path(sys.argv[3])
phase="INIT"
def save(name,x):
    (run/name).write_text(json.dumps(x,ensure_ascii=False,indent=2),encoding="utf-8")
def prior(source,prefix,nonce=None):
    found=[]
    for f in (spool/"History").glob("receipt-*.json"):
        q=obj(f)
        if q.get("source_commit")==source and q.get("result")=="SUCCESS" and re.fullmatch("[a-f0-9]{32}",str(q.get("nonce",""))):
            if nonce is None or q["nonce"]==nonce:found.append(q["nonce"])
    assert len(found)==1
    return root/(prefix+found[0])
def words(x):
    return re.findall(r"\w+",html.unescape(re.sub(r"<[^>]*>|\{\\[^}]*\}","",x)).casefold())
def qa():
    global phase
    phase="QA"
    d14=prior("7ec17dcee8ee362c8c691707ee04b7c281240401","bt14-movie-audio-qa-")
    old=obj(d14/"BRAIN_AUDIO_QA.json")
    assert old["schema"]=="BT14_AUDIO_QA_V1" and old["sample_count"]==5 and old["speech_sample_count"]==4
    fixture=obj(root/("bt10-human-fixture-preflight-"+old["fixture_nonce"])/"BRAIN_HUMAN_FIXTURE.json")
    assert fixture["schema"]=="BT10_HUMAN_FIXTURE_V1" and fixture["exact_file_verified"] is True and fixture["selection_fingerprint"]=="0c57a7ebb1d8c09b29b6642d48af57701ca4479e6d6d9f63fa8ae3c26a615b5e"
    jobs=[("N_OS","d4ade6fda6045597267e61f9439bf3635aef2b19","bt11-neon-opensubtitles-","d3132c2bbc0c442a8bb1e12950ab1ed2"),("H_OS_V13","5c01bbd07d767c2b69339ad0eaea79034bb040da","bt20-hydrogen-opensubtitles-","cae5bf1fc2a24c61a862999da0bc2e69")]
    reports={}
    src={}
    for k,source,prefix,nonce in jobs:
        d=prior(source,prefix,nonce)
        r=obj(d/"BRAIN_TEACHER_REPORT.json")
        v=r["video_input"]
        assert hashlib.sha256(re.sub(r"[^a-z0-9]","",str(v["release"]).casefold()).encode()).hexdigest()==fixture["selection_fingerprint"]
        assert v["fps"]==24 and abs(v["duration"]-old["duration_seconds"])<2
        assert r["provider"]=="OpenSubtitles"
        reports[k]=r
        src[k]=srt(d,r,source)
    duration=old["duration_seconds"]
    assert abs(duration-fixture["duration_seconds"])<1
    scores={k:[] for k in src};anchors={k:[] for k in src}
    scored={x["sample"] for x in old["scores"]["N_CAT"]}
    assert len(scored)==4
    for j in sorted(scored):
        assert j in range(5)
        data=obj(d14/f"asr-{j}.json")
        start=max(0,round(duration*(.10,.30,.50,.70,.90)[j]-18))
        segs=[]
        for seg in data.get("transcription",[]):
            o=seg.get("offsets",{})
            if not isinstance(o.get("from"),(float,int)) or not isinstance(o.get("to"),(float,int)):continue
            lo,hi=round(o["from"]),round(o["to"])
            if lo<1000 or hi>35000:continue
            toks=words(seg.get("text",""))
            if toks:segs.append((start*1000+lo,start*1000+hi,toks))
        aw=[w for x in segs for w in x[2]]
        assert len(aw)>=12
        lo,hi=segs[0][0],segs[-1][1]
        for k,rows in src.items():
            sw=[w for x in rows if lo-500<((x[0]+x[1])/2)<hi+500 for w in x[2].split()]
            match=sum(x.size for x in difflib.SequenceMatcher(None,aw,sw,autojunk=False).get_matching_blocks())
            scores[k].append({"sample":j,"asr_words":len(aw),"srt_words":len(sw),"matched":match,"asr_coverage":round(1000*match/len(aw)),"srt_agreement":round(1000*match/max(1,len(sw)))})
            for a,b,toks in segs:
                if len(toks)<4:continue
                near=[x for x in rows if x[1]>=a-5000 and x[0]<=b+5000]
                hits=[]
                for u in range(len(near)):
                    seq=[]
                    for v in range(u,min(u+5,len(near))):
                        seq.extend(near[v][2].split())
                        if len(seq)>len(toks) or seq!=toks[:len(seq)]:break
                        if seq==toks:
                            hits.append((near[u][0]-a,near[v][1]-b));break
                if len(hits)==1:anchors[k].append({"sample":j,"start_delta_ms":hits[0][0],"end_delta_ms":hits[0][1]})
    for k,oldk in (("N_OS","N_OS"),):
        assert scores[k]==sorted(old["scores"][oldk],key=lambda x:x["sample"])
    def metric(vals):
        if not vals:return None
        ab=sorted(abs(x) for x in vals)
        return {"count":len(vals),"median_signed_ms":round(statistics.median(vals)),"median_abs_ms":round(statistics.median(ab)),"p95_abs_ms":ab[math.ceil(.95*len(ab))-1]}
    timeline={}
    for k,values in anchors.items():
        groups={j:metric([x["start_delta_ms"] for x in values if x["sample"]==j]) for j in set(x["sample"] for x in values)}
        med=[v["median_signed_ms"] for v in groups.values()]
        timeline[k]={"onset":metric([x["start_delta_ms"] for x in values]),"offset":metric([x["end_delta_ms"] for x in values]),"regions":groups,"sample_median_range_ms":max(med)-min(med) if len(med)>1 else None}
    def agg(k):
        x=scores[k]
        return round(1000*sum(y["matched"] for y in x)/sum(y["asr_words"] for y in x))
    teacher=src["N_OS"];student=src["H_OS_V13"]
    eq=teacher==student
    content_equal=[x[2] for x in teacher]==[x[2] for x in student]
    token_equal=" ".join(x[2] for x in teacher)==" ".join(x[2] for x in student)
    # Reuse the exact five BT19 disputed intervals, no media reads.
    phase="BT19_REUSE"
    d19=prior("1e8fd0ac41fa9dda91366e4d013ec7b91022bd82","bt19-targeted-audio-qa-")
    q19=obj(d19/"BRAIN_BT19_QA.json")
    assert q19["schema"]=="BT19_TARGETED_ASR_QA_V1" and q19["fixture_nonce"]==old["fixture_nonce"] and len(q19["regions"])==5
    assert q19["artifact_hashes"]["TEACHER"]==next(x["sha256"] for x in reports["N_OS"]["artifacts"] if x.get("copied_to_job"))
    checks=[]
    for x in q19["regions"]:
        g=x["gap"];wanted=g["teacher_words"]
        near=[w for a,b,t in student if a<=g["end_ms"]+1500 and b>=g["start_ms"]-1500 for w in t.split()]
        present=any(near[i:i+len(wanted)]==wanted for i in range(len(near)-len(wanted)+1))
        checks.append({"sample":x["sample"],"previous_asr_classification":x["classification"],"teacher_phrase_present":present})
    recovered=sum(x["teacher_phrase_present"] for x in checks)
    phase="EVIDENCE"
    r=reports["H_OS_V13"];gate=r["filter_gate"]
    # Record evidence privately, without sending media, text, URLs or IDs to public logs.
    save("BRAIN_BT21_QA.json",{"schema":"BT21_REUSE_QA_V1","source":"5c01bbd07d767c2b69339ad0eaea79034bb040da","fixture_nonce":old["fixture_nonce"],"normalized_cue_tuples_equal":eq,"cue_text_equal":content_equal,"token_stream_equal":token_equal,"speech_samples":len(scored),"scores":scores,"coverage_permille":{k:agg(k) for k in src},"timeline":timeline,"anchors":anchors,"bt19_recovered":recovered,"bt19_checks":checks,"filter_gate":gate,"tool_outcomes":r.get("tool_outcomes",[]),"limitations":"Normalized text and timeline equivalence and retained ASR samples do not establish absolute full-film quality."})
    m=timeline["H_OS_V13"]["onset"]
    return f"S{len(scored)}Q{agg('H_OS_V13')}I{int(eq)}{int(content_equal)}{int(token_equal)}R{recovered}A{m['count'] if m else 0}M{m['median_abs_ms'] if m else 9999}P{m['p95_abs_ms'] if m else 9999}"
try:
    result=qa()
except Exception as e:
    save("BT21-error-type.json",{"type":type(e).__name__,"phase":phase})
    result="HOLD_"+phase+"_ERROR"
print("BT21_"+result)

'@
$f=Join-Path $run 'compare.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run 2> (Join-Path $run 'stderr.txt'))
$code='BT21_HOLD_READOUT_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^BT21_[A-Z0-9_]{3,83}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
