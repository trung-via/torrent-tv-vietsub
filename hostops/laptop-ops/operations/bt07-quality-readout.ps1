# Read-only BT04/BT07 comparison, no model, browser, production or provider call.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('bt07-quality-readout-'+$rq.nonce)
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
    ts="4cd3124ac8c7102028ff0b1f079a5b3b522b15c9"
    ss="ca4ccfb812bd05196b0e59c349c7b46b138789bd"
    prior=[]
    for f in (spool/"History").glob("receipt-*.json"):
        q=obj(f)
        if q.get("source_commit")==ts and q.get("result")=="SUCCESS" and re.fullmatch("[a-f0-9]{32}",str(q.get("nonce",""))):prior.append(q["nonce"])
    assert len(prior)==1
    td=root/("bt04-neon-subtitlecat-"+prior[0])
    sd=root/"bt07-hydrogen-subtitlecat-1e4e7ae677d74a01a1367273e1b1d225"
    hand=obj(sd/"BRAIN_RESULT.json")["handoff"]
    assert hand["source"]==ss and hand["nonce"]=="1e4e7ae677d74a01a1367273e1b1d225"
    t=srt(td,obj(td/"BRAIN_TEACHER_REPORT.json"),ts)
    s=srt(sd,obj(sd/"BRAIN_TEACHER_REPORT.json"),ss)
    assert len(t)==1018 and len(s)==919
    tt=" ".join(x[2] for x in t).split(); st=" ".join(x[2] for x in s).split()
    assert 0<len(tt)<20000 and 0<len(st)<20000
    match=sum(x.size for x in difflib.SequenceMatcher(None,tt,st,autojunk=False).get_matching_blocks())
    q=round(1000*match/len(tt)); r=round(1000*match/len(st))
    exact=sum((collections.Counter(x[:2] for x in t)&collections.Counter(x[:2] for x in s)).values())
    tc=collections.Counter(x[2] for x in t);sc=collections.Counter(x[2] for x in s)
    sm={x[2]:x[0] for x in s if x[2] and sc[x[2]]==1}
    ds=sorted(abs(x[0]-sm[x[2]]) for x in t if tc[x[2]]==1 and x[2] in sm)
    drift=round(statistics.median(ds)) if ds else 999999
    p95=ds[min(len(ds)-1, int(.95*len(ds)))] if ds else 999999
    print(f"BT07Q_T{len(t)}_S{len(s)}_Q{q}_R{r}_I{exact}_M{len(ds)}_D{drift}_P{p95}_F{abs(t[0][0]-s[0][0])}_L{abs(t[-1][1]-s[-1][1])}")
try:main()
except Exception:print("BT07Q_READOUT_ERROR")
'@
$f=Join-Path $run 'compare.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool 2> (Join-Path $run 'stderr.txt'))
$code='BT07Q_READOUT_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^BT07Q_[A-Z0-9_]{3,83}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
