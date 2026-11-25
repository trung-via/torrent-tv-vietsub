# BT29: cross-check four retained audio windows with existing Small.en, no media reads.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('bt29-dual-asr-qa-'+$rq.nonce)
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
    phase="ASR_SETUP"
    tools=root/"BT09ASRPortable"
    archive=tools/"whisper-bin-x64-b5454.zip"
    assert archive.is_file() and archive.stat().st_size==8928640 and digest(archive,"sha256")=="6ba69e3482d7826214f90a6a9c84ca07782aec1e1d0c6a7c30c994fd5d816ccb"
    model=tools/"ggml-small.en.bin"
    expected="db8a495a91d927739e50b3fc1cc4c6b8f6c2d022"
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
    phase="CROSSCHECK"
    def segments(p,start):
        out=[]
        for seg in obj(p).get("transcription",[]):
            o=seg.get("offsets",{})
            if type(o.get("from")) not in (int,float) or type(o.get("to")) not in (int,float):continue
            a,b=round(o["from"]),round(o["to"]);t=words(seg.get("text",""))
            if 1000<=a<b<=35000 and t:out.append((start*1000+a,start*1000+b,t))
        return out
    def anchors(ref,rows):
        result={}
        for a,b,t in ref:
            if len(t)<4:continue
            near=[x for x in rows if x[1]>=a-5000 and x[0]<=b+5000]
            hits=[]
            for u in range(len(near)):
                seq=[]
                for v in range(u,min(u+5,len(near))):
                    seq.extend(near[v][2].split())
                    if len(seq)>len(t) or seq!=t[:len(seq)]:break
                    if seq==t:hits.append((near[u][0],near[v][1]));break
            if len(hits)==1:result.setdefault(hits[0],[]).append((a,b,tuple(t)))
        return {k:v[0] for k,v in result.items() if len(v)==1}
    def metric(v):
        if not v:return None
        ab=sorted(abs(x) for x in v)
        return {"count":len(v),"median_signed_ms":round(statistics.median(v)),"median_abs_ms":round(statistics.median(ab)),"p95_abs_ms":ab[math.ceil(.95*len(ab))-1]}
    checks=[];common=[];small_on=[];turbo_on=[];small_off=[];turbo_off=[];disagree=[];agree=[];regions=[]
    for j,start,audio,asr in sorted(samples):
        dest=run/f"small-{j}"
        rc=cmd([str(cli[0]),"-m",str(model),"-f",str(audio),"-l","en","-t","6","-oj","-of",str(dest),"-np"],f"small-process-{j}",120)
        rec={"sample":j,"audio_sha256":digest(audio,"sha256"),"turbo_json_sha256":digest(asr,"sha256"),"rc":rc,"scored":False}
        checks.append(rec)
        if rc!=0 or not dest.with_suffix(".json").is_file():continue
        small=segments(dest.with_suffix(".json"),start);turbo=segments(asr,start)
        if sum(len(t) for a,b,t in small)<12:continue
        rec["scored"]=True
        aw=[w for a,b,t in small for w in t]
        lo,hi=small[0][0],small[-1][1]
        sw=[w for a,b,t in src["H"] if lo-500<(a+b)/2<hi+500 for w in t.split()]
        matched=sum(x.size for x in difflib.SequenceMatcher(None,aw,sw,autojunk=False).get_matching_blocks())
        rec["small_words"]=len(aw);rec["matched"]=matched
        sa=anchors(small,src["H"]);ta=anchors(turbo,src["H"])
        for key in sorted(sa.keys()&ta.keys()):
            s0,s1,st=sa[key];t0,t1,tt=ta[key]
            if st!=tt:continue
            a,b=key
            item={"sample":j,"small_onset":a-s0,"turbo_onset":a-t0,"small_offset":b-s1,"turbo_offset":b-t1,"asr_onset_difference":s0-t0,"asr_offset_difference":s1-t1}
            common.append(item)
            small_on.append(a-s0);turbo_on.append(a-t0);small_off.append(b-s1);turbo_off.append(b-t1);disagree.append(s0-t0)
            # Agreement is a diagnostic category, not a ground-truth verdict.
            if abs(s0-t0)<=250:agree.append(item)
        rec["common_anchors"]=sum(x["sample"]==j for x in common)
    for j in sorted({x["sample"] for x in common}):
        xs=[x for x in common if x["sample"]==j]
        regions.append({"sample":j,"small":metric([x["small_onset"] for x in xs]),"turbo":metric([x["turbo_onset"] for x in xs])})
    total=sum(x.get("small_words",0) for x in checks)
    coverage=round(1000*sum(x.get("matched",0) for x in checks)/total) if total else None
    sm=metric(small_on);tu=metric(turbo_on);di=metric(disagree)
    agreed=metric([round((x["small_onset"]+x["turbo_onset"])/2) for x in agree])
    report={"schema":"BT29_RETAINED_DUAL_ASR_V1","fixture_nonce":q28["fixture_nonce"],"prior_nonces":[n27,n28],"artifact_hashes":artifact_hashes,"small_model_sha1":expected,"runtime_sha256":digest(archive,"sha256"),"samples":checks,"small_coverage_permille":coverage,"common_exact_phrase_anchors":common,"common_region_metrics":regions,"small_onset":sm,"turbo_onset":tu,"small_offset":metric(small_off),"turbo_offset":metric(turbo_off),"between_asr_onset":di,"agreed_250ms_count":len(agree),"agreed_anchor_average_onset":agreed,"limitations":"Shared Whisper model family; same exact phrase boundaries only. ASR agreement is not human ground truth; small common-anchor count or region coverage is insufficient. No media, provider or production calls. No timestamp edits."}
    (run/"BRAIN_BT29_QA.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
    def v(x,k):return str(x[k]) if x else "X"
    print(f"BT29_S{sum(x['scored'] for x in checks)}Q{coverage if coverage is not None else 'X'}K{len(common)}R{len(regions)}D{v(di,'median_abs_ms')}M{v(sm,'median_abs_ms')}P{v(sm,'p95_abs_ms')}T{v(tu,'median_abs_ms')}A{len(agree)}B{v(agreed,'median_abs_ms')}Z{v(agreed,'p95_abs_ms')}")

try:main()
except Halt as e:print("BT29_HOLD_"+str(e))
except Exception as e:
    (run/"private-error-type.txt").write_text(type(e).__name__+" "+phase,encoding="utf-8")
    print("BT29_HOLD_"+phase+"_ERROR")
'@
$f=Join-Path $run 'compare.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run 2> (Join-Path $run 'stderr.txt'))
$code='BT29_HOLD_READOUT_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^BT29_[A-Z0-9_]{3,83}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
