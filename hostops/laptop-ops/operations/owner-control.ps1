# Reusable Owner lifecycle, local or pinned HostOps. Does not stop TorrServer or Chrome.
param([switch]$Status,[switch]$StopOwner,[switch]$StartOwner,[switch]$InstallAndFix)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(@($Status,$StopOwner,$StartOwner,$InstallAndFix|Where-Object{$_}).Count -ne 1){throw 'CHOOSE_ONE_ACTION'}
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0){throw 'OWNER_CONTEXT_REQUIRED'}
$base=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$owner=Join-Path $base 'OwnerBridge'
$app=Join-Path $owner 'app'
$taskName='TorrentTV-Vietsub-OwnerAgent'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$local=Join-Path $owner 'Maintenance\owner-control.ps1'
$rel='poc/p2-sub-discovery/agy_v13_native_producer.py'
$dst=Join-Path $app $rel
$prior='0b22620bfbb7dfe0ac107702a243cb2db2be1f234df8f0bcc21491170f95e8df'
$source='e678622ce015d4e6137169588125d859773cf137'
$blob='c003713574b8650601c37ed18789fd4bfd423181'
function Hash([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
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
   $hits=@($paths|Where-Object{([string]$p.CommandLine).IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0})
   $who=Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid
   if($hits.Count -ne 1 -or $who.ReturnValue -ne 0 -or $who.Sid -cne $sid -or -not $p.CreationDate){throw 'WORKER_IDENTITY'}
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
function Gap([int]$seconds=3){
 # Existing durable claims/markers are never cleared. A historical terminal
 # claim or old active.lock alone is not a live provider call.
 $inbox=Join-Path $owner 'inbox';$state=Join-Path $base 'P2\auto-lean120-state';$native=Join-Path $base 'subtitle-trials\.native-v13'
 if(Test-Path -LiteralPath (Join-Path $native 'browser.pending')){return 'BROWSER_PENDING'}
 if(@(Get-ChildItem -LiteralPath $state -File -Recurse -Force -Filter '*.inflight').Count){return 'INFLIGHT'}
 foreach($c in @(Get-ChildItem -LiteralPath $inbox -File -Force -Filter 'claim-*')){
   $stem='event-'+$c.Name.Substring(6)
   if(-not (@('.blocked','.done','.review')|Where-Object{Test-Path -LiteralPath (Join-Path $inbox ($stem+$_)) -PathType Leaf})){return 'UNRESOLVED_CLAIM'}
 }
 $now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
 foreach($f in @(Get-ChildItem -LiteralPath $inbox -File -Force -Filter 'event-*.json')){
   $e=Get-Content -LiteralPath $f.FullName -Raw|ConvertFrom-Json
   if([string]$e.event_id -cnotmatch '^[a-f0-9]{32}$' -or [string]$e.source_fingerprint -cnotmatch '^[a-f0-9]{64}$'){return 'EVENT_INVALID'}
   $rp=Join-Path $inbox ('preprovider-retry-'+$e.event_id+'.json')
   if(-not (Test-Path -LiteralPath $rp -PathType Leaf)){return 'EVENT_DUE'}
   $r=Get-Content -LiteralPath $rp -Raw|ConvertFrom-Json
   if($r.schema -cne 'TTV-OWNER-PREPROVIDER-RETRY-V1' -or [long]$r.not_before_epoch -le $now+$seconds){return 'RETRY_DUE'}
 }
 return 'CLEAR'
}
function Stop-Control{
 $t=Task
 if([string]$t.State -ceq 'Disabled' -and @(Workers).Count -eq 0){return 'STOPPED'}
 $reason='UNKNOWN'
 for($i=0;$i -lt 40;$i++){
   $reason=Gap 5
   if($reason -ceq 'CLEAR'){break}
   Start-Sleep -Seconds 1
 }
 if($reason -cne 'CLEAR'){return ('HOLD_'+$reason)}
 $before=@(Workers)
 Disable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
 # Disable does not kill current worker; recheck immediately before stopping.
 if((Gap 2) -cne 'CLEAR'){
   Enable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
   return 'HOLD_GAP_CHANGED'
 }
 try{Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop}catch{}
 foreach($w in @(Workers)){
   $known=@($before|Where-Object{[int]$_.ProcessId -eq [int]$w.ProcessId -and $_.CreationDate -eq $w.CreationDate -and $_.CommandLine -ceq $w.CommandLine})
   if($known.Count -ne 1 -or [string](Task).State -cne 'Disabled'){return 'HOLD_STOP_IDENTITY'}
   Stop-Process -Id ([int]$w.ProcessId) -Force -ErrorAction Stop
 }
 for($i=0;$i -lt 5 -and @(Workers).Count -gt 0;$i++){Start-Sleep -Milliseconds 300}
 if(@(Workers).Count -ne 0 -or [string](Task).State -cne 'Disabled'){return 'HOLD_STOP_UNVERIFIED'}
 # No replay if a race created an unknown-effect marker during stop.
 $g=Gap -2147483647
 if($g -in @('BROWSER_PENDING','INFLIGHT','UNRESOLVED_CLAIM','EVENT_INVALID')){return ('HOLD_STOPPED_'+$g)}
 return 'STOPPED'
}
function Start-Control{
 $t=Task
 if([string]$t.State -ceq 'Running' -and (Ready 0 0) -gt 0){return 'RUNNING'}
 if(@(Workers).Count -ne 0){return 'HOLD_RESIDUAL'}
 $g=Gap -2147483647
 if($g -in @('BROWSER_PENDING','INFLIGHT','UNRESOLVED_CLAIM','EVENT_INVALID')){return ('HOLD_'+$g)}
 $since=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-1
 Enable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
 Start-ScheduledTask -TaskName $taskName -TaskPath '\'
 for($i=0;$i -lt 30;$i++){Start-Sleep -Seconds 1;if([string](Task).State -ceq 'Running' -and (Ready 0 $since) -gt 0){return 'RUNNING'}}
 return 'HOLD_START_UNVERIFIED'
}
function Install-Fix{
 $stage=Join-Path $owner ('staged-releases\v13-control-'+[guid]::NewGuid().ToString('N'))
 New-Item -ItemType Directory -Path $stage -ErrorAction Stop|Out-Null
 $candidate=Join-Path $stage 'agy_v13_native_producer.py';$backup=Join-Path $stage 'prior.py'
 Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/'+$source+'/'+$rel) -OutFile $candidate -TimeoutSec 30
 $verify='import sys,pathlib,hashlib; b=pathlib.Path(sys.argv[1]).read_bytes(); assert hashlib.sha1(b"blob "+str(len(b)).encode()+b"\0"+b).hexdigest()==sys.argv[2]; compile(b,"candidate","exec"); print("VERIFIED")'
 $o=@(& py -3 -I -B -c $verify $candidate $blob 2>&1)
 if($LASTEXITCODE -ne 0 -or @($o|Where-Object{[string]$_ -ceq 'VERIFIED'}).Count -ne 1){return 'HOLD_CANDIDATE_VERIFY'}
 $target=Hash $candidate
 if((Hash $dst) -ceq $target){return ('ALREADY_FIXED_'+(Start-Control))}
 if((Hash $dst) -cne $prior){return 'HOLD_BASE_DRIFT'}
 [IO.File]::Copy($dst,$backup,$false)
 if((Hash $backup) -cne $prior){return 'HOLD_BACKUP'}
 $result=Stop-Control
 if($result -cne 'STOPPED'){return $result}
 $replaced=$false
 try{
   if((Hash $dst) -cne $prior){throw 'BASE_DRIFT'}
   $tmp=$dst+'.hotfix-'+[guid]::NewGuid().ToString('N')
   [IO.File]::Copy($candidate,$tmp,$false)
   if((Hash $tmp) -cne $target){throw 'TEMP_HASH'}
   [IO.File]::Replace($tmp,$dst,(Join-Path $stage 'displaced.py'));$replaced=$true
   if((Hash $dst) -cne $target){throw 'POST_HASH'}
   $import='import sys,pathlib;root=pathlib.Path(sys.argv[1]);sys.path[:0]=[str(root/"poc/p2-sub-discovery"),str(root/"poc/p2-aisub"),str(root/"poc/p3-vietsub-trigger")];import agy_v13_native_producer;print("IMPORTED")'
   $o=@(& py -3 -I -B -c $import $app 2>&1)
   if($LASTEXITCODE -ne 0 -or @($o|Where-Object{[string]$_ -ceq 'IMPORTED'}).Count -ne 1){throw 'IMPORT'}
 }catch{
   if($replaced){
     if((Hash $backup) -cne $prior -or @(Workers).Count){return 'HOLD_ROLLBACK'}
     $tmp=$dst+'.rollback-'+[guid]::NewGuid().ToString('N')
     [IO.File]::Copy($backup,$tmp,$false)
     [IO.File]::Replace($tmp,$dst,(Join-Path $stage 'failed-new.py'))
     if((Hash $dst) -cne $prior){return 'HOLD_ROLLBACK_HASH'}
   }
   return ('ROLLED_BACK_'+(Start-Control))
 }
 $result=Start-Control
 if($result -ceq 'RUNNING' -and (Hash $dst) -ceq $target){return 'FIX_INSTALLED_FRESH_OWNER'}
 return ('FIX_INSTALLED_'+$result)
}
$code='OWNER_CONTROL_HOLD'
try{
 if($InstallAndFix){
   # Install the same reviewed script as a reusable local command first.
   $dir=Split-Path -Parent $local
   if(-not (Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir|Out-Null}
   if(Test-Path -LiteralPath $local){
     if((Hash $local) -cne (Hash $PSCommandPath)){throw 'CONTROL_FILE_CONFLICT'}
   }else{[IO.File]::Copy($PSCommandPath,$local,$false)}
   if((Hash $local) -cne (Hash $PSCommandPath)){throw 'CONTROL_HASH'}
   $code='CONTROL_INSTALLED_'+(Install-Fix)
 }elseif($StopOwner){$code='OWNER_'+(Stop-Control)}
 elseif($StartOwner){$code='OWNER_'+(Start-Control)}
 else{
   $t=Task
   $code='OWNER_STATUS_'+([string]$t.State).ToUpperInvariant()+'_W'+@(Workers).Count+'_GAP_'+(Gap 3)
 }
}catch{
 $code='OWNER_CONTROL_EXCEPTION_'+$_.Exception.GetType().Name.ToUpperInvariant()
}
# Local direct execution never touches a previous HostOps request.
if($env:TTV_OWNER_CONTROL_RECEIPT -eq '1' -or ($PSCommandPath -ne $local -and (Test-Path -LiteralPath (Join-Path $spool 'Requests\request.json')))){
 $rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
 if($rq.schema -ne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
 $doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
 [IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
}
Write-Output $code
