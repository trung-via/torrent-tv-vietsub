# Owner read-only current request diagnostic; only bounded, fixed enum evidence leaves Owner.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$py=@'
import pathlib,sys,json,re,time
root=pathlib.Path(sys.argv[1])
def load(p):
    if p.is_symlink() or not p.is_file() or not 0<p.stat().st_size<=4096:raise ValueError()
    return json.loads(p.read_text(encoding="utf-8-sig"))
try:
    h=load(root/"agent-health.json")
    if h.get("state")!="READY" or not 0<=time.time()-h["observed_utc_epoch"]<=30:raise ValueError()
    import hashlib
    cache=root.parent/"subtitle-trials";state=root.parent/"P2/auto-lean120-state"
    sys.path[:0]=[str(root/"app/poc"/x) for x in ("p2-sub-discovery","p2-aisub","p3-vietsub-trigger")]
    from agy_v13_native_producer import _retained_verified
    from matcher import Media
    from cached_en_direct_handoff import CachedEnReceipt,prepare_local_translation_source
    from automatic_lean120_worker import AutomaticLean120Worker
    from lean120_api import ModelProfile
    def read(p,limit=16777216):
        if p.is_symlink() or not p.is_file() or not 0<p.stat().st_size<=limit:raise ValueError()
        return json.loads(p.read_text(encoding="utf-8-sig"))
    import datetime,urllib.parse
    from agy_v13_browser_evidence import filter_gate,_subtitle_bytes,_check_selected_movie
    from opensubtitles import validate_timed_text
    from agy_v13_native_producer import _job
    lo=datetime.datetime(2026,11,26,17,19,tzinfo=datetime.timezone.utc).timestamp()
    hi=datetime.datetime(2026,11,26,17,25,tzinfo=datetime.timezone.utc).timestamp()
    found=[]
    for f in (root/"inbox").glob("event-*.blocked"):
        if not lo<=f.stat().st_mtime<=hi:continue
        e=read(f,65536);fp=e.get("source_fingerprint")
        if not isinstance(fp,str) or not re.fullmatch(r"[a-f0-9]{64}",fp):continue
        job=cache/".native-v13"/fp
        term=job/"terminal.json";prompt=job/"prompt.txt"
        if not term.is_file() or not prompt.is_file():continue
        q=read(term,4096)
        if q.get("reason")!="AGY_EN_LIST_COVERAGE_UNVERIFIED" or q.get("status")!="SOURCE_REJECTED":continue
        if not prompt.read_text(encoding="utf-8").startswith("Student Recipe V13.2 Compact."):continue
        if not lo<=term.stat().st_mtime<=hi:continue
        proof=read(job/"evidence.json");media=Media(**proof["media"])
        if _job(cache,media)!=job or media.filename!=e.get("selected_video_filename"):continue
        found.append((job,proof,media))
    if len(found)!=1:print("R_AUDIT_JOB_COUNT_"+str(len(found)));sys.exit(0)
    job,proof,media=found[0]
    def sid(v):
        if not isinstance(v,str):return ""
        u=urllib.parse.urlsplit(urllib.parse.urljoin("https://www.opensubtitles.org/",v))
        if u.scheme!="https" or u.hostname not in {"www.opensubtitles.org","opensubtitles.org","dl.opensubtitles.org"}:return ""
        m=re.search(r"/(?:subtitles|download/sub|subtitleserve/sub)/(\d+)(?:/|$)",u.path)
        return m[1] if m else ""
    art=proof["artifacts"][0];blob=(job/"download.bin").read_bytes()
    if hashlib.sha256(blob).hexdigest()!=art.get("sha256") or len(blob)!=art.get("bytes"):raise ValueError()
    ids={sid(x) for x in art.get("candidate_refs",[])}-{""}
    if len(ids)!=1:print("R_AUDIT_ARTIFACT_ID_COUNT_"+str(len(ids)));sys.exit(0)
    cid=next(iter(ids));documents=[]
    for o in proof["outcomes"]:
        if o.get("error"):continue
        def walk(x,depth=0):
            if depth>5:return
            if isinstance(x,dict):
                documents.append((o["event"],x))
                for y in x.values():
                    if isinstance(y,(dict,list)):walk(y,depth+1)
                    elif isinstance(y,str) and y.lstrip().startswith(("{","[",chr(96))):walk(y,depth+1)
            elif isinstance(x,list):
                for y in x[:500]:walk(y,depth+1)
            elif isinstance(x,str):
                for block in re.findall(r"(?s)\x60\x60\x60(?:json)?\s*(\{.*?\})\s*\x60\x60\x60",x) or [x.strip()]:
                    try:walk(json.loads(block),depth+1)
                    except (ValueError,TypeError):pass
        walk(o.get("output"))
    def lang(v):
        if v is None:return "M"
        if not isinstance(v,str):return "T"
        v=" ".join(v.casefold().split())
        if not v:return "E"
        if v in {"english","en","eng","flag en"}:return "A"
        if v in {"unknown","null","n/a","none","-"}:return "U"
        if re.fullmatch(r"(?:flag[-_ ]+)*(?:english|eng|en)(?:[-_ ]+flag)*",v):return "F"
        if re.search(r"\benglish\b",v):return "W"
        if re.search(r"\b(?:eng|en)\b",v):return "C"
        return "O"
    rows=[];parents=[];details=[];clicks=[]
    for ev,d in documents:
        if sid(d.get("href"))==cid and d.get("clicked") is not True:rows.append((ev,d))
        if isinstance(d.get("rows"),list) and any(isinstance(r,dict) and sid(r.get("href"))==cid for r in d["rows"]):parents.append((ev,d))
        if sid(d.get("url"))==cid and d.get("btnVisible") is True:details.append((ev,d))
        if d.get("clicked") is True and sid(d.get("pageUrl"))==cid:clicks.append((ev,d))
    if len(rows)!=1 or len(details)!=1 or len(clicks)!=1:print("R_LANG_SHAPE");sys.exit(0)
    ev,row=rows[0];_,detail=details[0]
    def haseng(s):return isinstance(s,str) and bool(re.search(r"\benglish\b",s,re.I))
    def slug(s):return isinstance(s,str) and bool(re.search(r"-en/?(?:$|[?#])",s,re.I))
    def filt(s):return isinstance(s,str) and bool(re.search(r"(?:^|/)sublanguageid-eng(?:/|$)",s))
    field=detail.get("fieldsetText","")
    sub=_subtitle_bytes(blob)
    from agy_v13_browser_evidence import _check_selected_runtime,timeline_observation
    runtime=1
    try:_check_selected_runtime({"chosen_detail_texts":[field]},proof["duration"])
    except Exception:runtime=0
    obs=timeline_observation(sub,proof["duration"])
    over=int(obs["last_cue_ms"]>(proof["duration"]+2)*1000)
    words=re.findall(r"[a-z]+",sub.decode("utf-8-sig").lower())
    common=sum(w in {"the","you","i","is","to","a","and","of","it","that","we","my","your","not","what","me","this","he","she","do","have","are","was","can","for","in","on","with","they","but","don","just"} for w in words)
    pct=round(100*common/max(1,len(words)))
    flags="".join(lang(row.get(k)) for k in ("lang","language","language_code","languageCode"))
    df="".join(lang(detail.get(k)) for k in ("lang","language"))
    explicit=int(bool(re.search(r"(?im)^\s*(?:subtitle\s+)?language\s*[:=]?\s*english\b",field)))
    print("R_LANG_"+flags+"_D"+df+"F"+str(int(haseng(field)))+"X"+str(explicit)+"T"+str(int(haseng(detail.get("title"))))+"S"+str(int(slug(detail.get("url"))))+"_P"+str(len(parents))+"U"+str(int(any(filt(d.get("url")) for _,d in parents)))+"H"+str(int(any(haseng(d.get("heading")) for _,d in parents)))+"Y"+str(int(any(haseng(d.get("page_title")) for _,d in parents)))+"_C"+str(pct)+"_R"+str(runtime)+"O"+str(over)+"_L"+str(obs["last_cue_ms"]//1000)+"D"+str(round(proof["duration"])))

except Exception:
    print("R_READ_UNAVAILABLE")
'@
$lines=@(& py -3 -I -B -c $py $owner 2>$null)
$code='R_READ_UNAVAILABLE'
if($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and [string]$lines[0] -cmatch '^R_(READ_UNAVAILABLE|[A-Z0-9_]{3,86})$'){$code=[string]$lines[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
