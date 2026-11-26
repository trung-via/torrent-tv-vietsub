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
    row=lang=release=match=detail=button=href=field=click=clickhref=check=0
    rows=[];details=[];clicks=[]
    for ev,d in documents:
        if sid(d.get("href"))==cid and d.get("clicked") is not True:
            row+=1
            l=str(d.get("lang",d.get("language",""))).casefold().strip()
            lang+=int(l in {"en","eng","english","flag en"})
            label=d.get("release",d.get("release_name"))
            if isinstance(label,str) and label.strip():
                release+=1
                try:_check_selected_movie(media,label);match+=1
                except Exception:pass
            rows.append(ev)
        if sid(d.get("url"))==cid:
            detail+=1;button+=int(d.get("btnVisible") is True)
            href+=int(sid(d.get("downloadHref"))==cid)
            field+=int(isinstance(d.get("fieldsetText"),str) and bool(d["fieldsetText"]))
            details.append(ev)
        if d.get("clicked") is True and (sid(d.get("pageUrl"))==cid or str(d.get("id"))==cid):
            click+=1;clickhref+=int(sid(d.get("href"))==cid)
            check+=int("downloaderChecked" in d and d["downloaderChecked"] in (None,False))
            clicks.append(ev)
    order=int(any(r<d<c for r in rows for d in details for c in clicks))
    cues=validate_timed_text(_subtitle_bytes(blob),"srt")
    gate=filter_gate(proof["outcomes"],proof["artifacts"])
    print("R_AUDIT_O"+str(len(proof["outcomes"]))+"J"+str(len(documents))+"_R"+str(row)+"L"+str(lang)+"B"+str(release)+"M"+str(match)+"_D"+str(detail)+"V"+str(button)+"H"+str(href)+"F"+str(field)+"_C"+str(click)+"H"+str(clickhref)+"K"+str(check)+"Q"+str(order)+"_N"+str(cues)+"_G"+str(int(gate["accepted"])))

except Exception:
    print("R_READ_UNAVAILABLE")
'@
$lines=@(& py -3 -I -B -c $py $owner 2>$null)
$code='R_READ_UNAVAILABLE'
if($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and [string]$lines[0] -cmatch '^R_(READ_UNAVAILABLE|[A-Z0-9_]{3,86})$'){$code=[string]$lines[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
