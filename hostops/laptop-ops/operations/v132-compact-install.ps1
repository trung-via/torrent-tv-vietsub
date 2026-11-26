# Owner-approved V13.2 recipe-only install; preserve all event, provider and translation state.
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
$source='500f15b26237638fa6ebaeae5f6f1d3b101a7112'
$blob='2bbc0de3cda88e905852567ddab0c5d93cc9c006'
$stage=Join-Path $owner ('staged-releases\v132-compact-'+$rq.nonce)
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
 @{name='agy_v13_browser_evidence.py';old='8fdc55c9e90d56800f7423468a4f62a78515b731';new='2e2233cd151398ed2841461e0873df2e0fafac3d'}
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
 $import='import sys,pathlib;root=pathlib.Path(sys.argv[1]);sys.path[:0]=[str(root/"poc/p2-sub-discovery"),str(root/"poc/p2-aisub"),str(root/"poc/p3-vietsub-trigger")];from agy_v13_browser_evidence import RECIPE,RECIPE_V13_1,RECIPE_VERSION,VERIFICATION_REVISION;from agy_v13_native_producer import NativeBrowserProducer;assert RECIPE_VERSION=="V13.2" and VERIFICATION_REVISION=="V13.1-BR05-1" and len(RECIPE)<len(RECIPE_V13_1)*0.75;print("IMPORTED")'
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
 $code='V132_COMPACT_F1_FRESH_OWNER'
}catch{
 $code='V132_COMPACT_HOLD_'+$phase
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
   }catch{$code='V132_COMPACT_ROLLBACK_HOLD'}
 }
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
