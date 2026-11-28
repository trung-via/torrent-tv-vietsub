# One authorized production Flow 3 request through installed Owner, no restart or subtitle action.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root ('OwnerBridge\backups\g2-production-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$code='G2_PROD_LOCAL_ERROR'
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
def task():
    return ps(r"""$t=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\';$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;$u=[string]$t.Principal.UserId;if($u -notmatch '^S-1-'){$u=([Security.Principal.NTAccount]::new($u)).Translate([Security.Principal.SecurityIdentifier]).Value};if($u -cne $sid -or $t.Principal.LogonType -ine 'Interactive' -or @($t.Actions).Count -ne 1){throw 'TASK_IDENTITY'};$a=$t.Actions[0];if([IO.Path]::GetFileName([string]$a.Execute) -ine 'pwsh.exe' -or [string]$a.Arguments -notmatch '^(-NoLogo\s+-NoProfile\s+-NonInteractive\s+-File\s+)' -or ([string]$a.Arguments -replace '^(-NoLogo\s+-NoProfile\s+-NonInteractive\s+-File\s+)','').Trim('"') -ine """+q(launcher)+r"""){throw 'TASK_ACTION'};[string]$t.State""").upper()
def read_doc(p):
    return json.loads(safe_file(p).decode("utf-8-sig"))
