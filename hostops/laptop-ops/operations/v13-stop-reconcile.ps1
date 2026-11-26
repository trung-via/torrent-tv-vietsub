# Reconcile exact failed STOP attempt only; no task/process/file mutation.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
$base=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$owner=Join-Path $base 'OwnerBridge'
$app=Join-Path $owner 'app'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$manifest=@'
{"schema":"TTV-G1-V13-NATIVE-CANDIDATE-PACKAGE-V1","status":"SOURCE_PACKAGE_ONLY_NOT_INSTALL_AUTHORIZATION","repository":"trung-via/torrent-tv-vietsub","pr":188,"source_commit":"e1749ae60515731168bd554fe12a05031f50d040","expected_base":"5e3ce11f76828daa2d5aa72cacc7514e74dc152e","supersedes_manifest_commit":"0d952b5e7196dbf58e8b10c48ae8e2504ddcdf7e","activation":{"environment_variable":"TTV_NATIVE_V13","default":"unset","enable":"1","requires_explicit_native_acceptance":true},"files":[{"path":"poc/p2-sub-discovery/agy_v13_browser_evidence.py","expected_prior":{"state":"ABSENT"},"target":{"blob_sha":"26ebb2cc5c46e9b22f5b5e734bdd6031fa4b1b0f","sha256":"fbdabe6773bc44d490fd661dcd6845bf6746ee9c413cfb9ae75b2bd8193ec839","size":25580}},{"path":"poc/p2-sub-discovery/agy_v13_native_producer.py","expected_prior":{"state":"ABSENT"},"target":{"blob_sha":"d16a659b3ad1ddc51398109a03d7ee8f155327c3","sha256":"0b22620bfbb7dfe0ac107702a243cb2db2be1f234df8f0bcc21491170f95e8df","size":33639}},{"path":"poc/p2-sub-discovery/automatic_vietsub_flow.py","expected_prior":{"state":"EXACT_BASE_BYTES","blob_sha":"7f3da4c737fb7a3ffc5cc960d6fe7b981af261b9","sha256":"e3d1e6da2c8d08ae428f97fbae2d188e5817103dfc8bda7ed2c8a6e13f18792a","size":39082},"target":{"blob_sha":"5ae5b48da30e19192972b263a0844873500e185d","sha256":"e0edd420dccd5445481c84da36008842050e6ec61745a41b98f155136e0bccb7","size":40140}},{"path":"poc/p2-sub-discovery/dual_subtitle_catalog.py","expected_prior":{"state":"EXACT_BASE_BYTES","blob_sha":"27a0e36d2f19e19c47047aee11ad91033433d84b","sha256":"13ceb5859cfb1a9013177b373d81338a6492151983a90e07fbc761ad647d8206","size":7527},"target":{"blob_sha":"2e70090ff6bc2b252ebe8381acdf89a9edc31e0c","sha256":"c7f73ce7f1188384ca383d92de0447cada219ae33ba99b425646d2932f8fc10d","size":9802}},{"path":"poc/p2-sub-discovery/owner_p3_p4_runtime.py","expected_prior":{"state":"EXACT_BASE_BYTES","blob_sha":"40c653debe30499f280981ff194fe343729f0bc0","sha256":"a8af95433fc256082636440e74fa3343912f56b4a45b483948af00a9ce4898e3","size":8622},"target":{"blob_sha":"f8b6aa4b22647190e372d91f5bda045e7f17a326","sha256":"8f471755e5f7063e2dcc1aa672d355a132997d317f4b31c7437d6c5c903d3ad6","size":9384}},{"path":"poc/p2-sub-discovery/owner_r2_progressive_registry.py","expected_prior":{"state":"EXACT_BASE_BYTES","blob_sha":"23cbfb7d0a86a1f9542c4acef6ca7d9f793d943f","sha256":"c234749c1f9165d3436d344546b8b97089ff73c1e361aa225d0e0cb544320346","size":27620},"target":{"blob_sha":"7f9cf98e387f978f657217c517951c3dec506c99","sha256":"b600b3dcaf12fe4030c1e81967e65436256c6d259aa271fe0dd0ea0d2397952f","size":28970}},{"path":"poc/p2-sub-discovery/p3_p4_ready_registry.py","expected_prior":{"state":"EXACT_BASE_BYTES","blob_sha":"4a9bad66eadc93c072d17ad72f04425b6cbf6bcd","sha256":"7a11638820772d31e0ada488dc8c0410f94c294f1af469d45fc2beb72571a1e6","size":14027},"target":{"blob_sha":"e4eca0af41264dec07173018e3605c321a745f2b","sha256":"ff893fd4208bb644fef7c4b16558a0180bfd58ddd384411ec49ca297cc63fc72","size":14140}}],"requirements":["Verify installed full base before apply; mismatch holds. This manifest covers #188 runtime delta only, not uninstalled #186 or ancestors.","Stage exact source; verify SHA-256 and imports before apply.","Preserve legacy and native EN pointers, SRTs, checkpoints and unknown-effect claims; reconcile pending events and verify idle maintenance, rollback backup; no automatic restart/activation from this manifest.","Verify loaded PID-bound source and native opt-in at approved activation. Do not change 9444 or #187.","Retain prior verification receipts and raw evidence; old verification revisions revalidate locally, never trigger a download solely for revision drift."],"rollback":"Unset TTV_NATIVE_V13 and restore reviewed backup if needed. Native-only pointer is ignored in default mode; no cache/checkpoint deletion."}
'@|ConvertFrom-Json
$code='V13_STOP_RECONCILE_HOLD'
function ReceiptNonce([string]$commit){
 $hits=@(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -Filter 'receipt-*.json' -File|ForEach-Object{
  $v=Get-Content -LiteralPath $_.FullName -Raw|ConvertFrom-Json
  if($v.source_commit -ceq $commit -and $v.result -ceq 'SUCCESS' -and $v.nonce -cmatch '^[a-f0-9]{32}$'){$v.nonce}
 })
 if($hits.Count -ne 1){throw 'RECEIPT'}
 $hits[0]
}
function Hash($p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
try{
 $stageNonce=ReceiptNonce 'b1c1fa23dd0234554bb8b9b8d284c2f2d45aea67'
 $applyNonce=ReceiptNonce '65165d464db32f0e9f1002ee718685e1d2f033e1'
 $stage=Join-Path $owner ('staged-releases\v13-e1749ae-'+$stageNonce)
 $ledger=Get-Content -LiteralPath (Join-Path $stage 'activation-ledger.json') -Raw|ConvertFrom-Json
 $attempt=Get-Content -LiteralPath (Join-Path $stage 'apply-attempt.json') -Raw|ConvertFrom-Json
 if($attempt.nonce -cne $applyNonce -or $attempt.source -cne $manifest.source_commit -or $ledger.activation -cne 'NOT_APPLIED'){throw 'ATTEMPT'}
 $task=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'
 $tsid=[string]$task.Principal.UserId
 if($tsid -notmatch '^S-\d'){$tsid=([Security.Principal.NTAccount]::new($tsid).Translate([Security.Principal.SecurityIdentifier])).Value}
 if($tsid -cne $sid -or $task.Principal.LogonType -ine 'Interactive' -or @($task.Actions).Count -ne 1 -or [string]$task.Actions[0].Arguments -notmatch '(?i)-File\s+"([^"]+start-owner-session-agent\.ps1)"'){throw 'TASK_IDENTITY'}
 $launcher=[IO.Path]::GetFullPath($Matches[1])
 if(-not $launcher.StartsWith($owner+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'LAUNCHER'}
 $d=''
 foreach($f in $manifest.files){
  $p=Join-Path $app $f.path
  if(-not (Test-Path -LiteralPath $p)){if($f.expected_prior.state -ceq 'ABSENT'){$d+='A'}else{$d+='M'}}
  else{
   $sha=Hash $p
   if($f.expected_prior.state -ceq 'EXACT_BASE_BYTES' -and $sha -ceq $f.expected_prior.sha256){$d+='E'}
   elseif($sha -ceq $f.target.sha256){$d+='T'}else{$d+='X'}
  }
 }
 $l=if((Hash $launcher) -ceq $ledger.launcher_prior){'E'}elseif((Hash $launcher) -ceq $ledger.launcher_target){'T'}else{'X'}
 $workers=@(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe' OR Name='py.exe'"|Where-Object{[string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'})
 $valid=0
 foreach($w in $workers){
  $allowed=@((Join-Path $app 'poc\p2-sub-discovery\owner_p3_p4_entrypoint.py'),(Join-Path $app 'poc\p2-sub-discovery\owner_session_bridge.py'))
  $n=@($allowed|Where-Object{([string]$w.CommandLine).IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0}).Count
  $s=Invoke-CimMethod -InputObject $w -MethodName GetOwnerSid
  if($n -eq 1 -and $w.CreationDate -and $s.ReturnValue -eq 0 -and $s.Sid -ceq $sid){$valid++}
 }
 $inbox=Join-Path $owner 'inbox'
 $state=Join-Path $base 'P2\auto-lean120-state'
 $cache=Join-Path $base 'subtitle-trials'
 $q=@(Get-ChildItem -LiteralPath $inbox -File -Force -Filter 'event-*.json').Count
 $c=0
 foreach($f in @(Get-ChildItem -LiteralPath $inbox -File -Force -Filter 'claim-*')){
  $stem='event-'+$f.Name.Substring(6)
  if(-not (@('.blocked','.done','.review')|Where-Object{Test-Path -LiteralPath (Join-Path $inbox ($stem+$_)) -PathType Leaf})){$c++}
 }
 $i=@(Get-ChildItem -LiteralPath $state -Recurse -File -Force|Where-Object{$_.Name -eq 'active.lock' -or $_.Name -like '*.inflight'}).Count
 $n=[int](Test-Path -LiteralPath (Join-Path $cache '.native-v13\browser.pending'))
 $health=0
 try{
  $h=Get-Content -LiteralPath (Join-Path $owner 'agent-health.json') -Raw|ConvertFrom-Json
  $age=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-[long]$h.observed_utc_epoch
  if($h.state -ceq 'READY' -and $age -ge 0 -and $age -le 30 -and @($workers|Where-Object{$_.ProcessId -eq $h.pid}).Count -eq 1){$health=1}
 }catch{}
 $ts=switch([string]$task.State){'Disabled'{'D'}'Running'{'R'}'Ready'{'E'}default{'U'}}
 $code='V13_STOP_T'+$ts+'F'+$d+'L'+$l+'W'+$workers.Count+'V'+$valid+'H'+$health+'Q'+$q+'C'+$c+'I'+$i+'N'+$n
}catch{}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
