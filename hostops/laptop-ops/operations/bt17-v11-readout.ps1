# BT17: reuse BT14 ASR; BT16 terminal download diagnosis without retry.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('bt17-v11-readout-'+$rq.nonce)
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
phase="BT16"
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
def diagnose():
    d=prior("423fc92b958d46bf94b890736c4f22246ce4435f","bt16-hydrogen-opensubtitles-","0f5ecea552e14b4eb1ed77bfb149b9d5d")
    r=obj(d/"BRAIN_TEACHER_REPORT.json")
    assert r["source_commit"]=="423fc92b958d46bf94b890736c4f22246ce4435f" and r["provider"]=="OpenSubtitles" and not r["artifacts"]
    outputs=r.get("tool_outcomes",[])
    clicks=[x for x in outputs if x.get("tool")=="click"]
    last=clicks[-1] if clicks else {}
    out=json.dumps(last,ensure_ascii=True)
    cat="CLOSED" if re.search(r"target closed|page (?:has been |was )?closed|no target with given id",out,re.I) else "CHALLENGE" if re.search(r"captcha|making sure you.re not a bot|anti.bot challenge",out,re.I) else "DENIED" if re.search(r"forbidden|access denied|download limit",out,re.I) else "AUTH" if re.search(r"login required|sign in to download|log in to download",out,re.I) else "ERROR" if last.get("error") else "OUTPUT" if last else "NOCLICK"
    history=root/"CDP9555Profile"/"Default"/"History"
    rows=[];ok=False
    # Read only this attempt's actual Owner execution window and OpenSubtitles downloads.
    def epoch(s):return int((datetime.datetime.fromisoformat(s).timestamp()+11644473600)*1000000)
    try:
        con=sqlite3.connect(history.resolve().as_uri()+"?mode=ro",uri=True,timeout=3)
        con.row_factory=sqlite3.Row
        for rec in con.execute("select id,target_path,state,received_bytes,total_bytes,start_time,interrupt_reason from downloads where start_time>=? and start_time<=? order by id",(epoch("2026-11-25T20:04:09+00:00"),epoch("2026-11-25T20:07:00+00:00"))):
            q=dict(rec)
            chain=[x[0] for x in con.execute("select url from downloads_url_chains where id=? order by chain_index",(q["id"],))]
            if not any(urllib.parse.urlsplit(x).hostname in ("www.opensubtitles.org","opensubtitles.org","dl.opensubtitles.org") for x in chain):continue
            q["chain"]=chain
            p=pathlib.Path(q["target_path"])
            q["file_present"]=p.is_file() and not p.is_symlink()
            q["suffix"]=p.suffix.lower()
            rows.append(q)
        con.close();ok=True
    except (OSError,sqlite3.Error,ValueError):pass
    complete=sum(x["state"]==1 and x["received_bytes"]>0 for x in rows)
    present=sum(x["file_present"] for x in rows)
    saved={"schema":"BT16_DOWNLOAD_DIAG_V1","source":r["source_commit"],"click_category":cat,"last_click_private":last,"provider_access":r.get("provider_access"),"original_history_read":r.get("history_read"),"original_download_rows":r.get("downloads",[]),"original_physical_files":r.get("physical_files",[]),"filter_gate":r.get("filter_gate"),"history_now_read":ok,"attempt_download_rows":rows,"complete_rows":complete,"present_files":present,"model_final_private":r.get("final_response"),"note":"History is a later observation; no provider calls or retry."}
    save("BRAIN_BT16_DIAG.json",saved)
    return f"R{cat}H{int(ok)}D{len(rows)}C{complete}F{present}"
def qa():
    global phase
    phase="BT17"
    d14=prior("7ec17dcee8ee362c8c691707ee04b7c281240401","bt14-movie-audio-qa-")
    old=obj(d14/"BRAIN_AUDIO_QA.json")
    assert old["schema"]=="BT14_AUDIO_QA_V1" and old["sample_count"]==5 and old["speech_sample_count"]==4
    fixture=obj(root/("bt10-human-fixture-preflight-"+old["fixture_nonce"])/"BRAIN_HUMAN_FIXTURE.json")
    assert fixture["schema"]=="BT10_HUMAN_FIXTURE_V1" and fixture["exact_file_verified"] is True and fixture["selection_fingerprint"]=="0c57a7ebb1d8c09b29b6642d48af57701ca4479e6d6d9f63fa8ae3c26a615b5e"
    jobs=[("N_CAT","912b18ec6eaccc4f25f01b395e35d38de18827db","bt11-neon-subtitlecat-","bac0f7270b3545b5bbeac15077d360d6"),("H_CAT_V10","ffdd575ddc553266eb56f91fa737972ae444f9ef","bt13-hydrogen-subtitlecat-","0c90d38da33546c3b75d09388e931c3c"),("H_CAT_V11","2a19574f752faa0b8b9bc83f0c243077a5522e66","bt15-hydrogen-subtitlecat-","c30207ea8b904f7bb4808d39a004177d"),("N_OS","d4ade6fda6045597267e61f9439bf3635aef2b19","bt11-neon-opensubtitles-","d3132c2bbc0c442a8bb1e12950ab1ed2")]
    src={}
    for k,source,prefix,nonce in jobs:
        d=prior(source,prefix,nonce)
        r=obj(d/"BRAIN_TEACHER_REPORT.json")
        v=r["video_input"]
        assert hashlib.sha256(re.sub(r"[^a-z0-9]","",str(v["release"]).casefold()).encode()).hexdigest()==fixture["selection_fingerprint"]
        assert v["fps"]==24 and abs(v["duration"]-old["duration_seconds"])<2
        if k=="H_CAT_V11":assert r["origin_gate"]["accepted"] is True
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
    for k,oldk in (("N_CAT","N_CAT"),("H_CAT_V10","H_CAT"),("N_OS","N_OS")):
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
    eq=src["H_CAT_V11"]==src["N_CAT"]
    equal_os=src["H_CAT_V11"]==src["N_OS"]
    save("BRAIN_BT17_QA.json",{"schema":"BT17_REUSE_QA_V1","bt14_source":"7ec17dcee8ee362c8c691707ee04b7c281240401","fixture_nonce":old["fixture_nonce"],"speech_samples":len(scored),"normalized_v11_equal_teacher_cat":eq,"normalized_v11_equal_teacher_os":equal_os,"scores":scores,"coverage_permille":{k:agg(k) for k in src},"timeline":timeline,"anchors":anchors,"note":"Same ASR reference; does not prove absolute quality or all-film sync. BT16 unavailable."})
    m=timeline["H_CAT_V11"]["onset"]
    return f"S{len(scored)}Q{agg('H_CAT_V11')}I{int(eq)}{int(equal_os)}A{m['count'] if m else 0}M{m['median_abs_ms'] if m else 9999}P{m['p95_abs_ms'] if m else 9999}"
try:
    diag=diagnose()
except Exception as e:
    save("BT16-error-type.json",{"type":type(e).__name__})
    diag="RERROR"
try:
    result=qa()
except Exception as e:
    save("BT17-error-type.json",{"type":type(e).__name__,"phase":phase})
    result="QAERROR"
print("BT17_"+result+"_"+diag)
'@
$f=Join-Path $run 'compare.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run 2> (Join-Path $run 'stderr.txt'))
$code='BT17_HOLD_READOUT_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^BT17_[A-Z0-9_]{3,83}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
