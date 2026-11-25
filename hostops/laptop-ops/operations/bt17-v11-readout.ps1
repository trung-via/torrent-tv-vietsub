# BT23: replay exact V13.1 evidence gate on BT20 retained output and synthetic negatives.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('bt23-v13-1-replay-'+$rq.nonce)
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
os_hosts={'www.opensubtitles.org','opensubtitles.org'}
def filter_gate(outputs,artifacts):
    def url(v):
        if not isinstance(v,str) or not v:return None
        try:u=urllib.parse.urlsplit(urllib.parse.urljoin("https://www.opensubtitles.org/",v))
        except ValueError:return None
        return u if u.scheme=="https" and u.hostname in (os_hosts|{"dl.opensubtitles.org"}) else None
    def sid(v):
        u=url(v)
        m=re.search(r"/(?:subtitles|download/sub|subtitleserve/sub)/(\d+)(?:/|$)",u.path) if u else None
        return m[1] if m else ""
    def lang_en(v):
        return isinstance(v,str) and " ".join(v.casefold().split()) in {"english","en","eng","flag en"}
    def docs(v):
        if isinstance(v,dict):return [v]
        if not isinstance(v,str):return []
        blocks=re.findall(r"(?s)\x60\x60\x60(?:json)?\s*(\{.*?\})\s*\x60\x60\x60",v) or [v.strip()]
        result=[]
        for block in blocks:
            try:x=json.loads(block)
            except (ValueError,TypeError):continue
            if isinstance(x,dict):result.append(x)
        return result
    groups={};details={};clicks=[]
    for out in outputs:
        if out.get("error") or out.get("tool")!="evaluate_script":continue
        for d in docs(out.get("output")):
            u=url(d.get("url"))
            event=out["event"]
            did=sid(d.get("url"))
            if did and d.get("btnVisible") is True and isinstance(d.get("fieldsetText"),str) and d["fieldsetText"] and sid(d.get("downloadHref"))==did:
                details.setdefault(did,[]).append(event)
            if d.get("clicked") is True:
                cid=sid(d.get("pageUrl"))
                if cid and str(d.get("id"))==cid and sid(d.get("href"))==cid and "downloaderChecked" in d and d["downloaderChecked"] in (False,None):
                    clicks.append((cid,event))
            if not u:continue
            heading=str(d.get("heading",""))
            if not re.search(r"(?:^|/)sublanguageid-eng(?:/|$)",u.path) or not re.search(r"\benglish\b",heading,re.I):continue
            total=d.get("total_english"); rows=d.get("rows"); nxt=d.get("has_next")
            if type(nxt) is not bool or not isinstance(rows,list) or not rows:continue
            found={sid(x.get("href")) for x in rows if isinstance(x,dict) and lang_en(x.get("lang"))}-{""}
            if len(found)!=len(rows):continue
            key=re.sub(r"/offset-\d+","",u.path)
            g=groups.setdefault(key,{"ids":set(),"totals":set(),"last":False,"events":[],"bad_count":False,"release_groups":{},"release_labels":{},"pagination_reports":[]})
            g["ids"].update(found);g["last"]|=not nxt;g["events"].append(event);g["pagination_reports"].append({"event":event,"has_next":nxt,"next_href":d.get("next_href")})
            for row in rows:
                if isinstance(row,dict) and isinstance(row.get("release"),str) and row["release"].strip().casefold() not in ("","unknown","null"):
                    g["release_labels"][sid(row.get("href"))]=" ".join(row["release"].casefold().split())
                if isinstance(row,dict) and isinstance(row.get("release_group"),str) and row["release_group"].strip().casefold() not in ("","unknown","null"):
                    g["release_groups"][sid(row.get("href"))]=row["release_group"].strip().casefold()
            page_title=d.get("page_title")
            match=re.search(r"\bEnglish\s*\|\s*(\d+)\s+subtitles?\s*$",page_title,re.I) if isinstance(page_title,str) else None
            if type(total) is int and 0<total<=500 and match and int(match[1])==total and d.get("count_scope")=="filtered_results" and d.get("count_label")==page_title:g["totals"].add(total)
            else:g["bad_count"]=True
    count_matched=[g for g in groups.values() if not g["bad_count"] and g["totals"]=={len(g["ids"])}]
    complete=[g for g in count_matched if g["last"]]
    count_ok=len(count_matched)==1
    list_ok=len(complete)==1
    chosen="";click_ok=False;compared_groups=0;compared_details=0;compared_labels=0;missing_group=0
    if len(clicks)==1:
        chosen,event=clicks[0]
        matching=[g for g in groups.values() if chosen in g["ids"] and any(max(g["events"])<x<event for x in details.get(chosen,[]))]
        click_ok=len(matching)==1
        if click_ok:
            group=matching[0]
            eligible={candidate for candidate,events in details.items() if candidate in group["ids"] and any(max(group["events"])<x<event for x in events)}
            compared_details=len(eligible)
            compared_groups=len({group["release_groups"][candidate] for candidate in eligible if candidate in group["release_groups"]})
            compared_labels=len({group["release_labels"][candidate] for candidate in eligible if candidate in group["release_labels"]})
            missing_group=len(eligible-set(group["release_groups"]))
    ids={sid(x) for x in artifacts[0].get("candidate_refs",[])}-{""} if len(artifacts)==1 and artifacts[0].get("copied_to_job") is True else set()
    download_ok=bool(click_ok and ids=={chosen})
    return {"accepted":bool(list_ok and click_ok and download_ok),"reason":"ENGLISH_LIST_AND_DOWNLOAD_BOUND" if list_ok and download_ok else "DOWNLOAD_BOUND_LIST_COVERAGE_HOLD" if download_ok else "DOWNLOAD_UNVERIFIED" if click_ok else "CLICK_UNBOUND" if list_ok else "LIST_COVERAGE_UNVERIFIED","english_list_verified":list_ok,"scoped_count_matches_unique_rows":count_ok,"pagination_terminal_verified":list_ok,"english_candidates":len(complete[0]["ids"]) if list_ok else 0,"english_rows_observed":len(next(iter(groups.values()))["ids"]) if len(groups)==1 else 0,"ordinary_click_bound":click_ok,"download_verified":download_ok,"detail_candidates":len(details),"distinct_release_groups_compared":compared_groups,"candidate_details_compared_before_click":compared_details,"distinct_observed_release_labels_compared":compared_labels,"compared_candidates_missing_group":missing_group,"release_compatibility_verified":False}
