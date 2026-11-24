# TR-TTV.04c exact blind Teacher recovery, no provider or browser actions.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('tr-ttv-04c-recovery-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$py=@'
import sys,pathlib,os,json,re,sqlite3,zipfile,urllib.parse,hashlib
root,run=map(pathlib.Path,sys.argv[1:])
def read(p):
    if not p.is_file() or p.is_symlink() or p.stat().st_size>16777216:return ""
    return p.read_text(encoding="utf-8-sig",errors="replace")
def probe():
    history=pathlib.Path(os.environ["ProgramData"])/"TorrentTVVietsub"/"LaptopHostOps"/"History"
    hits=[]
    for f in history.glob("receipt-*.json"):
        try:
            q=json.loads(read(f))
            if q.get("source_commit")=="676eca7bdb6782b61b1adb62d42ae80ba9043d5d" and q.get("operation")=="agy-native-browser-readout-1124" and q.get("result")=="SUCCESS" and re.fullmatch(r"[a-f0-9]{32}",q.get("nonce","")):hits.append(q["nonce"])
        except (ValueError,TypeError,OSError):pass
    if len(hits)!=1:return "TR04AR_PRIOR_HOLD"
    p=root/("tr-ttv-04c-blind-"+hits[0])
    report=json.loads(read(p/"BRAIN_TEACHER_REPORT.json"))
    raw=read(p/"agy-stdout.jsonl");err=read(p/"agy-stderr.txt")
    records=[]
    for line in raw.splitlines():
        try:
            x=json.loads(line)
            if isinstance(x,dict):records.append(x)
        except ValueError:pass
    excluded={"prompt","input","arguments","thinking","reasoning","thought","signature","instructions","system","user","env","credentials"}
    def leaves(x,path=()):
        if isinstance(x,dict):
            for k,v in x.items():
                if k.lower() not in excluded:yield from leaves(v,path+(k,))
        elif isinstance(x,list):
            for i,v in enumerate(x):yield from leaves(v,path+(str(i),))
        elif isinstance(x,str):yield path,x
    texts=[];final=[];denials=[];mask=0;filedenial=0;unknown=0;answer={}
    tools=("list_pages","new_page","select_page","navigate_page","take_snapshot","click","fill","press_key","wait_for","close_page","evaluate_script","get_network_request","list_network_requests","handle_dialog","upload_file","hover","press")
    denial=r"permission check failed|user denied permission|auto-denied|permission denied|not permitted"
    def find_answer(v):
        if isinstance(v,dict):
            if isinstance(v.get("selection"),dict) and isinstance(v.get("result"),dict):return v
            for k,x in v.items():
                if k.lower() in excluded:continue
                z=find_answer(x)
                if z:return z
        elif isinstance(v,list):
            for x in v:
                z=find_answer(x)
                if z:return z
        return {}
    for i,e in enumerate(records):
        kind=e.get("event",e.get("type",""))
        z=find_answer(e)
        if z:answer=z
        for path,value in leaves(e):
            key=re.sub(r"[^a-z0-9]","",(path[-1] if path else "").lower())
            # Preserve full user-facing response and tool results, not private reasoning.
            if key in {"text","response","final","finalresponse","message","output","content","result","error","title","name","status","tooloutput","toolresult","toolname","type"}:
                texts.append({"event":i,"kind":kind,"field":path,"value":value})
                if kind=="result":final.append(value)
                if not answer and key in {"text","response","final","finalresponse","message","output","content","result"}:
                    for match in re.finditer(r"\{",value):
                        try:
                            val,_=json.JSONDecoder().raw_decode(value[match.start():])
                            z=find_answer(val)
                            if z:answer=z;break
                        except ValueError:pass
            if re.search(denial,value,re.I):
                names=re.findall(r"ttv-browser[/\\]([a-z_]+)",value,re.I)
                for name in names:
                    if name.lower() in tools:mask|=1<<tools.index(name.lower())
                    else:unknown=1
                if re.search(r"write_file|read_file|run_command|shell|terminal|save_file",value,re.I):filedenial=1
                if not names and not filedenial:unknown=1
                denials.append({"event":i,"field":path,"text":value})
    if re.search(denial,err,re.I):denials.append({"event":"stderr","text":err})
    sel=answer.get("selection",{}) if answer else report.get("selection",{})
    rr=answer.get("result",{}) if answer else report.get("reported_result",{})
    recipe=answer.get("teacher_recipe",{}) if answer else report.get("teacher_recipe",{})
    # Reconcile physical acquisition independently of the final JSON parser.
    # Only use the unique fresh Chrome profile created by this exact job.
    hdb=p/"ChromeBlindProfile"/"Default"/"History"
    downloads=[];dbok=0
    if hdb.is_file():
        try:
            con=sqlite3.connect(hdb.resolve().as_uri()+"?mode=ro",uri=True,timeout=3)
            con.row_factory=sqlite3.Row
            cols={x[1] for x in con.execute("pragma table_info(downloads)")}
            want=[x for x in ("id","current_path","target_path","state","received_bytes","total_bytes","start_time","end_time","tab_url","referrer","mime_type") if x in cols]
            for row in con.execute("select "+",".join(want)+" from downloads order by id"):
                item=dict(row);item["chain"]=[x[0] for x in con.execute("select url from downloads_url_chains where id=? order by chain_index",(row["id"],))]
                downloads.append(item)
            con.close();dbok=1
        except (OSError,sqlite3.Error,ValueError):pass
    def cues(f):
        try:
            if f.suffix.lower()==".srt":
                if f.stat().st_size>10000000:return 0
                blobs=[f.read_bytes()]
            elif f.suffix.lower()==".zip":
                with zipfile.ZipFile(f) as z:
                    blobs=[z.read(i) for i in z.infolist()[:100] if i.filename.lower().endswith(".srt") and 0<i.file_size<=2000000 and not i.flag_bits&1]
            else:return 0
            return max((len(re.findall(rb"(?m)^\d{2}:\d{2}:\d{2}[,.]\d{3}\s+-->\s+\d{2}:\d{2}:\d{2}[,.]\d{3}",v)) for v in blobs),default=0)
        except (OSError,ValueError,RuntimeError,zipfile.BadZipFile):return 0
    paths={}
    local=p/"browser-downloads"
    if local.is_dir():
        for f in local.iterdir():
            if f.is_file() and not f.is_symlink() and f.suffix.lower() in (".srt",".zip"):paths[str(f.resolve())]={"path":str(f.resolve()),"in_fresh_directory":True,"history_completed":False,"urls":[]}
    for row in downloads:
        if row.get("state")!=1:continue
        for name in ("target_path","current_path"):
            if not row.get(name):continue
            f=pathlib.Path(row[name])
            if not f.is_absolute() or not f.is_file() or f.is_symlink() or f.suffix.lower() not in (".srt",".zip"):continue
            f=f.resolve()
            # Exact fresh profile's completed download record supplies provenance.
            key=str(f);entry=paths.setdefault(key,{"path":key,"in_fresh_directory":f.is_relative_to(local.resolve()),"history_completed":False,"urls":[]})
            entry["history_completed"]=True
            entry["urls"]+=row.get("chain",[])+[row.get("tab_url") or "",row.get("referrer") or ""]
    for item in paths.values():
        f=pathlib.Path(item["path"]);item["cues"]=cues(f);item["bytes"]=f.stat().st_size
        try:
            with open(str(f)+":Zone.Identifier","r",encoding="utf-8",errors="replace") as z:
                d=dict(v.split("=",1) for v in z.read(8192).splitlines() if "=" in v)
            item["urls"] += [d.get("HostUrl",""),d.get("ReferrerUrl","")]
        except OSError:pass
        item["origin_verified"]=any(urllib.parse.urlsplit(u).scheme=="https" and urllib.parse.urlsplit(u).hostname in ("dl.opensubtitles.org","www.opensubtitles.org","opensubtitles.org","www.opensubtitles.com","opensubtitles.com") for u in item["urls"] if isinstance(u,str))
        item["sha256"]=hashlib.sha256(f.read_bytes()).hexdigest() if 0<item["bytes"]<=10000000 else ""
    good=[v for v in paths.values() if v["cues"]>0]
    verified=[v for v in good if v["origin_verified"] and (v["history_completed"] or v["in_fresh_directory"])]
    # Private report stays on Owner disk. No raw logs or subtitles in public receipts.
    summary={"source_commit":"676eca7bdb6782b61b1adb62d42ae80ba9043d5d","event_count":len(records),"final_response":final,"public_facing_event_text":texts,"denials":denials,"structured_answer":answer,"selection":sel,"result":rr,"teacher_recipe":recipe,"cli_stderr":err,"chrome_download_history":downloads,"file_evidence":list(paths.values()),"history_read":bool(dbok),"original_verifier":report.get("verified_acquisition",{}),"playback_sync_verified":False}
    (run/"BRAIN_BLIND_RECOVERY.json").write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding="utf-8")
    markdown="# Resident Evil Blind Teacher - recovered response\n\n## Final response\n\n"+("\n\n".join(final) or "[No final response field recovered]")+"\n\n## All user-facing event text and tool outcomes\n\n"+json.dumps(summary,ensure_ascii=False,indent=2)
    (run/"BRAIN_BLIND_RECOVERY.md").write_text(markdown,encoding="utf-8")
    target=pathlib.Path.home()/"Downloads"/"TTV_Resident_Evil_Blind_Teacher_Report.md"
    exported=0
    try:
        with target.open("x",encoding="utf-8") as f:f.write(markdown)
        exported=1
    except OSError:pass
    cc=max((v["cues"] for v in good),default=0)
    return f"TR04Z_N{len(records)}_H{dbok}F{len(good)}V{len(verified)}C{min(cc,99999)}J{int(bool(answer))}R{int(bool(recipe))}A{int(bool(final))}D{mask:X}W{filedenial}U{unknown}E{exported}"

try:print(probe())
except Exception as e:
    (run/"readout-error.txt").write_text(type(e).__name__+": "+str(e),encoding="utf-8")
    print("TR04AR_LOCAL_ERROR")
'@
$f=Join-Path $run 'control.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $run 2> (Join-Path $run 'python-stderr.txt'))
$code='TR04AR_LOCAL_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,65}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
