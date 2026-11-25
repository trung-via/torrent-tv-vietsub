# BT09: compare existing OpenSubtitles artifacts and inventory local ground-truth prerequisites; no ASR/model call.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('bt09-groundtruth-preflight-'+$rq.nonce)
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
    import importlib.util,shutil,os
    ts="01ab690a99839b006e3763fb7e1b9e7d36f47da8"
    ss="51a421398d6f3afe4ba350bb0509f28e2834c4b9"
    td=root/"bt05-neon-opensubtitles-0d2ff69cc151464fabe61e6f38fea339"
    sd=root/"bt08-hydrogen-opensubtitles-10920e6901704d2abb080cd8f808e66d"
    for d,source in ((td,ts),(sd,ss)):
        assert obj(d/"BRAIN_RESULT.json")["handoff"]["source"]==source
    t=srt(td,obj(td/"BRAIN_TEACHER_REPORT.json"),ts)
    s=srt(sd,obj(sd/"BRAIN_TEACHER_REPORT.json"),ss)
    tt=" ".join(x[2] for x in t).split(); st=" ".join(x[2] for x in s).split()
    assert 0<len(tt)<20000 and 0<len(st)<20000
    match=sum(x.size for x in difflib.SequenceMatcher(None,tt,st,autojunk=False).get_matching_blocks())
    q=round(1000*match/len(tt)); r=round(1000*match/len(st))
    exact=int(t==s)
    ff=int(bool(shutil.which("ffmpeg")));fp=int(bool(shutil.which("ffprobe")))
    fw=int(importlib.util.find_spec("faster_whisper") is not None)
    wh=int(importlib.util.find_spec("whisper") is not None)
    wc=int(bool(shutil.which("whisper-cli") or shutil.which("whisper")))
    owner=root.parent/"OwnerBridge"
    ready=0
    try:
        sys.path.insert(0,str(owner/"app/poc/p2-sub-discovery"))
        from owner_torrserver_readonly import OwnerLocalTorrServer,OwnerTorrServerReader,_local_post
        policy=obj(owner/"p3-p4-policy.json")
        cfg=OwnerLocalTorrServer(policy["profile_id"],policy["torrserver_port"])
        listing=json.loads(_local_post(cfg.url,b'{"action":"list"}',6.0))
        assert isinstance(listing,list) and len(listing)<=256
        target="8af4f744c246ab341688e00eb919df53fe7c48c540910d66659b6c659ae11b89"
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
        if len(found)==1:
            (tor,idx),name=next(iter(found.items()))
            actual=OwnerTorrServerReader(cfg)(cfg.profile_id,tor,idx)
            ready=int(actual.path.replace("\\","/").rsplit("/",1)[-1]==name)
    except Exception:ready=0
    print(f"BT09P_Q{q}_R{r}_E{exact}_F{ff}_P{fp}_A{fw}_W{wh}_C{wc}_T{ready}")
try:main()
except Exception:print("BT09P_READOUT_ERROR")
'@
$f=Join-Path $run 'compare.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool 2> (Join-Path $run 'stderr.txt'))
$code='BT09P_READOUT_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^BT09P_[A-Z0-9_]{3,83}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