def qa():
    global phase
    phase="REPORT"
    source="5c01bbd07d767c2b69339ad0eaea79034bb040da"
    p=root/"bt20-hydrogen-opensubtitles-cae5bf1fc2a24c61a862999da0bc2e69"
    r=obj(p/"BRAIN_TEACHER_REPORT.json")
    assert r["source_commit"]==source and len(srt(p,r,source))==2398
    old=r["filter_gate"]
    phase="REPLAY"
    result=filter_gate(r["tool_outcomes"],r["artifacts"])
    assert old["download_verified"] is True and old["english_list_verified"] is False
    assert result["download_verified"] is True and result["scoped_count_matches_unique_rows"] is True
    assert result["candidate_details_compared_before_click"]==2
    assert result["english_list_verified"] is False
    phase="REGRESSION"
    def out(event,data):return {"event":event,"tool":"evaluate_script","output":data}
    title="Fixture subtitles English | 2 subtitles"
    row={"url":"https://www.opensubtitles.org/en/search/sublanguageid-eng/moviename-fixture","heading":"Fixture English","page_title":title,"total_english":2,"count_scope":"filtered_results","count_label":title,"has_next":False,"next_href":None,"rows":[{"href":"/en/subtitles/111/fixture-en","lang":"flag en","release":"fixture release alpha","release_group":"alpha"},{"href":"/en/subtitles/222/fixture-en","lang":"english","release":"fixture release beta","release_group":"beta"}]}
    def detail(n):return {"url":f"https://www.opensubtitles.org/en/subtitles/{n}/fixture-en","btnVisible":True,"fieldsetText":"Visible ordinary download","downloadHref":f"/en/subtitleserve/sub/{n}"}
    click={"clicked":True,"pageUrl":"https://www.opensubtitles.org/en/subtitles/111/fixture-en","id":"111","href":"/en/subtitleserve/sub/111","downloaderChecked":False}
    artifact=[{"copied_to_job":True,"candidate_refs":["/en/download/sub/111"]}]
    def test(rows=row,art=artifact,clicked=click):
        return filter_gate([out(1,rows),out(2,detail(222)),out(3,detail(111)),out(4,clicked)],art)
    checks={
        "complete":test()["accepted"] and test()["candidate_details_compared_before_click"]==2 and test()["distinct_release_groups_compared"]==2,
        "pagination_conflict":not test(dict(row,has_next=True))["accepted"] and test(dict(row,has_next=True))["scoped_count_matches_unique_rows"] and test(dict(row,has_next=True))["download_verified"],
        "bad_count":not test(dict(row,total_english=9999999))["scoped_count_matches_unique_rows"],
        "no_artifact":not test(art=[])["download_verified"],
        "wrong_artifact":not test(art=[{"copied_to_job":True,"candidate_refs":["/en/download/sub/222"]}])["download_verified"],
        "wrong_click":not test(clicked=dict(click,id="222"))["ordinary_click_bound"],
        "missing_group":test(dict(row,rows=[dict(row["rows"][0],release_group="unknown"),row["rows"][1]]))["candidate_details_compared_before_click"]==2 and test(dict(row,rows=[dict(row["rows"][0],release_group="unknown"),row["rows"][1]]))["compared_candidates_missing_group"]==1
    }
    save("BRAIN_BT23_REPLAY.json",{"schema":"BT23_V13_1_REPLAY_V1","source":source,"before":old,"after":result,"checks":checks,"limitations":"Count matching does not prove terminal pagination. Distinct detail IDs or observed release labels do not prove distinct release groups or absolute quality. No provider calls."})
    assert all(checks.values())
    return f"T{sum(checks.values())}C{int(result['scoped_count_matches_unique_rows'])}E{int(result['english_list_verified'])}B{int(result['ordinary_click_bound'])}D{result['candidate_details_compared_before_click']}L{result['distinct_observed_release_labels_compared']}Q{result['distinct_release_groups_compared']}U{result['compared_candidates_missing_group']}"
try:
    result=qa()
except Exception as e:
    save("BT23-error-type.json",{"type":type(e).__name__,"phase":phase})
    result="HOLD_"+phase+"_ERROR"
print("BT23_"+result)

'@
$f=Join-Path $run 'compare.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run 2> (Join-Path $run 'stderr.txt'))
$code='BT23_HOLD_READOUT_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^BT23_[A-Z0-9_]{3,83}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
