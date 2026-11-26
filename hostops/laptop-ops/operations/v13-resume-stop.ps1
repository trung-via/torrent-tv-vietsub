# Continue the exact reconciled STOP hold; no fresh apply or replay.
param([switch]$ResumeStop)
if(-not $ResumeStop){throw 'RESUME_STOP_REQUIRED'}
$Apply=$true
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
$base=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$owner=Join-Path $base 'OwnerBridge'
$app=Join-Path $owner 'app'
$taskName='TorrentTV-Vietsub-OwnerAgent'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$manifest=@'
{"schema":"TTV-G1-V13-NATIVE-CANDIDATE-PACKAGE-V1","status":"SOURCE_PACKAGE_ONLY_NOT_INSTALL_AUTHORIZATION","repository":"trung-via/torrent-tv-vietsub","pr":188,"source_commit":"e1749ae60515731168bd554fe12a05031f50d040","expected_base":"5e3ce11f76828daa2d5aa72cacc7514e74dc152e","supersedes_manifest_commit":"0d952b5e7196dbf58e8b10c48ae8e2504ddcdf7e","activation":{"environment_variable":"TTV_NATIVE_V13","default":"unset","enable":"1","requires_explicit_native_acceptance":true},"files":[{"path":"poc/p2-sub-discovery/agy_v13_browser_evidence.py","expected_prior":{"state":"ABSENT"},"target":{"blob_sha":"26ebb2cc5c46e9b22f5b5e734bdd6031fa4b1b0f","sha256":"fbdabe6773bc44d490fd661dcd6845bf6746ee9c413cfb9ae75b2bd8193ec839","size":25580}},{"path":"poc/p2-sub-discovery/agy_v13_native_producer.py","expected_prior":{"state":"ABSENT"},"target":{"blob_sha":"d16a659b3ad1ddc51398109a03d7ee8f155327c3","sha256":"0b22620bfbb7dfe0ac107702a243cb2db2be1f234df8f0bcc21491170f95e8df","size":33639}},{"path":"poc/p2-sub-discovery/automatic_vietsub_flow.py","expected_prior":{"state":"EXACT_BASE_BYTES","blob_sha":"7f3da4c737fb7a3ffc5cc960d6fe7b981af261b9","sha256":"e3d1e6da2c8d08ae428f97fbae2d188e5817103dfc8bda7ed2c8a6e13f18792a","size":39082},"target":{"blob_sha":"5ae5b48da30e19192972b263a0844873500e185d","sha256":"e0edd420dccd5445481c84da36008842050e6ec61745a41b98f155136e0bccb7","size":40140}},{"path":"poc/p2-sub-discovery/dual_subtitle_catalog.py","expected_prior":{"state":"EXACT_BASE_BYTES","blob_sha":"27a0e36d2f19e19c47047aee11ad91033433d84b","sha256":"13ceb5859cfb1a9013177b373d81338a6492151983a90e07fbc761ad647d8206","size":7527},"target":{"blob_sha":"2e70090ff6bc2b252ebe8381acdf89a9edc31e0c","sha256":"c7f73ce7f1188384ca383d92de0447cada219ae33ba99b425646d2932f8fc10d","size":9802}},{"path":"poc/p2-sub-discovery/owner_p3_p4_runtime.py","expected_prior":{"state":"EXACT_BASE_BYTES","blob_sha":"40c653debe30499f280981ff194fe343729f0bc0","sha256":"a8af95433fc256082636440e74fa3343912f56b4a45b483948af00a9ce4898e3","size":8622},"target":{"blob_sha":"f8b6aa4b22647190e372d91f5bda045e7f17a326","sha256":"8f471755e5f7063e2dcc1aa672d355a132997d317f4b31c7437d6c5c903d3ad6","size":9384}},{"path":"poc/p2-sub-discovery/owner_r2_progressive_registry.py","expected_prior":{"state":"EXACT_BASE_BYTES","blob_sha":"23cbfb7d0a86a1f9542c4acef6ca7d9f793d943f","sha256":"c234749c1f9165d3436d344546b8b97089ff73c1e361aa225d0e0cb544320346","size":27620},"target":{"blob_sha":"7f9cf98e387f978f657217c517951c3dec506c99","sha256":"b600b3dcaf12fe4030c1e81967e65436256c6d259aa271fe0dd0ea0d2397952f","size":28970}},{"path":"poc/p2-sub-discovery/p3_p4_ready_registry.py","expected_prior":{"state":"EXACT_BASE_BYTES","blob_sha":"4a9bad66eadc93c072d17ad72f04425b6cbf6bcd","sha256":"7a11638820772d31e0ada488dc8c0410f94c294f1af469d45fc2beb72571a1e6","size":14027},"target":{"blob_sha":"e4eca0af41264dec07173018e3605c321a745f2b","sha256":"ff893fd4208bb644fef7c4b16558a0180bfd58ddd384411ec49ca297cc63fc72","size":14140}}],"requirements":["Verify installed full base before apply; mismatch holds. This manifest covers #188 runtime delta only, not uninstalled #186 or ancestors.","Stage exact source; verify SHA-256 and imports before apply.","Preserve legacy and native EN pointers, SRTs, checkpoints and unknown-effect claims; reconcile pending events and verify idle maintenance, rollback backup; no automatic restart/activation from this manifest.","Verify loaded PID-bound source and native opt-in at approved activation. Do not change 9444 or #187.","Retain prior verification receipts and raw evidence; old verification revisions revalidate locally, never trigger a download solely for revision drift."],"rollback":"Unset TTV_NATIVE_V13 and restore reviewed backup if needed. Native-only pointer is ignored in default mode; no cache/checkpoint deletion."}
'@|ConvertFrom-Json
$code='V13_INSTALL_HOLD_PREFLIGHT'
$phase='PREFLIGHT'
$mutated=[Collections.Generic.List[object]]::new()
$disabled=$false;$startAttempted=$false;$stage=$null
function Hash([string]$p){
 $item=Get-Item -LiteralPath $p -Force
 if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'FILE_INVALID'}
 (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Task {
 $t=Get-ScheduledTask -TaskName $taskName -TaskPath '\'
 $tsid=[string]$t.Principal.UserId
 if($tsid -notmatch '^S-\d'){$tsid=([Security.Principal.NTAccount]::new($tsid).Translate([Security.Principal.SecurityIdentifier])).Value}
 if($tsid -cne $sid -or [string]$t.Principal.LogonType -ine 'Interactive' -or @($t.Actions).Count -ne 1){throw 'TASK_IDENTITY'}
 $t
}
function Workers {
 @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe' OR Name='py.exe'"|Where-Object{
   [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
 })
}
function Ready([long]$oldPid,[long]$since){
 try{
  $h=Get-Content -LiteralPath (Join-Path $owner 'agent-health.json') -Raw|ConvertFrom-Json
  $age=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-[long]$h.observed_utc_epoch
  if($h.schema -cne 'TTV-OWNER-AGENT-HEALTH-V1' -or $h.state -cne 'READY' -or $age -lt 0 -or $age -gt 30 -or [long]$h.observed_utc_epoch -lt $since -or [long]$h.pid -eq $oldPid){return 0}
  $p=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$h.pid)
  if(-not $p -or ([string]$p.CommandLine).IndexOf((Join-Path $app 'poc\p2-sub-discovery\owner_p3_p4_entrypoint.py'),[StringComparison]::OrdinalIgnoreCase) -lt 0){return 0}
  $s=Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid
  if($s.ReturnValue -ne 0 -or $s.Sid -cne $sid){return 0}
  return [long]$h.pid
 }catch{return 0}
}
function Idle {
 $inbox=Join-Path $owner 'inbox'
 $state=Join-Path $base 'P2\auto-lean120-state'
 $cache=Join-Path $base 'subtitle-trials'
 foreach($d in @($inbox,$state,$cache)){
  $item=Get-Item -LiteralPath $d -Force
  if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'ROOT_INVALID'}
 }
 if(@(Get-ChildItem -LiteralPath $inbox -File -Force -Filter 'event-*.json').Count){throw 'PENDING_EVENTS'}
 foreach($c in @(Get-ChildItem -LiteralPath $inbox -File -Force -Filter 'claim-*')){
   $stem='event-'+$c.Name.Substring(6)
   if(-not (@('.blocked','.done','.review')|Where-Object{Test-Path -LiteralPath (Join-Path $inbox ($stem+$_)) -PathType Leaf})){throw 'UNRESOLVED_CLAIM'}
 }
 if(@(Get-ChildItem -LiteralPath $state -Recurse -File -Force|Where-Object{$_.Name -eq 'active.lock' -or $_.Name -like '*.inflight'}).Count){throw 'P2_INFLIGHT'}
 if(Test-Path -LiteralPath (Join-Path $cache '.native-v13\browser.pending')){throw 'NATIVE_PENDING'}
}
function CopyVerified([string]$src,[string]$dst,[string]$target,[bool]$absent,[string]$displaced){
 $tmp=Join-Path (Split-Path -Parent $dst) ('.v13-'+[Guid]::NewGuid().ToString('N')+'.tmp')
 [IO.File]::Copy($src,$tmp,$false)
 if((Hash $tmp) -cne $target){throw 'COPY_HASH'}
 if($absent){[IO.File]::Move($tmp,$dst)}else{[IO.File]::Replace($tmp,$dst,$displaced)}
 if((Hash $dst) -cne $target){throw 'POST_HASH'}
}
try{
 $hits=@(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -Filter 'receipt-*.json' -File|ForEach-Object{
   $v=Get-Content -LiteralPath $_.FullName -Raw|ConvertFrom-Json
   if($v.source_commit -ceq 'b1c1fa23dd0234554bb8b9b8d284c2f2d45aea67' -and $v.result -ceq 'SUCCESS' -and $v.nonce -cmatch '^[a-f0-9]{32}$'){$v.nonce}
 })
 if($hits.Count -ne 1){throw 'STAGE_RECEIPT'}
 $stage=Join-Path $owner ('staged-releases\v13-e1749ae-'+$hits[0])
 $ledger=Get-Content -LiteralPath (Join-Path $stage 'activation-ledger.json') -Raw|ConvertFrom-Json
 if($ledger.schema -cne 'TTV-V13-STAGED-ACTIVATION-V1' -or $ledger.source -cne $manifest.source_commit -or $ledger.stage_nonce -cne $hits[0] -or $ledger.activation -cne 'NOT_APPLIED'){throw 'LEDGER'}
 $priorHits=@(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -Filter 'receipt-*.json' -File|ForEach-Object{
   $v=Get-Content -LiteralPath $_.FullName -Raw|ConvertFrom-Json
   if($v.source_commit -ceq '65165d464db32f0e9f1002ee718685e1d2f033e1' -and $v.result -ceq 'SUCCESS' -and $v.nonce -cmatch '^[a-f0-9]{32}
 if([string]$t.Actions[0].Arguments -notmatch '(?i)-File\s+"([^"]+start-owner-session-agent\.ps1)"'){throw 'LAUNCHER'}
 $launcher=[IO.Path]::GetFullPath($Matches[1])
 if(-not $launcher.StartsWith($owner+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'LAUNCHER_SCOPE'}
 $oldPid=Ready 0 0
 # Disabled task has retained residual workers; identity is rechecked before stopping.
 $phase='P3'
 $compare=Get-Content -LiteralPath (Join-Path $stage 'gate-comparison.json') -Raw|ConvertFrom-Json
 $a=@($compare.installed)+@($compare.installed_sequence)
 $b=@($compare.candidate)+@($compare.candidate_sequence)
 if($a.Count -ne 19 -or $b.Count -ne 19){throw 'GATE_CASE_COUNT'}
 $reasonDiff=0
 for($i=0;$i -lt 19;$i++){
   if($a[$i][0] -cne $b[$i][0] -or $a[$i][2] -cne $b[$i][2]){throw 'GATE_DECISION'}
   if($a[$i][1] -cne $b[$i][1]){
     if($a[$i][0] -cne 'DISPATCH'){throw 'GATE_NONDISPATCH_REASON'}
     $reasonDiff++
   }
 }
 $gate=Join-Path $app 'poc\p3-vietsub-trigger\activation_gate.py'
 if((Hash $gate) -cne $compare.installed_gate_sha256 -or (Hash (Join-Path $stage 'rollback\poc\p3-vietsub-trigger\activation_gate.py')) -cne $compare.installed_gate_sha256){throw 'GATE_DRIFT'}
 $phase='FILES'
 $plan=@()
 foreach($f in $manifest.files){
   $dst=Join-Path $app $f.path;$src=Join-Path $stage ('candidate\'+$f.path);$saved=Join-Path $stage ('rollback\'+$f.path)
   if((Hash $src) -cne $f.target.sha256){throw 'STAGE_DRIFT'}
   $absent=$f.expected_prior.state -ceq 'ABSENT'
   $prior=if($absent){'ABSENT'}else{$f.expected_prior.sha256}
   if($absent){if(Test-Path -LiteralPath $dst){throw 'NEW_FILE_EXISTS'}}
   elseif((Hash $dst) -cne $prior -or (Hash $saved) -cne $prior){throw 'BASE_OR_BACKUP_DRIFT'}
   $plan+= [pscustomobject]@{dst=$dst;src=$src;saved=$saved;prior=$prior;target=$f.target.sha256;absent=$absent}
 }
 $src=Join-Path $stage 'candidate\start-owner-session-agent.ps1'
 $saved=Join-Path $stage 'rollback\start-owner-session-agent.ps1'
 if((Hash $launcher) -cne $ledger.launcher_prior -or (Hash $saved) -cne $ledger.launcher_prior -or (Hash $src) -cne $ledger.launcher_target){throw 'LAUNCHER_DRIFT'}
 $tokens=$null;$errors=$null
 [Management.Automation.Language.Parser]::ParseFile($src,[ref]$tokens,[ref]$errors)|Out-Null
 if(@($errors).Count){throw 'LAUNCHER_PARSE'}
 $plan+=[pscustomobject]@{dst=$launcher;src=$src;saved=$saved;prior=$ledger.launcher_prior;target=$ledger.launcher_target;absent=$false}
 $phase='IDLE'
 Idle
 if(-not $Apply){$code='V13_INSTALL_READY_F8_G19_D'+$reasonDiff+'_IDLE'}
 else{
   # No automatic replay of an earlier apply attempt, including crash windows.
   # Original attempt remains intact. Only continue the proven STOP boundary.
   [IO.File]::WriteAllText((Join-Path $stage 'resume-stop-attempt.json'),(@{nonce=$rq.nonce;prior_nonce=$attempt.nonce;source=$manifest.source_commit;state='STARTED'}|ConvertTo-Json -Compress))
   $phase='STOP'
   Idle
   if([string](Task).State -cne 'Disabled'){throw 'TASK_REENABLED'}
   $disabled=$true
   $workers=@(Workers)
   if($workers.Count -gt 4){throw 'RESIDUAL_SET_UNEXPECTED'}
   $allowed=@((Join-Path $app 'poc\p2-sub-discovery\owner_p3_p4_entrypoint.py'),(Join-Path $app 'poc\p2-sub-discovery\owner_session_bridge.py'))
   foreach($w in $workers){
      $hits=@($allowed|Where-Object{([string]$w.CommandLine).IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0})
      $who=Invoke-CimMethod -InputObject $w -MethodName GetOwnerSid
      if($hits.Count -ne 1 -or -not $w.CreationDate -or $who.ReturnValue -ne 0 -or $who.Sid -cne $sid){throw 'RESIDUAL_IDENTITY'}
   }
   foreach($w in $workers){
      Idle
      if([string](Task).State -cne 'Disabled'){throw 'TASK_REENABLED'}
      $live=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$w.ProcessId)
      if(-not $live){continue}
      $who=Invoke-CimMethod -InputObject $live -MethodName GetOwnerSid
      if([string]$live.CommandLine -cne [string]$w.CommandLine -or $live.CreationDate -ne $w.CreationDate -or $who.ReturnValue -ne 0 -or $who.Sid -cne $sid){throw 'RESIDUAL_CHANGED'}
      Stop-Process -Id ([int]$w.ProcessId) -Force -ErrorAction Stop
   }
   for($i=0;$i -lt 10 -and @(Workers).Count -gt 0;$i++){Start-Sleep -Seconds 1}
   if(@(Workers).Count -gt 0 -or [string](Task).State -cne 'Disabled'){throw 'STOP_UNVERIFIED'}
   Idle
   $phase='REPLACE'
   foreach($f in $plan){
     if([string](Task).State -cne 'Disabled' -or @(Workers).Count){throw 'OWNER_RESTARTED'}
     if($f.absent){if(Test-Path -LiteralPath $f.dst){throw 'NEW_FILE_CONFLICT'}}
     elseif((Hash $f.dst) -cne $f.prior){throw 'BASE_DRIFT'}
     $mutated.Add($f)
     CopyVerified $f.src $f.dst $f.target $f.absent (Join-Path $stage ('displaced-'+[Guid]::NewGuid().ToString('N')))
   }
   $phase='IMPORT'
   $py='import sys,pathlib;root=pathlib.Path(sys.argv[1]);sys.path[:0]=[str(root/"poc/p2-sub-discovery"),str(root/"poc/p2-aisub"),str(root/"poc/p3-vietsub-trigger")];import owner_p3_p4_entrypoint,agy_v13_native_producer,agy_v13_browser_evidence;assert agy_v13_browser_evidence.VERIFICATION_REVISION=="V13.1-BR03-1";print("V13_INSTALLED_IMPORT_PASS")'
   $out=@(& py -3 -I -B -c $py $app 2>&1)
   if($LASTEXITCODE -ne 0 -or @($out|Where-Object{[string]$_ -ceq 'V13_INSTALLED_IMPORT_PASS'}).Count -ne 1){throw 'IMPORT'}
   Idle
   $phase='START'
   $since=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-1
   $startAttempted=$true
   Enable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
   $disabled=$false
   Start-ScheduledTask -TaskName $taskName -TaskPath '\'
   $newPid=0
   for($i=0;$i -lt 30;$i++){
     Start-Sleep -Seconds 1
     if([string](Task).State -ceq 'Running'){$newPid=Ready $oldPid $since;if($newPid -gt 0){break}}
   }
   if($newPid -le 0){throw 'FRESH_HEARTBEAT'}
   foreach($f in $plan){if((Hash $f.dst) -cne $f.target){throw 'POST_START_DRIFT'}}
   $code='V13_INSTALL_RESUMED_F8_FRESH_OWNER'
   $ledger.activation='APPLIED'
   [IO.File]::WriteAllText((Join-Path $stage 'activation-ledger.json'),($ledger|ConvertTo-Json -Compress))
 }
}catch{
 $code='V13_INSTALL_HOLD_'+$phase
 # If startup was attempted, preserve evidence and require reconciliation; never replay/kill uncertain work.
 if($Apply -and $disabled -and -not $startAttempted){
   try{
     if(@(Workers).Count -eq 0 -and [string](Task).State -ceq 'Disabled'){
       Idle
       for($i=$mutated.Count-1;$i -ge 0;$i--){
         $f=$mutated[$i]
         if($f.absent){
           if(Test-Path -LiteralPath $f.dst){
             if((Hash $f.dst) -cne $f.target){throw 'ROLLBACK_DRIFT'}
             [IO.File]::Move($f.dst,(Join-Path $stage ('rollback-added-'+[Guid]::NewGuid().ToString('N'))))
           }
         }elseif((Hash $f.dst) -ne $f.prior){
           if((Hash $f.dst) -cne $f.target -or (Hash $f.saved) -cne $f.prior){throw 'ROLLBACK_DRIFT'}
           CopyVerified $f.saved $f.dst $f.prior $false (Join-Path $stage ('rollback-displaced-'+[Guid]::NewGuid().ToString('N')))
         }
       }
       Enable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
       Start-ScheduledTask -TaskName $taskName -TaskPath '\'
       $code='V13_INSTALL_ROLLBACK_STARTED_VERIFY_REQUIRED'
     }
   }catch{$code='V13_INSTALL_ROLLBACK_HOLD'}
 }
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
){$v.nonce}
 })
 if($priorHits.Count -ne 1){throw 'PRIOR_RECEIPT'}
 $attempt=Get-Content -LiteralPath (Join-Path $stage 'apply-attempt.json') -Raw|ConvertFrom-Json
 if($attempt.nonce -cne $priorHits[0] -or $attempt.source -cne $manifest.source_commit -or $attempt.state -cne 'STARTED'){throw 'PRIOR_ATTEMPT'}
 if(Test-Path -LiteralPath (Join-Path $stage 'resume-stop-attempt.json')){throw 'RESUME_ALREADY_ATTEMPTED'}
 $t=Task
 if([string]$t.State -cne 'Disabled'){throw 'RECONCILED_TASK_NOT_DISABLED'}
 if([string]$t.Actions[0].Arguments -notmatch '(?i)-File\s+"([^"]+start-owner-session-agent\.ps1)"'){throw 'LAUNCHER'}
 $launcher=[IO.Path]::GetFullPath($Matches[1])
 if(-not $launcher.StartsWith($owner+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'LAUNCHER_SCOPE'}
 $oldPid=Ready 0 0
 if($oldPid -le 0){throw 'HEARTBEAT'}
 $phase='P3'
 $compare=Get-Content -LiteralPath (Join-Path $stage 'gate-comparison.json') -Raw|ConvertFrom-Json
 $a=@($compare.installed)+@($compare.installed_sequence)
 $b=@($compare.candidate)+@($compare.candidate_sequence)
 if($a.Count -ne 19 -or $b.Count -ne 19){throw 'GATE_CASE_COUNT'}
 $reasonDiff=0
 for($i=0;$i -lt 19;$i++){
   if($a[$i][0] -cne $b[$i][0] -or $a[$i][2] -cne $b[$i][2]){throw 'GATE_DECISION'}
   if($a[$i][1] -cne $b[$i][1]){
     if($a[$i][0] -cne 'DISPATCH'){throw 'GATE_NONDISPATCH_REASON'}
     $reasonDiff++
   }
 }
 $gate=Join-Path $app 'poc\p3-vietsub-trigger\activation_gate.py'
 if((Hash $gate) -cne $compare.installed_gate_sha256 -or (Hash (Join-Path $stage 'rollback\poc\p3-vietsub-trigger\activation_gate.py')) -cne $compare.installed_gate_sha256){throw 'GATE_DRIFT'}
 $phase='FILES'
 $plan=@()
 foreach($f in $manifest.files){
   $dst=Join-Path $app $f.path;$src=Join-Path $stage ('candidate\'+$f.path);$saved=Join-Path $stage ('rollback\'+$f.path)
   if((Hash $src) -cne $f.target.sha256){throw 'STAGE_DRIFT'}
   $absent=$f.expected_prior.state -ceq 'ABSENT'
   $prior=if($absent){'ABSENT'}else{$f.expected_prior.sha256}
   if($absent){if(Test-Path -LiteralPath $dst){throw 'NEW_FILE_EXISTS'}}
   elseif((Hash $dst) -cne $prior -or (Hash $saved) -cne $prior){throw 'BASE_OR_BACKUP_DRIFT'}
   $plan+= [pscustomobject]@{dst=$dst;src=$src;saved=$saved;prior=$prior;target=$f.target.sha256;absent=$absent}
 }
 $src=Join-Path $stage 'candidate\start-owner-session-agent.ps1'
 $saved=Join-Path $stage 'rollback\start-owner-session-agent.ps1'
 if((Hash $launcher) -cne $ledger.launcher_prior -or (Hash $saved) -cne $ledger.launcher_prior -or (Hash $src) -cne $ledger.launcher_target){throw 'LAUNCHER_DRIFT'}
 $tokens=$null;$errors=$null
 [Management.Automation.Language.Parser]::ParseFile($src,[ref]$tokens,[ref]$errors)|Out-Null
 if(@($errors).Count){throw 'LAUNCHER_PARSE'}
 $plan+=[pscustomobject]@{dst=$launcher;src=$src;saved=$saved;prior=$ledger.launcher_prior;target=$ledger.launcher_target;absent=$false}
 $phase='IDLE'
 Idle
 if(-not $Apply){$code='V13_INSTALL_READY_F8_G19_D'+$reasonDiff+'_IDLE'}
 else{
   # No automatic replay of an earlier apply attempt, including crash windows.
   [IO.File]::WriteAllText((Join-Path $stage 'apply-attempt.json'),(@{nonce=$rq.nonce;source=$manifest.source_commit;state='STARTED'}|ConvertTo-Json -Compress))
   $phase='STOP'
   Idle
   Disable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
   $disabled=$true
   Stop-ScheduledTask -TaskName $taskName -TaskPath '\'
   for($i=0;$i -lt 20 -and @(Workers).Count -gt 0;$i++){Start-Sleep -Seconds 1}
   if(@(Workers).Count -gt 0 -or [string](Task).State -cne 'Disabled'){throw 'STOP_UNVERIFIED'}
   Idle
   $phase='REPLACE'
   foreach($f in $plan){
     if([string](Task).State -cne 'Disabled' -or @(Workers).Count){throw 'OWNER_RESTARTED'}
     if($f.absent){if(Test-Path -LiteralPath $f.dst){throw 'NEW_FILE_CONFLICT'}}
     elseif((Hash $f.dst) -cne $f.prior){throw 'BASE_DRIFT'}
     $mutated.Add($f)
     CopyVerified $f.src $f.dst $f.target $f.absent (Join-Path $stage ('displaced-'+[Guid]::NewGuid().ToString('N')))
   }
   $phase='IMPORT'
   $py='import sys,pathlib;root=pathlib.Path(sys.argv[1]);sys.path[:0]=[str(root/"poc/p2-sub-discovery"),str(root/"poc/p2-aisub"),str(root/"poc/p3-vietsub-trigger")];import owner_p3_p4_entrypoint,agy_v13_native_producer,agy_v13_browser_evidence;assert agy_v13_browser_evidence.VERIFICATION_REVISION=="V13.1-BR03-1";print("V13_INSTALLED_IMPORT_PASS")'
   $out=@(& py -3 -I -B -c $py $app 2>&1)
   if($LASTEXITCODE -ne 0 -or @($out|Where-Object{[string]$_ -ceq 'V13_INSTALLED_IMPORT_PASS'}).Count -ne 1){throw 'IMPORT'}
   Idle
   $phase='START'
   $since=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-1
   $startAttempted=$true
   Enable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
   $disabled=$false
   Start-ScheduledTask -TaskName $taskName -TaskPath '\'
   $newPid=0
   for($i=0;$i -lt 30;$i++){
     Start-Sleep -Seconds 1
     if([string](Task).State -ceq 'Running'){$newPid=Ready $oldPid $since;if($newPid -gt 0){break}}
   }
   if($newPid -le 0){throw 'FRESH_HEARTBEAT'}
   foreach($f in $plan){if((Hash $f.dst) -cne $f.target){throw 'POST_START_DRIFT'}}
   $code='V13_INSTALL_APPLIED_F8_FRESH_OWNER'
   $ledger.activation='APPLIED'
   [IO.File]::WriteAllText((Join-Path $stage 'activation-ledger.json'),($ledger|ConvertTo-Json -Compress))
 }
}catch{
 $code='V13_INSTALL_HOLD_'+$phase
 # If startup was attempted, preserve evidence and require reconciliation; never replay/kill uncertain work.
 if($Apply -and $disabled -and -not $startAttempted){
   try{
     if(@(Workers).Count -eq 0 -and [string](Task).State -ceq 'Disabled'){
       Idle
       for($i=$mutated.Count-1;$i -ge 0;$i--){
         $f=$mutated[$i]
         if($f.absent){
           if(Test-Path -LiteralPath $f.dst){
             if((Hash $f.dst) -cne $f.target){throw 'ROLLBACK_DRIFT'}
             [IO.File]::Move($f.dst,(Join-Path $stage ('rollback-added-'+[Guid]::NewGuid().ToString('N'))))
           }
         }elseif((Hash $f.dst) -ne $f.prior){
           if((Hash $f.dst) -cne $f.target -or (Hash $f.saved) -cne $f.prior){throw 'ROLLBACK_DRIFT'}
           CopyVerified $f.saved $f.dst $f.prior $false (Join-Path $stage ('rollback-displaced-'+[Guid]::NewGuid().ToString('N')))
         }
       }
       Enable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
       Start-ScheduledTask -TaskName $taskName -TaskPath '\'
       $code='V13_INSTALL_ROLLBACK_STARTED_VERIFY_REQUIRED'
     }
   }catch{$code='V13_INSTALL_ROLLBACK_HOLD'}
 }
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
