# BT10: verify legacy second-fixture private artifacts and exact local media/audio metadata.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('bt10-second-fixture-preflight-'+$rq.nonce)
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
def main():
    import urllib.request
    phase="REPORTS"
    jobs=[("CAT","6e28d723bf95611bb8a4541cd54ea0e1bcf74fdc","tr-ttv-16-kalki2898ad-subtitlecat-v4-profile-"),("OS","bfc80f4cd94c800e92ae3ab63e25227c1e2bb7b6","tr-ttv-17-kalki2898ad-opensubtitles-v4-profile-")]
    rows={};statuses={}
    for label,source,prefix in jobs:
        try:
            matches=[]
            for f in (spool/"History").glob("receipt-*.json"):
                r=obj(f)
                if r.get("source_commit")==source and r.get("result")=="SUCCESS" and re.fullmatch("[a-f0-9]{32}",str(r.get("nonce",""))):matches.append(r["nonce"])
            assert len(matches)==1
            d=root/(prefix+matches[0])
            report=obj(d/"BRAIN_STUDENT_REPORT.json")
            assert report["source_commit"]==source and report["recipe_version"]=="V4"
            assert hashlib.sha256(re.sub(r"[^a-z0-9]","",report["video_input"]["release"].casefold()).encode()).hexdigest()=="4063a310983cf48f69017df3bc349e019f00fb5c3920e8477e8f387403463e51"
            a=[x for x in report["artifacts"] if x.get("cues",0)>0]
            assert len(a)==1
            # Legacy report didn't mark copied_to_job; independently verify exact private copy by SHA in srt().
            a[0]["copied_to_job"]=True
            rows[label]=srt(d,report,source)
            statuses[label]="VERIFIED"
        except Exception:statuses[label]="UNAVAILABLE"
    t=rows.get("CAT",[]);s=rows.get("OS",[])
    q=r=0
    if t and s:
        tt=" ".join(x[2] for x in t).split();st=" ".join(x[2] for x in s).split()
        assert 0<len(tt)<30000 and 0<len(st)<30000
        match=sum(x.size for x in difflib.SequenceMatcher(None,tt,st,autojunk=False).get_matching_blocks())
        q=round(1000*match/len(tt));r=round(1000*match/len(st))
    owner=root.parent/"OwnerBridge"
    sys.path.insert(0,str(owner/"app/poc/p2-sub-discovery"))
    from owner_torrserver_readonly import OwnerLocalTorrServer,OwnerTorrServerReader,_local_post
    policy=obj(owner/"p3-p4-policy.json")
    cfg=OwnerLocalTorrServer(policy["profile_id"],policy["torrserver_port"])
    listing=json.loads(_local_post(cfg.url,b'{"action":"list"}',6.0))
    assert isinstance(listing,list) and len(listing)<=256
    target="4063a310983cf48f69017df3bc349e019f00fb5c3920e8477e8f387403463e51"
    def matchrelease(x):return hashlib.sha256(re.sub(r"[^a-z0-9]","",str(x).casefold()).encode()).hexdigest()==target
    found={}
    for v in listing:
        if not isinstance(v,dict):continue
        tor=v.get("hash")
        if not isinstance(tor,str) or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}",tor):continue
        files=v.get("file_stats")
        if not files:
            try:files=json.loads(v.get("data","{}"))["TorrServer"]["Files"]
            except (ValueError,TypeError,KeyError):continue
        if not isinstance(files,list) or len(files)>4096:continue
        for x in files:
            name=str(x.get("path","")).replace("\\","/").rsplit("/",1)[-1]
            idx=x.get("id")
            if type(idx) is not int or not 0<=idx<4096 or not re.search(r"\.(mkv|mp4|avi|m4v|ts|m2ts)$",name,re.I):continue
            if not (matchrelease(pathlib.PurePosixPath(name).stem) or matchrelease(v.get("title",""))):continue
            if type(x.get("length")) is int and x["length"]>100000000:found[(tor,idx)]=name
    ready=0;en=0;audio=0;probe=0
    if len(found)==1:
        (tor,idx),name=next(iter(found.items()))
        actual=OwnerTorrServerReader(cfg)(cfg.profile_id,tor,idx)
        ready=int(actual.path.replace("\\","/").rsplit("/",1)[-1]==name)
        if ready:
            try:
                from owner_torrserver_ffp_tracks import _read_local_ffp
                doc=json.loads(_read_local_ffp(f"http://127.0.0.1:{cfg.localhost_port}/ffp/{tor}/{idx}",8.0))
                streams=doc.get("streams",[])
                assert isinstance(streams,list) and 0<len(streams)<=128
                aud=[x for x in streams if isinstance(x,dict) and x.get("codec_type")=="audio"]
                audio=len(aud);en=sum(str(x.get("tags",{}).get("language","")).lower() in ("en","eng","english") for x in aud)
                probe=1
            except Exception:pass
    run=pathlib.Path(sys.argv[3])
    (run/"BRAIN_SECOND_FIXTURE_PREFLIGHT.json").write_text(json.dumps({"schema":"BT10_PREFLIGHT_V1","legacy_artifacts":statuses,"cues":{"CAT":len(t),"OS":len(s)},"srt_to_srt_permille":{"CAT":q,"OS":r},"exact_media_present":bool(ready),"ffp_read":bool(probe),"audio_tracks":audio,"tagged_en_tracks":en,"note":"English ASR is valid only on confirmed EN audio. No new provider download, movie seek or ASR."},indent=2),encoding="utf-8")
    print(f"BT10P_C{len(t)}_O{len(s)}_Q{q}_R{r}_T{ready}_P{probe}_A{audio}_E{en}")
try:main()
except Exception:print("BT10P_READOUT_ERROR")
'@
$f=Join-Path $run 'compare.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run 2> (Join-Path $run 'stderr.txt'))
$code='BT10P_READOUT_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^BT10P_[A-Z0-9_]{3,83}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
