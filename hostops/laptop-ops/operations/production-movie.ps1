# Explicit title request; one existing G2 job, no Library precheck. Play searches the existing open-license catalog.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('OwnerBridge\backups\production-movie-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='PRODUCTION_MOVIE_LOCAL_ERROR'
try {
$py=@'
import ast,hashlib,json,os,pathlib,re,shutil,subprocess,sys,time,urllib.request,difflib
root,run,spool=map(pathlib.Path,sys.argv[1:4])
nonce=sys.argv[4]
owner=root/"OwnerBridge"; app=owner/"app"; d2=app/"poc/p2-sub-discovery"; launcher=owner/"start-owner-session-agent.ps1"
inbox=owner/"inbox"; state=root/"P2/auto-lean120-state"; cache=root/"subtitle-trials"
base="b0e0cba86a09a7353c416536088d666363f3676c"; head="47c265fc908171ab18bb0707b2e26b014fb39d40"
new={"agy_owner_warm_session.py":"9cbc45c643d99cc9655fe9a7357eafd07cd227d0","owner_g2_discovery.py":"2707298aaa10e38c79f44505a6853ed31336ff0d","owner_g2_submit.py":"196da5a5e560faa9f780428073e67a75e956d73b","owner_movie_handoff.py":"0e5d351af58d089bd53d3fd78b4a6f46509ecbbb"}
shared={"agy_v13_native_producer.py":("20e9c725bce400593ae9a5ba27eda19f2aed797f","cfd8af916f73eff84cbb46ca75f0eab184540641"),"owner_p3_p4_runtime.py":("f8b6aa4b22647190e372d91f5bda045e7f17a326","33277f5ea67cabf95cb096ba87a6c2c659bfb6e1"),"owner_session_bridge.py":("6c0d14c66e401f5cdb9ac0ccd2974208355b167f","3b6faaeb4481ea8c1a06b0bcd777dbdad336070e")}
class Hold(Exception):pass
def need(ok,reason):
    if not ok:raise Hold(reason)
def blob(b):return hashlib.sha1(b"blob "+str(len(b)).encode()+b"\0"+b).hexdigest()
def norm(b):return b.replace(b"\r\n",b"\n")
def ps(s,timeout=20):
    p=subprocess.run(["pwsh","-NoProfile","-NonInteractive","-Command","$ErrorActionPreference='Stop';"+s],capture_output=True,encoding="utf-8",errors="replace",timeout=timeout)
    need(p.returncode==0,"TASK_OR_PS_FAILED")
    return p.stdout.strip()
def q(s):return "'"+str(s).replace("'","''")+"'"
def write_doc(name,v):(run/name).write_text(json.dumps(v,indent=2),encoding="utf-8")
def safe_file(p):
    need(p.is_file() and not p.is_symlink() and not (p.stat().st_file_attributes & 1024),"FILE_IDENTITY")
    return p.read_bytes()
def source(ref,name,expected):
    url=f"https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/{ref}/poc/p2-sub-discovery/{name}"
    with urllib.request.urlopen(url,timeout=25) as f:b=f.read(2_000_000)
    need(blob(b)==expected,"SOURCE_HASH")
    return b
def task_info():
    return json.loads(ps(r"""$t=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\';$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;$u=[string]$t.Principal.UserId;if($u -notmatch '^S-1-'){$u=([Security.Principal.NTAccount]::new($u)).Translate([Security.Principal.SecurityIdentifier]).Value};if($u -cne $sid -or $t.Principal.LogonType -ine 'Interactive' -or @($t.Actions).Count -ne 1){throw 'TASK_IDENTITY'};$a=$t.Actions[0];if([IO.Path]::GetFileName([string]$a.Execute) -ine 'pwsh.exe' -or [string]$a.Arguments -notmatch '^(-NoLogo\s+-NoProfile\s+-NonInteractive\s+-File\s+)' -or ([string]$a.Arguments -replace '^(-NoLogo\s+-NoProfile\s+-NonInteractive\s+-File\s+)','').Trim('"') -ine """+q(launcher)+r"""){throw 'TASK_ACTION'};([pscustomobject]@{state=([string]$t.State).ToUpperInvariant();enabled=[bool]$t.Settings.Enabled}|ConvertTo-Json -Compress)"""))
def task():return task_info()["state"]
def read_doc(p):
    return json.loads(safe_file(p).decode("utf-8-sig"))
def matching(source_commit,reason):
    found=set()
    for folder in (spool/"History",spool/"Receipts"):
        for p in folder.glob("receipt*.json"):
            try:r=read_doc(p)
            except (OSError,ValueError,Hold):continue
            n=r.get("nonce","")
            if r.get("source_commit")!=source_commit or r.get("result")!="SUCCESS" or not re.fullmatch(r"[a-f0-9]{32}",str(n)):continue
            s=read_doc(spool/"Receipts"/("odyssey-stage-"+n+".json"))
            if s.get("nonce")==n and s.get("reason")==reason:found.add(n)
    need(len(found)==1,"PRIOR_RECEIPT")
    return next(iter(found))
def apply_context(old,baseline,target):
    # Apply only exact unique G2 hunks on the installed text. No fuzzy merge.
    old,baseline,target=map(norm,(old,baseline,target))
    if old==baseline:return target
    if old==target:return old
    lines=old.splitlines(keepends=True); b=baseline.splitlines(keepends=True); t=target.splitlines(keepends=True)
    groups=list(difflib.SequenceMatcher(None,b,t,autojunk=False).get_grouped_opcodes(3))
    for group in groups:
        start,end=group[0][1],group[-1][2]; ts,te=group[0][3],group[-1][4]
        before=b[start:end]; after=t[ts:te]
        hits=[i for i in range(len(lines)-len(before)+1) if lines[i:i+len(before)]==before]
        need(len(hits)==1,"SHARED_CONTEXT_CONFLICT")
        i=hits[0];lines[i:i+len(before)]=after
    return b"".join(lines)
def replace(p,b):
    tmp=p.with_name("."+p.name+".g2-"+nonce+".tmp")
    with tmp.open("xb") as f:f.write(b);f.flush();os.fsync(f.fileno())
    os.replace(tmp,p)
def main():
    # The runner supplies data only. No new script, no global G1 idle gate.
    request=read_doc(spool/"Requests"/("movie-"+nonce+".json"))
    need(set(request)=={"schema","request_id","mode","year","title"} and request["schema"]=="TTV-PRODUCTION-MOVIE-V1" and request["request_id"]==nonce,"INPUT_BIND")
    mode,title,year=request["mode"],request["title"],request["year"]
    need(mode in ("search","play") and isinstance(title,str) and 1<=len(title)<=160 and type(year) is int and 1900<=year<=2100,"INPUT")
    query={"title":title,"year":year,"resolution":"1080p"}
    known_open_release_hashes={("Big Buck Bunny",2008):"dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c",("Cosmos Laundromat",2015):"c9e15763f722f23e98a29decdfae341b98d53056"}
    if mode=="play":
        expected=known_open_release_hashes.get((title,year))
        # No fixture-title admission gate. Only search the existing curated
        # open-license catalog. The native producer must observe a matching
        # release in that source; no authority is inferred for other sites.
        source_url="https://webtorrent.io/free-torrents"
        query.update(select_release=True,media_authorized=True,play=True)
        if expected is not None:query["verified_release_hash"]=expected
        schema="TTV-OWNER-G2-CONCIERGE-V1"
    else:
        source_url="https://ext.to/"
        query.update(select_release=False,media_authorized=False,play=False)
        schema="TTV-OWNER-G2-METADATA-V1"
    payload={"schema":schema,"request_id":nonce,"authorized_source":True,"source_url":source_url,"queries":[query]}
    req=run/"private-request.json";req.write_text(json.dumps(payload),encoding="utf-8")
    write_doc("submit-intent.json",{"request_id":nonce,"mode":mode})
    p=subprocess.run([sys.executable,"-B",str(d2/"owner_g2_submit.py"),"--owner-root",str(owner),"--request-file",str(req)],capture_output=True,timeout=20)
    need(p.returncode==0 and b"OWNER_G2_SUBMIT_ACCEPTED_NOT_RESULT" in p.stdout,"SUBMIT_UNVERIFIED_NO_REPLAY")
    write_doc("submitted.json",{"request_id":nonce})
    receipt=inbox/("g2-"+nonce+".receipt.json")
    for _ in range(240):
        if receipt.is_file():
            v=read_doc(receipt)
            need(v.get("schema")=="TTV-OWNER-G2-RECEIPT-V1" and v.get("request_id")==nonce,"RECEIPT_BIND")
            if v.get("status")!="COMPLETE":
                reason=v.get("reason","UNKNOWN")
                return "PRODUCTION_MOVIE_HOLD_"+(reason if isinstance(reason,str) and re.fullmatch(r"[A-Z0-9_]{1,60}",reason) else "UNKNOWN")
            rows=v.get("results",[])
            need(len(rows)==1 and rows[0].get("owner_request_id")==nonce,"RESULT_BIND")
            status=rows[0].get("status","UNKNOWN")
            need(isinstance(status,str) and re.fullmatch(r"[A-Z0-9_]{1,50}",status),"RESULT_STATUS")
            if mode=="search":return "PRODUCTION_MOVIE_METADATA_"+status
            if status!="SELECTION_READY":return "PRODUCTION_MOVIE_SELECTION_"+status
            need(v.get("selection_published") is True and v.get("library_status")=="LIBRARY_READY","LIBRARY_NOT_READY_NO_REPLAY")
            library=read_doc(spool/"Receipts"/("g2-"+nonce+".library.json"))
            selected=rows[0].get("selection")
            need(isinstance(selected,dict) and selected.get("title")==title and selected.get("source_authorized") is True and selected.get("media_authorized") is True and selected.get("release_matched") is True,"SELECTION_BIND")
            chosen=selected.get("expected_hash")
            need(isinstance(chosen,str) and re.fullmatch(r"[a-f0-9]{40}",chosen) and (expected is None or chosen==expected),"SELECTION_HASH_BIND")
            need(library.get("schema")=="TTV-G2-LIBRARY-RECEIPT-V1" and library.get("request_id")==nonce and library.get("status")=="LIBRARY_READY" and library.get("play") is True and library.get("auto_vietsub") is True and library.get("torrent_hash")==chosen and type(library.get("file_id")) is int,"LIBRARY_BIND")
            return "PRODUCTION_MOVIE_LIBRARY_READY"
        time.sleep(1)
    return "PRODUCTION_MOVIE_SUBMITTED_PENDING_NO_REPLAY"
try: print(main())
except Hold as e: print("PRODUCTION_MOVIE_HOLD_"+str(e))
except Exception:
    import traceback
    (run/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("PRODUCTION_MOVIE_LOCAL_ERROR")
'@
$f=Join-Path $run 'deploy.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $run $spool $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
}catch{[IO.File]::WriteAllText((Join-Path $run 'host-private-error.txt'),($_|Out-String),[Text.UTF8Encoding]::new($false))}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