def main():
    # Reuse verified installed delta; no import test, installation or task restart.
    need(task()=="RUNNING","OWNER_NOT_RUNNING")
    h=read_doc(owner/"agent-health.json")
    pid=int(h["pid"])
    need(h["state"]=="READY" and 0<=time.time()-int(h["observed_utc_epoch"])<=30 and pid>0,"OWNER_HEARTBEAT")
    s=ps("$w=Get-CimInstance Win32_Process -Filter "+q("ProcessId="+str(pid))+";if($null -eq $w){throw 'PID'};$who=Invoke-CimMethod -InputObject $w -MethodName GetOwnerSid;if($who.ReturnValue -ne 0 -or $who.Sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or ([string]$w.CommandLine).IndexOf("+q(str(d2/"owner_p3_p4_entrypoint.py"))+",[StringComparison]::OrdinalIgnoreCase) -lt 0){throw 'PID_IDENTITY'};'OK'")
    need(s=="OK","OWNER_PID")
    matches=set()
    for folder in (spool/"History",spool/"Receipts"):
        for p in folder.glob("receipt*.json"):
            try:r=read_doc(p)
            except (OSError,ValueError,Hold):continue
            n=r.get("nonce","")
            if r.get("source_commit")!="0ecf5774c267da08b9d79659b0fae360fb14ddd5" or r.get("result")!="SUCCESS" or not re.fullmatch(r"[a-f0-9]{32}",str(n)):continue
            s=read_doc(spool/"Receipts"/("odyssey-stage-"+n+".json"))
            if s.get("nonce")==n and s.get("reason")=="G2_DEPLOY_APPLIED_START_HOLD_PENDING_1":matches.add(n)
    need(len(matches)==1,"DEPLOY_RECEIPT")
    prior=owner/"backups"/("g2-delta-"+next(iter(matches)))
    applied=read_doc(prior/"applied.json")
    names=set(new)|set(shared)|{launcher.name}
    hashes=applied.get("hashes",{})
    need(applied.get("head")==head and set(hashes)==names,"DEPLOY_MANIFEST")
    need(all(blob(safe_file(launcher if name==launcher.name else d2/name))==hashes[name] for name in names),"INSTALLED_HASH_DRIFT")
    need(not any((p/"submitted.json").exists() or (p/"submit-intent.json").exists() for p in (owner/"backups").glob("g2-production-*") if p!=run),"PRIOR_REQUEST_NO_REPLAY")
    need(not any(inbox.glob("event-*.json")) and not any(state.rglob("*.inflight")) and not any(cache.rglob("browser.pending")),"OWNER_BUSY")
    need(not any(re.fullmatch(r"g2-[a-f0-9]{32}\.json",p.name) and not p.with_suffix(".claim").exists() and not p.with_suffix(".receipt.json").exists() for p in inbox.glob("g2-*.json")),"OTHER_G2_PENDING")
    # Verify this fixture is not already in Library (one read within this request).
    req=urllib.request.Request("http://127.0.0.1:8090/torrents",data=b'{"action":"list"}',headers={"Content-Type":"application/json"},method="POST")
    with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(req,timeout=5) as f:rows=json.load(f)
    need(rows is None or isinstance(rows,list),"LIBRARY_SCHEMA")
    existing={str(x.get("hash","")).lower() for x in (rows or []) if isinstance(x,dict)}
    fixtures=[("Cosmos Laundromat",2015,"c9e15763f722f23e98a29decdfae341b98d53056","COSMOS"),("Big Buck Bunny",2008,"dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c","BUNNY")]
    candidates=[f for f in fixtures if f[2] not in existing]
    need(bool(candidates),"ALL_AUTHORIZED_FIXTURES_ALREADY_IN_LIBRARY")
    title,year,expected,fixture=candidates[0]
    payload={"schema":"TTV-OWNER-G2-SELECTION-V1","request_id":nonce,"authorized_source":True,"source_url":"https://webtorrent.io/free-torrents","queries":[{"title":title,"year":year,"resolution":"1080p","select_release":True,"media_authorized":True,"play":True,"verified_release_hash":expected}]}
    reqfile=run/"private-request.json";reqfile.write_text(json.dumps(payload),encoding="utf-8")
    # Submit through the installed official ingress. Running Owner alone consumes.
    write_doc("submit-intent.json",{"request_id":nonce,"pid":pid,"head":head})
    began=time.monotonic()
    p=subprocess.run([sys.executable,"-B",str(d2/"owner_g2_submit.py"),"--owner-root",str(owner),"--request-file",str(reqfile)],capture_output=True,timeout=20)
    need(p.returncode==0 and b"OWNER_G2_SUBMIT_ACCEPTED_NOT_RESULT" in p.stdout,"SUBMIT_UNVERIFIED_NO_REPLAY")
    write_doc("submitted.json",{"request_id":nonce,"fixture":fixture})
    receipt=inbox/("g2-"+nonce+".receipt.json")
    library=spool/"Receipts"/("g2-"+nonce+".library.json")
    for _ in range(230):
        if receipt.is_file():
            d=read_doc(receipt)
            need(d.get("schema")=="TTV-OWNER-G2-RECEIPT-V1" and d.get("request_id")==nonce,"RECEIPT_BINDING")
            if d.get("status")!="COMPLETE":
                reason=d.get("reason","UNKNOWN")
                return "G2_PROD_OWNER_HOLD_"+(reason if isinstance(reason,str) and re.fullmatch(r"[A-Z0-9_]{1,55}",reason) else "UNKNOWN")
            results=d.get("results",[])
            need(len(results)==1 and results[0].get("owner_request_id")==nonce,"RESULT_BINDING")
            row=results[0]
            if row.get("status")!="SELECTION_READY":
                status=row.get("status","UNKNOWN")
                return "G2_PROD_SELECTION_HOLD_"+(status if isinstance(status,str) and re.fullmatch(r"[A-Z0-9_]{1,55}",status) else "UNKNOWN")
            if d.get("selection_published") is not True or d.get("library_status")!="LIBRARY_READY":
                status=d.get("library_status","UNKNOWN")
                return "G2_PROD_LIBRARY_HOLD_"+(status if isinstance(status,str) and re.fullmatch(r"[A-Z0-9_]{1,55}",status) else "UNKNOWN")
            l=read_doc(library)
            need(l.get("schema")=="TTV-G2-LIBRARY-RECEIPT-V1" and l.get("request_id")==nonce and l.get("status")=="LIBRARY_READY" and l.get("play") is True and l.get("torrent_hash")==expected and type(l.get("file_id")) is int,"LIBRARY_BINDING")
            ms=row.get("timing",{}).get("final_ms",0)
            need(type(ms) is int and ms>0,"TIMING_UNVERIFIED")
            total=round((time.monotonic()-began)*1000)
            write_doc("accepted.json",{"request_id":nonce,"pid":pid,"fixture":fixture,"agy_ms":ms,"submit_to_library_ms":total})
            return f"G2_PROD_LIBRARY_READY_AGY{ms}_TOTAL{total}"
        time.sleep(1)
    return "G2_PROD_PENDING_NO_REPLAY"
try: print(main())
except Hold as e: print("G2_PROD_HOLD_"+str(e))
except Exception:
    import traceback
    (run/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("G2_PROD_LOCAL_ERROR")
'@
$f=Join-Path $run 'deploy.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $run $spool $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
}catch{[IO.File]::WriteAllText((Join-Path $run 'host-private-error.txt'),($_|Out-String),[Text.UTF8Encoding]::new($false))}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
