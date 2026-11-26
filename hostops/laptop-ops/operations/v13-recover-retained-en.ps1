# Approved one-file V13.1 hotfix; preserve queued pre-provider event and all receipts.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$base=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$owner=Join-Path $base 'OwnerBridge'
$app=Join-Path $owner 'app'
$taskName='TorrentTV-Vietsub-OwnerAgent'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$rel='poc/p2-sub-discovery/agy_v13_native_producer.py'
$dst=Join-Path $app $rel
$prior=$null
$source='5b0f7ef68ba6c4665bc7ef77f2b387d3a43b097a'
$blob='2bbc0de3cda88e905852567ddab0c5d93cc9c006'
$stage=Join-Path $owner ('staged-releases\v13-retained-en-'+$rq.nonce)
$phase='PREFLIGHT';$disabled=$false;$changed=$false;$startAttempted=$false
function Hash([string]$p){$i=Get-Item -LiteralPath $p -Force;if($i.PSIsContainer -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'FILE_INVALID'};(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
function Task{
 $t=Get-ScheduledTask -TaskName $taskName -TaskPath '\'
 $s=[string]$t.Principal.UserId
 if($s -notmatch '^S-\d'){$s=([Security.Principal.NTAccount]::new($s).Translate([Security.Principal.SecurityIdentifier])).Value}
 if($s -cne $sid -or [string]$t.Principal.LogonType -ine 'Interactive' -or @($t.Actions).Count -ne 1 -or [string]$t.Actions[0].Arguments -notmatch 'start-owner-session-agent\.ps1'){throw 'TASK_IDENTITY'}
 $t
}
function Workers{
 $paths=@((Join-Path $app 'poc\p2-sub-discovery\owner_p3_p4_entrypoint.py'),(Join-Path $app 'poc\p2-sub-discovery\owner_session_bridge.py'))
 foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe' OR Name='py.exe'")){
   if([string]$p.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'){continue}
   $matches=@($paths|Where-Object{([string]$p.CommandLine).IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0})
   $who=Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid
   if($matches.Count -ne 1 -or $who.ReturnValue -ne 0 -or $who.Sid -cne $sid -or -not $p.CreationDate){throw 'WORKER_IDENTITY'}
   $p
 }
}
function Ready([long]$old,[long]$since){
 try{
   $h=Get-Content -LiteralPath (Join-Path $owner 'agent-health.json') -Raw|ConvertFrom-Json
   $age=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-[long]$h.observed_utc_epoch
   if($h.schema -cne 'TTV-OWNER-AGENT-HEALTH-V1' -or $h.state -cne 'READY' -or $age -lt 0 -or $age -gt 30 -or [long]$h.pid -eq $old -or [long]$h.observed_utc_epoch -lt $since){return 0}
   if(@(Workers|Where-Object{[long]$_.ProcessId -eq [long]$h.pid}).Count -ne 1){return 0}
   return [long]$h.pid
 }catch{return 0}
}

$files=@(
 @{name='agy_v13_browser_evidence.py';old='26ebb2cc5c46e9b22f5b5e734bdd6031fa4b1b0f';new='4df753952a65404ed7db628fbf2049460c6d8d6c'},
 @{name='agy_v13_native_producer.py';old='2bbc0de3cda88e905852567ddab0c5d93cc9c006';new='0e10a18f4727c4bf1e377712d706d57e9bc3cb84'}
)
$replaced=@()
$verify='import sys,pathlib,hashlib; b=pathlib.Path(sys.argv[1]).read_bytes(); assert hashlib.sha1(b"blob "+str(len(b)).encode()+b"\0"+b).hexdigest()==sys.argv[2]; compile(b,"candidate","exec"); print("VERIFIED")'
function Verify([string]$path,[string]$expected){
 $o=@(& py -3 -I -B -c $verify $path $expected 2>&1)
 if($LASTEXITCODE -ne 0 -or $o.Count -ne 1 -or [string]$o[0] -cne 'VERIFIED'){throw 'BLOB_VERIFY'}
}
try{
 if([string](Task).State -cne 'Running'){throw 'TASK_NOT_RUNNING'}
 $oldPid=Ready 0 0
 if($oldPid -le 0){throw 'HEARTBEAT'}
 $phase='STAGE'
 New-Item -ItemType Directory -Path $stage -ErrorAction Stop|Out-Null
 foreach($f in $files){
   $rel='poc/p2-sub-discovery/'+$f.name
   $f.dst=Join-Path $app $rel
   $f.candidate=Join-Path $stage $f.name
   $f.backup=Join-Path $stage ('prior-'+$f.name)
   Verify $f.dst $f.old
   $f.prior=Hash $f.dst
   Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/'+$source+'/'+$rel) -OutFile $f.candidate -TimeoutSec 30
   Verify $f.candidate $f.new
   $f.target=Hash $f.candidate
   [IO.File]::Copy($f.dst,$f.backup,$false)
   if((Hash $f.backup) -cne $f.prior){throw 'BACKUP'}
 }
 $phase='STOP'
 Disable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
 $disabled=$true
 try{Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop}catch{}
 for($i=0;$i -lt 3 -and @(Workers).Count -gt 0;$i++){Start-Sleep -Milliseconds 300}
 foreach($w in @(Workers)){
   if([string](Task).State -cne 'Disabled'){throw 'STOP_IDENTITY'}
   $live=@(Workers|Where-Object{[int]$_.ProcessId -eq [int]$w.ProcessId})
   if($live.Count -eq 0){continue}
   if($live.Count -ne 1 -or $live[0].CreationDate -ne $w.CreationDate -or $live[0].CommandLine -cne $w.CommandLine){throw 'WORKER_CHANGED'}
   Stop-Process -Id ([int]$w.ProcessId) -Force -ErrorAction Stop
 }
 if(@(Workers).Count -gt 0 -or [string](Task).State -cne 'Disabled'){throw 'STOP_UNVERIFIED'}
 $phase='REPLACE'
 foreach($f in $files){
   if((Hash $f.dst) -cne $f.prior){throw 'BASE_DRIFT'}
   $tmp=$f.dst+'.hotfix-'+$rq.nonce
   [IO.File]::Copy($f.candidate,$tmp,$false)
   if((Hash $tmp) -cne $f.target){throw 'TEMP_HASH'}
   [IO.File]::Replace($tmp,$f.dst,(Join-Path $stage ('displaced-'+$f.name)))
   $replaced+=@($f)
   if((Hash $f.dst) -cne $f.target){throw 'POST_HASH'}
 }
 $phase='IMPORT'
 $import='import sys,pathlib;root=pathlib.Path(sys.argv[1]);sys.path[:0]=[str(root/"poc/p2-sub-discovery"),str(root/"poc/p2-aisub"),str(root/"poc/p3-vietsub-trigger")];from agy_v13_native_producer import recover_comparison_rejected;print("IMPORTED")'
 $o=@(& py -3 -I -B -c $import $app 2>&1)
 if($LASTEXITCODE -ne 0 -or $o.Count -ne 1 -or [string]$o[0] -cne 'IMPORTED'){throw 'IMPORT'}
 $phase='RECOVER'
 $recover=@'
import ast,hashlib,json,os,pathlib,re,sys
root=pathlib.Path(sys.argv[1]);stage=pathlib.Path(sys.argv[2]);oldpid=int(sys.argv[3])
sys.path[:0]=[str(root/"app/poc"/p) for p in ("p2-sub-discovery","p2-aisub","p3-vietsub-trigger")]
from agy_v13_native_producer import recover_comparison_rejected,_job
from matcher import Media
from owner_session_bridge import _authorized_selection
from agy_opensubtitles_acquisition import AgyEnglishUnavailable
def load(p,limit=16777216):
    if p.is_symlink() or not p.is_file() or not 0<p.stat().st_size<=limit:raise ValueError()
    return json.loads(p.read_text(encoding="utf-8-sig"))
try:
    inbox=root/"inbox";cache=root.parent/"subtitle-trials";native=cache/".native-v13"
    if (native/"browser.pending").exists() or (native/"browser.pending").is_symlink():
        print("HELD_BROWSER_PENDING");sys.exit(0)
    with (root/"diagnostics"/"owner-full.log").open("rb") as f:
        n=f.seek(0,2);off=max(0,n-8388608);f.seek(off);raw=f.read(8388608)
    if off:raw=raw.partition(b"\n")[2]
    lines=raw.decode("utf-8","replace").splitlines()
    starts=[i for i,l in enumerate(lines) if re.fullmatch(r"OWNER_FULL_DIAGNOSTICS_STARTED pid="+str(oldpid)+r" epoch=\d+",l)]
    if not starts:print("HELD_LOG_UNBOUND");sys.exit(0)
    epoch=int(lines[starts[-1]].rsplit("=",1)[1])
    last={}
    for l in lines[starts[-1]+1:]:
        m=re.match(r"OWNER_FULL_TRACE 'P2_(EVENT_CLAIMED|PREPROVIDER_TRANSIENT|EVENT_BLOCKED|EVENT_FINISHED)' (\{.*\})$",l)
        if m:
            try:
                d=ast.literal_eval(m.group(2));eid=d.get("event_id")
                if isinstance(eid,str) and re.fullmatch(r"[a-f0-9]{32}",eid):last[eid]=(m.group(1),d)
            except (ValueError,SyntaxError,AttributeError):pass
    eligible=[]
    for eid,(kind,trace) in last.items():
        if kind!="EVENT_BLOCKED":continue
        blocked=inbox/("event-"+eid+".blocked")
        if not blocked.is_file():continue
        ev=load(blocked,65536);fp=ev.get("source_fingerprint")
        if ev.get("event_id")!=eid or not isinstance(fp,str) or not re.fullmatch(r"[a-f0-9]{64}",fp) or trace.get("source_fingerprint")!=fp:continue
        run=native/fp
        term=run/"terminal.json"
        if not term.is_file() or term.stat().st_mtime<epoch:continue
        t=load(term,4096)
        if t.get("status")!="SOURCE_REJECTED" or t.get("reason")!="AGY_EN_RELEASE_COMPARISON_MISSING":continue
        evidence=load(run/"evidence.json")
        media=Media(**evidence["media"])
        if _job(cache,media)!=run or media.filename!=ev.get("selected_video_filename"):continue
        coords=_authorized_selection(ev.get("authorized_selection"),fp,ev.get("tv_session_id"))
        if media.key!=(coords["server_id"],coords["torrent_hash"],coords["file_index"]):continue
        claim=inbox/("claim-"+eid)
        if claim.is_symlink() or not claim.is_file() or claim.read_bytes()!=b"CLAIMED_DO_NOT_AUTO_REPLAY\n":continue
        queued=inbox/("event-"+eid+".json")
        if queued.exists() or any(load(p,65536).get("source_fingerprint")==fp for p in inbox.glob("event-*.json")):continue
        eligible.append((run,media,blocked,claim,queued))
    if len(eligible)!=1:
        print("HELD_EVENT_UNBOUND");sys.exit(0)
    run,media,blocked,claim,queued=eligible[0]
    try:asset=recover_comparison_rejected(run,media)
    except AgyEnglishUnavailable:
        print("HELD_SOURCE_RECHECK");sys.exit(0)
    # Retain original blocked event and claim. No translation or provider
    # was invoked by this maintenance script. The normal Owner consumes
    # the original event, but native acquisition now reads verified.json.
    (stage/"blocked-event.backup").write_bytes(blocked.read_bytes())
    archive=stage/"blocked-claim.backup"
    os.replace(claim,archive)
    try:os.replace(blocked,queued)
    except OSError:
        os.replace(archive,claim)
        raise
    print("EN_RECOVERED_C"+str(asset.cues))
except Exception:
    print("HELD_RECOVERY_EXCEPTION")
'@
 $o=@(& py -3 -I -B -c $recover $owner $stage $oldPid 2>&1)
 $outcome='HELD_RECOVERY_EXCEPTION'
 if($LASTEXITCODE -eq 0 -and $o.Count -eq 1 -and [string]$o[0] -cmatch '^(EN_RECOVERED_C[0-9]{1,6}|HELD_[A-Z_]+)$'){$outcome=[string]$o[0]}
 $phase='START';$since=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-1
 Enable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
 $disabled=$false;$startAttempted=$true
 Start-ScheduledTask -TaskName $taskName -TaskPath '\'
 $newPid=0
 for($i=0;$i -lt 30;$i++){Start-Sleep -Seconds 1;if([string](Task).State -ceq 'Running'){$newPid=Ready $oldPid $since;if($newPid -gt 0){break}}}
 if($newPid -le 0){throw 'FRESH_OWNER'}
 foreach($f in $files){if((Hash $f.dst) -cne $f.target){throw 'POST_HASH'}}
 $code='V13_RETAINED_F2_FRESH_OWNER_'+$outcome
}catch{
 $code='V13_RETAINED_HOLD_'+$phase
 if(-not $startAttempted -and $disabled){
   try{
     if(@(Workers).Count -gt 0){throw 'ROLLBACK_UNSAFE'}
     foreach($f in $replaced){
       if((Hash $f.backup) -cne $f.prior){throw 'ROLLBACK_HASH'}
       $tmp=$f.dst+'.rollback-'+$rq.nonce
       [IO.File]::Copy($f.backup,$tmp,$false)
       [IO.File]::Replace($tmp,$f.dst,(Join-Path $stage ('failed-'+$f.name)))
       if((Hash $f.dst) -cne $f.prior){throw 'ROLLBACK_HASH'}
     }
     Enable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
     Start-ScheduledTask -TaskName $taskName -TaskPath '\'
     $code+='_OWNER_REENABLED'
   }catch{$code='V13_RETAINED_ROLLBACK_HOLD'}
 }
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
