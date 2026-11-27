Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'NONCE_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('NativeBrowserTest\g2-sintel-resume-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$head='9a110724cab7b184ca56bd171a5ccdebf469b9b5'
$code='G21_V33_LOCAL_ERROR'
try {
    $py=@'
import pathlib,sys,json,os,re,subprocess,shutil,urllib.request,hashlib,time
root,run,spool=map(pathlib.Path,sys.argv[1:4])
head=sys.argv[4];nonce=sys.argv[5]
def write(p,x):
    p.write_text(json.dumps(x,ensure_ascii=True,indent=2),encoding="utf-8")
def ps(cmd,timeout=15):
    return subprocess.run(["pwsh","-NoProfile","-NonInteractive","-Command",cmd],
        capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=timeout,check=True).stdout.strip()
def task_state():
    return ps("(Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -ErrorAction Stop).State.ToString()")
def pages():
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open("http://127.0.0.1:9555/json/list",timeout=3) as f:
        return [p for p in json.load(f) if p.get("type")=="page"]
def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else "MISSING"
def main():
    def read(p,limit=4194304):
        if p.is_symlink() or not p.is_file() or p.stat().st_size>limit:return {}
        return json.loads(p.read_text(encoding="utf-8-sig"))
    matches=[]
    for directory in (spool/"History",spool/"Receipts"):
        for p in directory.glob("receipt*.json"):
            d=read(p,4096);n=d.get("nonce","")
            if d.get("source_commit")!="02a02788a3d06fc28b4f7b023e0fc0294bb7a74d" or d.get("result")!="SUCCESS" or not re.fullmatch("[a-f0-9]{32}",str(n)):continue
            q=read(spool/"History"/("request-"+n+".json"),4096) or read(spool/"Requests"/"request.json",4096)
            # Latest request may already have been archived by dispatcher.
            st=read(spool/"Receipts"/("odyssey-stage-"+n+".json"),4096)
            if q.get("nonce")==n and q.get("source_commit")==d["source_commit"] and st.get("nonce")==n and st.get("reason")=="G2_SINTEL_NO_EXACT_MATCH_REPORTED_MS60488":matches.append(n)
    matches=list(set(matches))
    if len(matches)!=1:return "G2_READOUT_PRIOR_HOLD"
    n=matches[0];old=root/"NativeBrowserTest"/("g2-sintel-library-once-"+n)
    acc=read(old/"ACCEPTANCE.json");rec=acc.get("receipt",{})
    if acc.get("head")!=head or rec.get("request_id")!=n or len(rec.get("results",[]))!=1:return "G2_READOUT_BINDING_HOLD"
    row=rec["results"][0];tid=row.get("turn_request_id","")
    if row.get("status")!="NO_EXACT_MATCH_REPORTED" or not re.fullmatch("[a-f0-9]{32}",tid):return "G2_READOUT_RESULT_HOLD"
    trace=old/"isolated-cache"/".native-v13"/("g2-"+n)/tid/"agy-stdout.jsonl"
    if not trace.is_file() or trace.is_symlink() or trace.stat().st_size>16777216:return "G2_READOUT_TRACE_HOLD"
    finals=[]
    for line in trace.read_text(encoding="utf-8").splitlines():
        try: ev=json.loads(line)
        except ValueError:continue
        if ev.get("event")=="result" and isinstance(ev.get("result"),dict):
            response=ev["result"].get("response")
            if isinstance(response,str):
                response=response.strip()
                fence=re.fullmatch(r"\x60{3}(?:json)?\s*(.*?)\s*\x60{3}",response,re.S)
                finals.append(json.loads(fence[1] if fence else response))
    if len(finals)!=1:return "G2_READOUT_FINAL_HOLD"
    payload=finals[0];rows=payload.get("candidates")
    if payload.get("request_id")!=tid or not isinstance(rows,list):return "G2_READOUT_PAYLOAD_HOLD"
    counts=dict(c=len(rows),title=0,year=0,string=0,missing=0,other=0,both=0,link=0)
    for x in rows:
        if not isinstance(x,dict):continue
        title=x.get("title");year=x.get("year")
        match=isinstance(title,str) and " ".join(title.casefold().split())=="sintel"
        counts["title"]+=int(match)
        counts["year"]+=int(type(year) is int and year==2010)
        counts["string"]+=int(year=="2010")
        counts["missing"]+=int(year is None)
        counts["other"]+=int(year is not None and year!="2010" and not(type(year) is int and year==2010))
        counts["both"]+=int(match and type(year) is int and year==2010)
        counts["link"]+=int(isinstance(x.get("link"),str) and x["link"].startswith("magnet:?"))
    journal=read(old/"OWNER_RECOVERY.json")
    selected=payload.get("selected")
    counts["pick"]=int(isinstance(selected,dict) and isinstance(selected.get("link"),str))
    counts["handoff"]=len(acc.get("handoffs",[]))
    counts["restored"]=int(journal.get("stage")=="RESTORED" and acc.get("restored") is True)
    # Resume from the original AGY result only. The exact source release
    # identity was independently established in the official WebTorrent FAQ
    # and Blender's official 2010 film record, not inferred from AGY output.
    if counts["c"]!=1 or counts["title"]!=1 or counts["missing"]!=1 or counts["handoff"]!=0 or counts["restored"]!=1:
        return "G2_RESUME_PRIOR_EFFECT_HOLD"
    for p in (root/"NativeBrowserTest").glob("g2-sintel-resume-*"):
        if p!=run and (p/"resume-attempt.json").exists():return "G2_RESUME_ALREADY_ATTEMPTED"
    if (spool/"Receipts"/("g2-"+n+".library.json")).exists():return "G2_RESUME_PRIOR_LIBRARY_RECEIPT"
    prior=old/"isolated-owner"/"inbox"
    if (prior/("g2-"+n+".selected.json")).exists() or (prior/("g2-"+n+".library.json")).exists():return "G2_RESUME_PRIOR_SELECTION_EFFECT"
    candidate=old/"candidate"
    if subprocess.check_output(["git","-C",str(candidate),"rev-parse","HEAD"],text=True).strip()!=head:return "G2_RESUME_ORIGINAL_SOURCE_HOLD"
    if subprocess.check_output(["git","-C",str(candidate),"status","--porcelain","--untracked-files=no"],text=True).strip():return "G2_RESUME_ORIGINAL_DIRTY"
    # Fetch only the corrected file, verify Git blob; do not install or start provider.
    url="https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/c9f846a17eb6d1f97624a4efb901840523e6e0c1/poc/p2-sub-discovery/owner_g2_discovery.py"
    with urllib.request.urlopen(url,timeout=30) as f:
        if f.geturl()!=url:return "G2_RESUME_PATCH_REDIRECT"
        data=f.read(65537)
    if not 0<len(data)<=65536 or hashlib.sha1(b"blob "+str(len(data)).encode()+b"\0"+data).hexdigest()!="d3ad615a79fa015075ee8742f1bfb5b4258cda4b":return "G2_RESUME_PATCH_DRIFT"
    (run/"owner_g2_discovery.py").write_bytes(data)
    sys.path[:0]=[str(run),str(candidate/"poc/p2-sub-discovery"),str(candidate/"poc/p2-aisub")]
    from owner_g2_discovery import MovieQuery,_query,_selected_metadata
    from owner_movie_handoff import publish_library_receipt,_post,_listed,_file
    # Exactly one affected synthetic test before proceeding; no APK or provider.
    testurl="https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/c9f846a17eb6d1f97624a4efb901840523e6e0c1/poc/p2-sub-discovery/test_owner_g2_warm_session.py"
    with urllib.request.urlopen(testurl,timeout=30) as f:
        if f.geturl()!=testurl:return "G2_RESUME_TEST_REDIRECT"
        testdata=f.read(262145)
    if not 0<len(testdata)<=262144 or hashlib.sha1(b"blob "+str(len(testdata)).encode()+b"\0"+testdata).hexdigest()!="d2b53a30d557d2e72e42a361b88af19699c0fc11":return "G2_RESUME_TEST_DRIFT"
    (run/"test_owner_g2_warm_session.py").write_bytes(testdata)
    import unittest,io
    import test_owner_g2_warm_session
    suite=unittest.TestSuite()
    for cls in vars(test_owner_g2_warm_session).values():
        if isinstance(cls,type) and issubclass(cls,unittest.TestCase):
            method="test_authorized_selection_is_exact_top_release_and_observed_locator"
            if hasattr(cls,method):suite.addTest(cls(method))
    if suite.countTestCases()!=1:return "G2_RESUME_TEST_MISSING"
    report=io.StringIO()
    result=unittest.TextTestRunner(stream=report,verbosity=2).run(suite)
    (run/"targeted-test.txt").write_text(report.getvalue(),encoding="utf-8")
    if not result.wasSuccessful():return "G2_RESUME_TARGETED_TEST_FAIL"
    expected="08ada5a7a6183aae1e09d831df6748d566095a10"
    q=_query(MovieQuery(**dict(row["query"],verified_release_hash=expected)))
    if q.title!="Sintel" or q.year!=2010 or q.play or not q.media_authorized:return "G2_RESUME_AUTHORITY_HOLD"
    repaired=_selected_metadata(payload,q,tid,"webtorrent.io",trace)
    if repaired.get("status")!="SELECTION_READY":
        reason=repaired.get("status","UNKNOWN")
        return "G2_RESUME_"+reason if re.fullmatch("[A-Z0-9_]{1,60}",reason) else "G2_RESUME_SELECTION_HOLD"
    if repaired.get("identity_evidence")!="TRUSTED_RELEASE_HASH" or repaired["selection"]["expected_hash"]!=expected:return "G2_RESUME_IDENTITY_HOLD"
    private=run/"private";private.mkdir()
    write(run/"resume-attempt.json",{"original_request_id":n,"original_turn_id":tid,"patch":"c9f846a17eb6d1f97624a4efb901840523e6e0c1","provider_replayed":False})
    # Reuse the existing production publisher, not a hand-built selection file.
    from owner_session_bridge import _publish_g2_selection
    from dataclasses import asdict
    repaired.update(owner_request_id=n,query=asdict(q))
    if not _publish_g2_selection(private,n,q,[repaired]):return "G2_RESUME_PUBLISH_HOLD"
    already=_listed(_post({"action":"list"},5),expected)
    started=time.monotonic()
    try:
        status=publish_library_receipt(private,n)
        for _ in range(6):
            if status!="FILE_SELECTION_PENDING":break
            time.sleep(5);status=publish_library_receipt(private,n)
    except Exception as e:
        reason=str(e)
        return "G2_RESUME_"+reason if re.fullmatch("[A-Z0-9_]{1,65}",reason) else "G2_RESUME_HANDOFF_HOLD"
    if status!="LIBRARY_READY":return "G2_RESUME_"+status
    lib=read(private/("g2-"+n+".library.json"));shared=read(spool/"Receipts"/("g2-"+n+".library.json"))
    if lib!=shared or lib.get("request_id")!=n or lib.get("torrent_hash")!=expected or lib.get("play") is not False or type(lib.get("file_id")) is not int:return "G2_RESUME_RECEIPT_HOLD"
    if not _listed(_post({"action":"list"},5),expected) or _file(_post({"action":"get","hash":expected},5),expected,lib["file_id"])!=lib["file_id"]:return "G2_RESUME_READBACK_HOLD"
    elapsed=round((time.monotonic()-started)*1000)
    write(run/"RESUME_RESULT.json",{"original_request_id":n,"original_turn_id":tid,"library_receipt":lib,"handoff_ms":elapsed,"already_in_library":already,"provider_replayed":False})
    return "G2_RESUME_LIBRARY_PASS_"+("EXISTING" if already else "ADDED")+"_MS"+str(elapsed)+"_TEST1"

try:
    import urllib.parse
    print(main())
except Exception as exc:
    import traceback
    (run/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("G21_V33_LOCAL_ERROR")
'@
    $f=Join-Path $run 'v33.py'
    [IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
    $out=@(& py -3 -I -B $f $root $run $spool $head $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
    if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
} catch {
    [IO.File]::WriteAllText((Join-Path $run 'host-private-error.txt'),($_|Out-String),[Text.UTF8Encoding]::new($false))
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
