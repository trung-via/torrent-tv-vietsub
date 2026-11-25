# BT16R2: resolve the unique original receipt by SHA, diagnose retained download only; no ASR or provider retry.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('bt16r2-download-readout-'+$rq.nonce)
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
    d=prior("423fc92b958d46bf94b890736c4f22246ce4435f","bt16-hydrogen-opensubtitles-")
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
try:
    diag=diagnose()
    print("BT16R2_"+diag)
except Exception as e:
    save("BT16-error-type.json",{"type":type(e).__name__,"phase":"DIAGNOSE"})
    print("BT16R2_HOLD_"+type(e).__name__.upper())

'@
$f=Join-Path $run 'compare.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run 2> (Join-Path $run 'stderr.txt'))
$code='BT16R2_HOLD_READOUT_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^BT16R2_[A-Z0-9_]{3,83}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
