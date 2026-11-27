# Approved G1 V13.5 acquisition hotfix. Exact two Python modules; no event or cache mutation.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$app=Join-Path $owner 'app'
$taskName='TorrentTV-Vietsub-OwnerAgent'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$source='b0e0cba86a09a7353c416536088d666363f3676c'
$stage=Join-Path $owner ('staged-releases\v135-acquisition-'+$rq.nonce)
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
 @{rel='poc/p2-sub-discovery/agy_v13_browser_evidence.py';old='d9a16af5f508ec07020ae8d9a493339b64120f9e';new='37913c008f2cc521494ac076fe1e7b8fa2ba08b2'},
 @{rel='poc/p2-sub-discovery/agy_v13_native_producer.py';old='c60785b94e3f4e77df3359b7a867b402f99d494b';new='20e9c725bce400593ae9a5ba27eda19f2aed797f'}
)
$base=Split-Path $owner -Parent
$state=Join-Path $base 'P2\auto-lean120-state'
$inbox=Join-Path $owner 'inbox'
$browserPending=Join-Path $base 'subtitle-trials\.native-v13\browser.pending'
function Confirm-NoWork{
 if((Test-Path -LiteralPath $browserPending) -or @(Get-ChildItem -LiteralPath $state -Recurse -File -Filter 'active.lock').Count -ne 0 -or @(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json').Count -ne 0){throw 'WORK_OR_UNKNOWN_EFFECT'}
}
function Confirm-Audit{
 $snapPath=Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\Diagnostics\owner-snapshot.json'
 $item=Get-Item -LiteralPath $snapPath -Force
 if($item.Length -gt 4096 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'SNAPSHOT_INVALID'}
 $snap=Get-Content -LiteralPath $snapPath -Raw|ConvertFrom-Json
 $age=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-[long]$snap.snapshot_utc_epoch
 if($snap.schema -cne 'TTV-HOSTOPS-OWNER-SNAPSHOT-V4' -or $snap.status -cne 'READY_FRESH' -or $age -lt 0 -or $age -gt 30 -or $snap.p2.status -cne 'CLEAR' -or $snap.p2.pending_events -ne 0 -or $snap.p2.inflight_count -ne 0){throw 'OWNER_NOT_IDLE'}
 if([string]$snap.p3_state -in @('FRESH_ON','FRESH_REQUESTED')){throw 'TV_ACTIVE'}
 Confirm-NoWork
}
$verify='import sys,pathlib,hashlib; b=pathlib.Path(sys.argv[1]).read_bytes().replace(b"\r\n",b"\n"); assert hashlib.sha1(b"blob "+str(len(b)).encode()+b"\0"+b).hexdigest()==sys.argv[2]; compile(b,"candidate","exec"); print("VERIFIED")'
function Verify([string]$path,[string]$expected){
 $o=@(& py -3 -I -B -c $verify $path $expected 2>&1)
 if($LASTEXITCODE -ne 0 -or $o.Count -ne 1 -or [string]$o[0] -cne 'VERIFIED'){throw 'BLOB_VERIFY'}
}
$replaced=@();$disabled=$false;$startAttempted=$false;$phase='PREFLIGHT';$code='V135_INSTALL_HOLD_PREFLIGHT'
try {
 if([string](Task).State -cne 'Running'){throw 'TASK_NOT_RUNNING'}
 $oldPid=Ready 0 0
 if($oldPid -le 0){throw 'HEARTBEAT'}
 Confirm-Audit
 $phase='STAGE'
 New-Item -ItemType Directory -Path $stage -ErrorAction Stop|Out-Null
 foreach($f in $files){
   $name=[IO.Path]::GetFileName($f.rel)
   $f.dst=Join-Path $app $f.rel
   $f.candidate=Join-Path $stage $name
   $f.backup=Join-Path $stage ('prior-'+$name)
   Verify $f.dst $f.old
   $f.prior=Hash $f.dst
   Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/'+$source+'/'+$f.rel) -OutFile $f.candidate -TimeoutSec 30
   Verify $f.candidate $f.new
   $f.target=Hash $f.candidate
   [IO.File]::Copy($f.dst,$f.backup,$false)
   if((Hash $f.backup) -cne $f.prior){throw 'BACKUP'}
 }
 $phase='QUIESCENCE'
 Confirm-Audit
 if((Ready 0 0) -ne $oldPid -or [string](Task).State -cne 'Running'){throw 'OWNER_CHANGED'}
 Disable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
 $disabled=$true
 # Recheck after disabling future scheduled starts; do not stop new work.
 Confirm-Audit
 $phase='STOP'
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
 $state=Join-Path (Split-Path $owner -Parent) 'P2\auto-lean120-state'
 $inbox=Join-Path $owner 'inbox'
 Confirm-NoWork
 $phase='REPLACE'
 foreach($f in $files){
   if((Hash $f.dst) -cne $f.prior){throw 'BASE_DRIFT'}
   $tmp=$f.dst+'.hotfix-'+$rq.nonce
   [IO.File]::Copy($f.candidate,$tmp,$false)
   if((Hash $tmp) -cne $f.target){throw 'TEMP_HASH'}
   [IO.File]::Replace($tmp,$f.dst,(Join-Path $stage ('displaced-'+[IO.Path]::GetFileName($f.rel))))
   $replaced+=@($f)
   if((Hash $f.dst) -cne $f.target){throw 'POST_HASH'}
 }
 $phase='IMPORT'
 $import='import sys,pathlib;root=pathlib.Path(sys.argv[1]);sys.path[:0]=[str(root/"poc"/p) for p in ("p2-sub-discovery","p2-aisub","p3-vietsub-trigger")];import agy_v13_browser_evidence as e,agy_v13_native_producer as n;assert e.RECIPE_VERSION=="V13.5" and e.VERIFICATION_REVISION=="V13.4-BR07-1" and e.MAX_DOWNLOAD_BYTES==6291456 and n.closing;print("IMPORTED")'
 $o=@(& py -3 -I -B -c $import $app 2>&1)
 if($LASTEXITCODE -ne 0 -or $o.Count -ne 1 -or [string]$o[0] -cne 'IMPORTED'){throw 'IMPORT'}
 $phase='START';$since=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-1
 Enable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
 $disabled=$false;$startAttempted=$true
 Start-ScheduledTask -TaskName $taskName -TaskPath '\'
 $newPid=0
 for($i=0;$i -lt 30;$i++){Start-Sleep -Seconds 1;if([string](Task).State -ceq 'Running'){$newPid=Ready $oldPid $since;if($newPid -gt 0){break}}}
 if($newPid -le 0){throw 'FRESH_OWNER'}
 foreach($f in $files){if((Hash $f.dst) -cne $f.target){throw 'POST_HASH'}}

 $code='V135_INSTALL_PASS_TWO_MODULES_FRESH_OWNER_CACHE_PRESERVED'
}catch{
 $code='V135_INSTALL_HOLD_'+$phase
 if($_.Exception.Message -cin @('OWNER_NOT_IDLE','TV_ACTIVE','WORK_OR_UNKNOWN_EFFECT','SNAPSHOT_INVALID','BLOB_VERIFY')){$code+='_'+$_.Exception.Message}
 if(-not $startAttempted -and $disabled){
   try{
     if(@(Workers).Count -gt 0){
       if($replaced.Count -ne 0){throw 'ROLLBACK_UNSAFE'}
       Enable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
     }else{
       foreach($f in $replaced){
         if((Hash $f.backup) -cne $f.prior){throw 'ROLLBACK_HASH'}
         $tmp=$f.dst+'.rollback-'+$rq.nonce
         [IO.File]::Copy($f.backup,$tmp,$false)
         [IO.File]::Replace($tmp,$f.dst,(Join-Path $stage ('failed-'+[IO.Path]::GetFileName($f.rel))))
         if((Hash $f.dst) -cne $f.prior){throw 'ROLLBACK_HASH'}
       }
       Enable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
       Start-ScheduledTask -TaskName $taskName -TaskPath '\'
     }
     $code+='_OWNER_REENABLED'
   }catch{$code='V135_INSTALL_ROLLBACK_HOLD'}
 }
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
