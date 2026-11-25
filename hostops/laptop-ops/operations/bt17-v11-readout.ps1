# BT22: offline diagnosis of BT20 list and comparison evidence; no provider or ASR calls.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('bt22-v13-evidence-diag-'+$rq.nonce)
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
    phase="REPORT"
    source="5c01bbd07d767c2b69339ad0eaea79034bb040da"
    # Exact nonce from the actual BT20 terminal handoff, not a new acquisition.
    d=root/"bt20-hydrogen-opensubtitles-cae5bf1fc2a24c61a862999da0bc2e69"
    r=obj(d/"BRAIN_TEACHER_REPORT.json")
    assert r["source_commit"]==source and r["provider"]=="OpenSubtitles"
    assert r["filter_gate"]["ordinary_click_bound"] is True and r["filter_gate"]["download_verified"] is True
    assert len(srt(d,r,source))==2398
    phase="EVIDENCE"
    def url(v):
        if not isinstance(v,str) or not v:return None
        try:u=urllib.parse.urlsplit(urllib.parse.urljoin("https://www.opensubtitles.org/",v))
        except ValueError:return None
        return u if u.scheme=="https" and u.hostname in {"www.opensubtitles.org","opensubtitles.org","dl.opensubtitles.org"} else None
    def sid(v):
        u=url(v);m=re.search(r"/(?:subtitles|download/sub|subtitleserve/sub)/(\d+)(?:/|$)",u.path) if u else None
        return m[1] if m else ""
    def docs(v):
        if isinstance(v,dict):return [v]
        if not isinstance(v,str):return []
        result=[]
        for block in re.findall(r"(?s)\x60\x60\x60(?:json)?\s*(\{.*?\})\s*\x60\x60\x60",v) or [v.strip()]:
            try:x=json.loads(block)
            except (ValueError,TypeError):continue
            if isinstance(x,dict):result.append(x)
        return result
    lists=[];detail_ids=set();strict_ids=set();group_map={};clicks=[]
    for o in r["tool_outcomes"]:
        if o.get("error") or o.get("tool")!="evaluate_script":continue
        for x in docs(o.get("output")):
            u=url(x.get("url"));did=sid(x.get("url"))
            if did:
                detail_ids.add(did)
                if x.get("btnVisible") is True and isinstance(x.get("fieldsetText"),str) and x["fieldsetText"] and sid(x.get("downloadHref"))==did:strict_ids.add(did)
            if x.get("clicked") is True:clicks.append(x)
            if not u or not re.search(r"(?:^|/)sublanguageid-eng(?:/|$)",u.path) or not re.search(r"\benglish\b",str(x.get("heading","")),re.I):continue
            rows=x.get("rows")
            if not isinstance(rows,list):continue
            ids={sid(v.get("href")) for v in rows if isinstance(v,dict) and " ".join(str(v.get("lang","")).casefold().split()) in {"english","en","eng","flag en"}}-{""}
            for row in rows:
                if isinstance(row,dict) and sid(row.get("href")) in ids and isinstance(row.get("release_group"),str) and row["release_group"].strip().casefold() not in ("","unknown","null"):
                    group_map[sid(row.get("href"))]=row["release_group"].strip().casefold()
            title=x.get("page_title")
            m=re.search(r"\bEnglish\s*\|\s*(\d+)\s+subtitles?\s*$",title,re.I) if isinstance(title,str) else None
            # Reason codes refer to the original gate, not claims of a new verified result.
            total=x.get("total_english")
            issues=[]
            if not m:issues.append("TITLE_PATTERN_MISSING")
            if m and (type(total) is not int or int(m[1])!=total):issues.append("TOTAL_MISMATCH")
            if x.get("count_scope")!="filtered_results":issues.append("SCOPE_MISSING")
            if x.get("count_label")!=title:issues.append("LABEL_MISMATCH")
            if type(total) is not int or not 0<total<=500:issues.append("COUNT_INVALID")
            if len(ids)!=len(rows):issues.append("ROWS_INVALID")
            if x.get("has_next") is not False:issues.append("PAGINATION_NOT_TERMINAL")
            if type(total) is int and total!=len(ids):issues.append("COUNT_NOT_EQUAL_ROWS")
            lists.append({"event":o.get("event"),"row_count":len(rows),"english_ids":len(ids),"title_count":int(m[1]) if m else None,"total_english":total,"issues":issues})
    issue_set={i for x in lists for i in x["issues"]}
    n=lists[0]["english_ids"] if len(lists)==1 else 0
    distinct=len(set(group_map.values()))
    verified_groups=len({group_map[x] for x in strict_ids if x in group_map})
    save("BRAIN_BT22_DIAG.json",{"schema":"BT22_V13_EVIDENCE_DIAG_V1","source":source,"list_events":lists,"actual_detail_ids":sorted(detail_ids),"strict_detail_ids":sorted(strict_ids),"release_groups":group_map,"clicks":clicks,"original_gate":r["filter_gate"],"limitations":"Retained output only; no new provider calls. Cannot infer unseen rows or completeness."})
    flags="".join(str(int(x in issue_set)) for x in ("TITLE_PATTERN_MISSING","TOTAL_MISMATCH","SCOPE_MISSING","LABEL_MISMATCH","COUNT_INVALID","ROWS_INVALID","PAGINATION_NOT_TERMINAL","COUNT_NOT_EQUAL_ROWS"))
    return f"L{len(lists)}N{n}D{len(detail_ids)}V{len(strict_ids)}G{distinct}Q{verified_groups}F{flags}"
try:
    result=qa()
except Exception as e:
    save("BT22-error-type.json",{"type":type(e).__name__,"phase":phase})
    result="HOLD_"+phase+"_ERROR"
print("BT22_"+result)

'@
$f=Join-Path $run 'compare.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run 2> (Join-Path $run 'stderr.txt'))
$code='BT22_HOLD_READOUT_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^BT22_[A-Z0-9_]{3,83}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
