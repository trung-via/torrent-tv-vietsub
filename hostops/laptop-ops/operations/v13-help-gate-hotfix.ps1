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
$prior='0b22620bfbb7dfe0ac107702a243cb2db2be1f234df8f0bcc21491170f95e8df'
$source='e678622ce015d4e6137169588125d859773cf137'
$blob='c003713574b8650601c37ed18789fd4bfd423181'
$stage=Join-Path $owner ('staged-releases\v13-help-'+$rq.nonce)
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
function SafeGap{
 $inbox=Join-Path $owner 'inbox';$state=Join-Path $base 'P2\auto-lean120-state';$native=Join-Path $base 'subtitle-trials\.native-v13'
 foreach($d in @($inbox,$state,$native)){
   $item=Get-Item -LiteralPath $d -Force
   if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){return $false}
 }
 if(Test-Path -LiteralPath (Join-Path $native 'browser.pending')){return $false}
 if(@(Get-ChildItem -LiteralPath $state -File -Recurse -Force|Where-Object{$_.Name -eq 'active.lock' -or $_.Name -like '*.inflight'}).Count){return $false}
 foreach($c in @(Get-ChildItem -LiteralPath $inbox -File -Force -Filter 'claim-*')){
   $stem='event-'+$c.Name.Substring(6)
   if(-not (@('.blocked','.done','.review')|Where-Object{Test-Path -LiteralPath (Join-Path $inbox ($stem+$_)) -PathType Leaf})){return $false}
 }
 $events=@(Get-ChildItem -LiteralPath $inbox -File -Force -Filter 'event-*.json')
 if($events.Count -gt 1){return $false}
 if($events.Count -eq 1){
   $e=Get-Content -LiteralPath $events[0].FullName -Raw|ConvertFrom-Json
   if([string]$e.event_id -cnotmatch '^[a-f0-9]{32}$' -or [string]$e.source_fingerprint -cnotmatch '^[a-f0-9]{64}$'){return $false}
   $retry=Join-Path $inbox ('preprovider-retry-'+$e.event_id+'.json')
   if(-not (Test-Path -LiteralPath $retry -PathType Leaf)){return $false}
   $r=Get-Content -LiteralPath $retry -Raw|ConvertFrom-Json
   if($r.schema -cne 'TTV-OWNER-PREPROVIDER-RETRY-V1' -or [long]$r.not_before_epoch -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+3){return $false}
   $job=Join-Path $native $e.source_fingerprint
   $terminal=Join-Path $job 'terminal.json'
   if(-not (Test-Path -LiteralPath $terminal -PathType Leaf) -or (Test-Path -LiteralPath (Join-Path $job 'provider.started.json'))){return $false}
   $v=Get-Content -LiteralPath $terminal -Raw|ConvertFrom-Json
   if($v.status -cne 'PRE_PROVIDER_BLOCKED' -or $v.reason -cne 'AGY_EN_NATIVE_SESSION_SETTINGS_UNAVAILABLE'){return $false}
 }
 return $true
}
try{
 if((Hash $dst) -cne $prior){throw 'BASE_DRIFT'}
 if([string](Task).State -cne 'Running'){throw 'TASK_NOT_RUNNING'}
 $oldPid=Ready 0 0
 if($oldPid -le 0){throw 'HEARTBEAT'}
 $phase='STAGE'
 New-Item -ItemType Directory -Path $stage -ErrorAction Stop|Out-Null
 $candidate=Join-Path $stage 'agy_v13_native_producer.py';$backup=Join-Path $stage 'prior.py'
 Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/'+$source+'/'+$rel) -OutFile $candidate -TimeoutSec 30
 $verify='import sys,pathlib,hashlib; b=pathlib.Path(sys.argv[1]).read_bytes(); assert hashlib.sha1(b"blob "+str(len(b)).encode()+b"\0"+b).hexdigest()==sys.argv[2]; compile(b,"candidate","exec"); print("VERIFIED")'
 $o=@(& py -3 -I -B -c $verify $candidate $blob 2>&1)
 if($LASTEXITCODE -ne 0 -or @($o|Where-Object{[string]$_ -ceq 'VERIFIED'}).Count -ne 1){throw 'CANDIDATE_VERIFY'}
 $target=Hash $candidate
 [IO.File]::Copy($dst,$backup,$false)
 if((Hash $backup) -cne $prior){throw 'BACKUP'}
 $phase='GAP'
 $safe=$false
 for($i=0;$i -lt 40;$i++){if(SafeGap){$safe=$true;break};Start-Sleep -Seconds 1}
 if(-not $safe){throw 'ACTIVE_OR_UNKNOWN'}
 if((Ready 0 0) -ne $oldPid -or (Hash $dst) -cne $prior){throw 'OWNER_DRIFT'}
 $phase='STOP'
 Disable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
 $disabled=$true
 if(-not (SafeGap)){throw 'GAP_CHANGED'}
 try{Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop}catch{}
 for($i=0;$i -lt 3 -and @(Workers).Count -gt 0;$i++){Start-Sleep -Milliseconds 300}
 foreach($w in @(Workers)){
   if([string](Task).State -cne 'Disabled' -or -not (SafeGap)){throw 'STOP_GAP_CHANGED'}
   $live=@(Workers|Where-Object{[int]$_.ProcessId -eq [int]$w.ProcessId})
   if($live.Count -ne 1 -or $live[0].CreationDate -ne $w.CreationDate -or $live[0].CommandLine -cne $w.CommandLine){throw 'WORKER_CHANGED'}
   Stop-Process -Id ([int]$w.ProcessId) -Force -ErrorAction Stop
 }
 if(@(Workers).Count -gt 0 -or [string](Task).State -cne 'Disabled' -or -not (SafeGap)){throw 'STOP_UNVERIFIED'}
 $phase='REPLACE'
 if((Hash $dst) -cne $prior){throw 'BASE_DRIFT'}
 $tmp=$dst+'.hotfix-'+$rq.nonce
 [IO.File]::Copy($candidate,$tmp,$false)
 if((Hash $tmp) -cne $target){throw 'TEMP_HASH'}
 [IO.File]::Replace($tmp,$dst,(Join-Path $stage 'displaced.py'));$changed=$true
 if((Hash $dst) -cne $target){throw 'POST_HASH'}
 $phase='IMPORT'
 $import='import sys,pathlib;root=pathlib.Path(sys.argv[1]);sys.path[:0]=[str(root/"poc/p2-sub-discovery"),str(root/"poc/p2-aisub"),str(root/"poc/p3-vietsub-trigger")];import agy_v13_native_producer;print("IMPORTED")'
 $o=@(& py -3 -I -B -c $import $app 2>&1)
 if($LASTEXITCODE -ne 0 -or @($o|Where-Object{[string]$_ -ceq 'IMPORTED'}).Count -ne 1){throw 'IMPORT'}
 $phase='START';$since=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-1
 Enable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
 $disabled=$false;$startAttempted=$true
 Start-ScheduledTask -TaskName $taskName -TaskPath '\'
 $newPid=0
 for($i=0;$i -lt 30;$i++){Start-Sleep -Seconds 1;if([string](Task).State -ceq 'Running'){$newPid=Ready $oldPid $since;if($newPid -gt 0){break}}}
 if($newPid -le 0 -or (Hash $dst) -cne $target){throw 'FRESH_OWNER'}
 $code='V13_HELP_FIX_INSTALLED_F1_FRESH_OWNER'
}catch{
 $code='V13_HELP_FIX_HOLD_'+$phase
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
   }catch{$code='V13_HELP_FIX_ROLLBACK_HOLD'}
 }
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
