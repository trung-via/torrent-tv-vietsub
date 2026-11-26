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
    p=root/"diagnostics"/"owner-full.log"
    if p.is_symlink():raise ValueError()
    with p.open("rb") as f:
        n=f.seek(0,2); off=max(0,n-1048576);f.seek(off);raw=f.read(1048576)
    if off:raw=raw.partition(b"\n")[2]
    lines=raw.decode("utf-8","replace").splitlines()
    starts=[i for i,l in enumerate(lines) if re.fullmatch(r"OWNER_FULL_DIAGNOSTICS_STARTED pid="+str(int(h["pid"]))+r" epoch=[0-9]+",l)]
    if not starts:raise ValueError()
    epoch=int(lines[starts[-1]].rsplit("=",1)[1])
    lines=lines[starts[-1]+1:]
    import ast
    events=[]
    inbox=root/"inbox"
    for l in lines:
        m=re.match(r"OWNER_FULL_TRACE 'P2_(EVENT_CLAIMED|PREPROVIDER_TRANSIENT|EVENT_BLOCKED|EVENT_FINISHED)' (\{.*\})$",l)
        if not m:continue
        try:
            d=ast.literal_eval(m.group(2));eid=d.get("event_id")
            if not isinstance(eid,str) or not re.fullmatch(r"[a-f0-9]{32}",eid):continue
            fs=[inbox/("event-"+eid+ext) for ext in (".json",".blocked",".done",".review")]
            fs=[x for x in fs if x.is_file() and not x.is_symlink()]
            if len(fs)!=1:continue
            e=load(fs[0]);name=re.sub(r"[^a-z0-9]+"," ",str(e.get("selected_video_filename","")).lower())
            if e.get("event_id")!=eid or not re.search(r"\bjohn wick (?:chapter )?(?:4|iv)\b",name):continue
            fp=e.get("source_fingerprint")
            if not isinstance(fp,str) or not re.fullmatch(r"[a-f0-9]{64}",fp):continue
            events.append((m.group(1),fp))
        except (ValueError,SyntaxError,AttributeError,OSError):pass
    if not events:print("R_JW4_EVENT_UNBOUND");sys.exit(0)
    outcome,fp=events[-1]
    cache=root.parent/"subtitle-trials";job=cache/".native-v13"/fp
    import hashlib, math
    sys.path[:0]=[str(root/"app/poc"/x) for x in ("p2-sub-discovery","p2-aisub","p3-vietsub-trigger")]
    from matcher import Media, Subtitle, SearchResults, choose, parse_release, preferred_media_release
    from agy_v13_browser_evidence import filter_gate,_subtitle_bytes,_check_selected_runtime,timeline_observation
    from opensubtitles import validate_timed_text
    def bounded(p,limit):
        if p.is_symlink() or not p.is_file() or not 0<p.stat().st_size<=limit:raise ValueError()
        return p.read_bytes()
    term=load(job/"terminal.json")
    if term.get("reason")!="AGY_EN_MEDIA_RELEASE_MISMATCH":print("R_JW4_STATE_CHANGED");sys.exit(0)
    evidence=json.loads(bounded(job/"evidence.json",16777216))
    blob=bounded(job/"download.bin",2000000)
    media=Media(**evidence["media"])
    digest=hashlib.sha256("\0".join((media.server_profile_id,media.torrent_hash.lower(),str(media.file_index))).encode()).hexdigest()
    if digest!=fp:raise ValueError()
    gate=filter_gate(evidence["outcomes"],evidence["artifacts"])
    if not gate["accepted"] or not gate["chosen_release"]:print("R_JW4_BIND_FAIL");sys.exit(0)
    if evidence["artifacts"][0]["sha256"]!=hashlib.sha256(blob).hexdigest():raise ValueError()
    a=preferred_media_release(media);b=parse_release(gate["chosen_release"])
    def relation(x,y):
        return "U" if x is None or y is None or x=="" or y=="" else "M" if x==y else "D"
    title=relation(a.title.removeprefix("the "),b.title.removeprefix("the "))
    year=relation(a.year,b.year);group=relation(a.group,b.group);source=relation(a.source,b.source);res=relation(a.resolution,b.resolution);codec=relation(a.codec,b.codec)
    runtime="U"
    try:
        _check_selected_runtime(gate,evidence["duration"])
        if any(re.search(r"(?im)^\s*(?:movie\s+)?(?:runtime|duration|length)\s*:\s*(?:\d{1,2}:[0-5]\d:[0-5]\d|\d{1,4}\s*(?:minutes?|mins?))\b",x) for x in gate["chosen_detail_texts"]):runtime="M"
    except Exception:runtime="D"
    n=0;last=0;fps="U"
    try:
        data=_subtitle_bytes(blob);n=validate_timed_text(data,"srt")
        last=timeline_observation(data,evidence["duration"])["last_cue_ms"]//1000
    except Exception:pass
    observed_fps=[]
    for x in gate["chosen_detail_texts"]:
        for f in re.findall(r"(?im)^\s*(?:movie\s+)?fps\s*:\s*(\d{2}(?:[.,]\d{1,3})?)\b",x):
            observed_fps.append(float(f.replace(",",".")))
    if observed_fps:fps="M" if all(abs(x-evidence["fps"])<0.05 for x in observed_fps) else "D"
    decision=choose(media,SearchResults(media.key,(Subtitle("probe",gate["chosen_release"],"en","srt"),)))
    score=decision.ranked[0].score if decision.ranked else 0
    print("R_JW4_T"+title+"Y"+year+"G"+group+"S"+source+"R"+res+"C"+codec+"U"+runtime+"F"+fps+"_N"+str(n)+"_L"+str(last)+"_D"+str(round(evidence["duration"]))+"_K"+str(score))

except Exception:
    print("R_READ_UNAVAILABLE")
'@
$lines=@(& py -3 -I -B -c $py $owner 2>$null)
$code='R_READ_UNAVAILABLE'
if($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and [string]$lines[0] -cmatch '^R_(READ_UNAVAILABLE|[A-Z0-9_]{3,86})$'){$code=[string]$lines[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
