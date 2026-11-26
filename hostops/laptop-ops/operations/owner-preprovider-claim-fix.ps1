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
$rel='poc/p2-sub-discovery/owner_session_bridge.py'
$dst=Join-Path $app $rel
$prior=$null
$source='7893d121cd2b147982aff804120362e3f576b89f'
$blob='a3305ff2ef6a926a49d6f42eac6ba461b0775aa6'
$stage=Join-Path $owner ('staged-releases\claim-fix-'+$rq.nonce)
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

try{
 $prior=Hash $dst
 $priorVerify='import sys,pathlib,hashlib; b=pathlib.Path(sys.argv[1]).read_bytes(); print(hashlib.sha1(b"blob "+str(len(b)).encode()+b"\0"+b).hexdigest())'
 $oldBlob=@(& py -3 -I -B -c $priorVerify $dst 2>&1)
 if($LASTEXITCODE -ne 0 -or $oldBlob.Count -ne 1 -or [string]$oldBlob[0] -cne '7154d2f32bb30fe3fa811a59cae812bcb4c67767'){throw 'BASE_DRIFT'}
 if([string](Task).State -cne 'Running'){throw 'TASK_NOT_RUNNING'}
 $oldPid=Ready 0 0
 if($oldPid -le 0){throw 'HEARTBEAT'}
 $phase='STAGE'
 New-Item -ItemType Directory -Path $stage -ErrorAction Stop|Out-Null
 $candidate=Join-Path $stage 'owner_session_bridge.py';$backup=Join-Path $stage 'prior.py'
 Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/'+$source+'/'+$rel) -OutFile $candidate -TimeoutSec 30
 $verify='import sys,pathlib,hashlib; b=pathlib.Path(sys.argv[1]).read_bytes(); assert hashlib.sha1(b"blob "+str(len(b)).encode()+b"\0"+b).hexdigest()==sys.argv[2]; compile(b,"candidate","exec"); print("VERIFIED")'
 $o=@(& py -3 -I -B -c $verify $candidate $blob 2>&1)
 if($LASTEXITCODE -ne 0 -or @($o|Where-Object{[string]$_ -ceq 'VERIFIED'}).Count -ne 1){throw 'CANDIDATE_VERIFY'}
 $target=Hash $candidate
 [IO.File]::Copy($dst,$backup,$false)
 if((Hash $backup) -cne $prior){throw 'BACKUP'}
 if((Hash $dst) -cne $prior){throw 'BASE_DRIFT'}

 $phase='STOP'
 Disable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
 $disabled=$true
 try{Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop}catch{}
 for($i=0;$i -lt 3 -and @(Workers).Count -gt 0;$i++){Start-Sleep -Milliseconds 300}
 foreach($w in @(Workers)){
   if([string](Task).State -cne 'Disabled'){throw 'STOP_GAP_CHANGED'}
   $live=@(Workers|Where-Object{[int]$_.ProcessId -eq [int]$w.ProcessId})
   if($live.Count -eq 0){continue}
   if($live.Count -ne 1 -or $live[0].CreationDate -ne $w.CreationDate -or $live[0].CommandLine -cne $w.CommandLine){throw 'WORKER_CHANGED'}
   Stop-Process -Id ([int]$w.ProcessId) -Force -ErrorAction Stop
 }
 if(@(Workers).Count -gt 0 -or [string](Task).State -cne 'Disabled'){throw 'STOP_UNVERIFIED'}
 $phase='REPLACE'
 if((Hash $dst) -cne $prior){throw 'BASE_DRIFT'}
 $tmp=$dst+'.hotfix-'+$rq.nonce
 [IO.File]::Copy($candidate,$tmp,$false)
 if((Hash $tmp) -cne $target){throw 'TEMP_HASH'}
 [IO.File]::Replace($tmp,$dst,(Join-Path $stage 'displaced.py'));$changed=$true
 if((Hash $dst) -cne $target){throw 'POST_HASH'}
 $phase='IMPORT'
 $import='import sys,pathlib;root=pathlib.Path(sys.argv[1]);sys.path[:0]=[str(root/"poc/p2-sub-discovery"),str(root/"poc/p2-aisub"),str(root/"poc/p3-vietsub-trigger")];import owner_session_bridge;print("IMPORTED")'
 $o=@(& py -3 -I -B -c $import $app 2>&1)
 if($LASTEXITCODE -ne 0 -or @($o|Where-Object{[string]$_ -ceq 'IMPORTED'}).Count -ne 1){throw 'IMPORT'}

 # Reconcile only the one proven pre-provider legacy claim, after Owner is stopped.
 # Keep the original claim as private backup. Never recover unknown provider effects.
 $phase='RECONCILE'
 $migration=@'
import sys,pathlib,json,ast,re,time,shutil
root=pathlib.Path(sys.argv[1]);stage=pathlib.Path(sys.argv[2])
sys.path[:0]=[str(root/"app/poc"/p) for p in ("p2-sub-discovery","p2-aisub","p3-vietsub-trigger")]
from owner_session_bridge import _record_preprovider_retry,_retry_state
def load(p):
    if not p.is_file() or p.is_symlink() or not 0<p.stat().st_size<=65536:raise ValueError()
    return json.loads(p.read_text(encoding="utf-8-sig"))
try:
    inbox=root/"inbox";native=root.parent/"subtitle-trials"/".native-v13";state=root.parent/"P2"/"auto-lean120-state"
    if (native/"browser.pending").exists() or any(state.rglob("*.inflight")):
        print("LEGACY_HELD");sys.exit(0)
    log=root/"diagnostics"/"owner-full.log"
    with log.open("rb") as f:
        n=f.seek(0,2);off=max(0,n-8388608);f.seek(off);raw=f.read(8388608)
    if off:raw=raw.partition(b"\n")[2]
    last={};claimed={}
    for l in raw.decode("utf-8","replace").splitlines():
        m=re.match(r"OWNER_FULL_TRACE 'P2_(EVENT_CLAIMED|PREPROVIDER_TRANSIENT|EVENT_BLOCKED|EVENT_FINISHED)' (\{.*\})$",l)
        if m:
            try:
                d=ast.literal_eval(m.group(2));eid=d.get("event_id")
                if isinstance(eid,str) and re.fullmatch(r"[a-f0-9]{32}",eid):
                    last[eid]=m.group(1)
                    if m.group(1)=="EVENT_CLAIMED":claimed[eid]=d
            except Exception:pass
    eligible=[]
    for p in inbox.glob("event-*.json"):
        ev=load(p);eid=ev.get("event_id");fp=ev.get("source_fingerprint")
        if not isinstance(eid,str) or not re.fullmatch(r"[a-f0-9]{32}",eid) or p.stem!="event-"+eid or not isinstance(fp,str) or not re.fullmatch(r"[a-f0-9]{64}",fp):continue
        claim=inbox/("claim-"+eid)
        if not claim.is_file() or claim.is_symlink() or claim.read_bytes()!=b"CLAIMED_DO_NOT_AUTO_REPLAY\n":continue
        if last.get(eid)!="PREPROVIDER_TRANSIENT" or claimed.get(eid,{}).get("source_fingerprint")!=fp or claimed[eid].get("video")!=ev.get("selected_video_filename"):continue
        d=native/fp
        if (d/"provider.started.json").exists() or (d/"provider.started.json").is_symlink():continue
        terminal=d/"terminal.json"
        doc=load(terminal)
        if doc.get("status")!="PRE_PROVIDER_BLOCKED" or doc.get("reason")!="AGY_EN_NATIVE_SESSION_SETTINGS_UNAVAILABLE" or terminal.stat().st_mtime_ns<claim.stat().st_mtime_ns:continue
        eligible.append((eid,claim))
    if len(eligible)!=1:
        print("LEGACY_NOT_PROVEN");sys.exit(0)
    eid,claim=eligible[0]
    retry=inbox/("preprovider-retry-"+eid+".json")
    attempts,_=_retry_state(retry)
    backup=stage/"legacy-preprovider-claim.backup"
    with backup.open("xb") as f:f.write(claim.read_bytes())
    _record_preprovider_retry(claim,min(max(1,attempts),3),int(time.time()))
    print("LEGACY_RECOVERABLE")
except Exception:
    print("LEGACY_HELD")
'@
 $migrationOut=@(& py -3 -I -B -c $migration $owner $stage 2>&1)
 $legacy='LEGACY_HELD'
 if($LASTEXITCODE -eq 0 -and $migrationOut.Count -eq 1 -and [string]$migrationOut[0] -cin @('LEGACY_RECOVERABLE','LEGACY_NOT_PROVEN','LEGACY_HELD')){$legacy=[string]$migrationOut[0]}

 $phase='START';$since=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-1
 Enable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
 $disabled=$false;$startAttempted=$true
 Start-ScheduledTask -TaskName $taskName -TaskPath '\'
 $newPid=0
 for($i=0;$i -lt 30;$i++){Start-Sleep -Seconds 1;if([string](Task).State -ceq 'Running'){$newPid=Ready $oldPid $since;if($newPid -gt 0){break}}}
 if($newPid -le 0 -or (Hash $dst) -cne $target){throw 'FRESH_OWNER'}
 $code='CLAIM_FIX_F1_FRESH_OWNER_'+$legacy
}catch{
 $code='CLAIM_FIX_HOLD_'+$phase
 if(-not $startAttempted -and $disabled){
   try{
     if($changed){
       if(@(Workers).Count -gt 0 -or (Hash $backup) -cne $prior){throw 'ROLLBACK_UNSAFE'}
       $tmp=$dst+'.rollback-'+$rq.nonce
       [IO.File]::Copy($backup,$tmp,$false)
       [IO.File]::Replace($tmp,$dst,(Join-Path $stage 'failed-new.py'))
       if((Hash $dst) -cne $prior){throw 'ROLLBACK_HASH'}
     }
     Enable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
     if(@(Workers).Count -eq 0){Start-ScheduledTask -TaskName $taskName -TaskPath '\'}
     $code+=' _OWNER_REENABLED'.Replace(' ','')
   }catch{$code='CLAIM_FIX_ROLLBACK_HOLD'}
 }
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
