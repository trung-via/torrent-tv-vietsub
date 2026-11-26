# Read-only reconciliation of exact timed-out Owner Control request. No new spool request.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win'){throw 'WRONG_RUNNER'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$req=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($req.source_commit -cne '40b23c6556bc4258b69392e6990ba4bca9e16cf3' -or $req.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_DRIFT'}
foreach($name in @('TorrentTV-Vietsub-Laptop-HostOps','TorrentTV-Vietsub-OwnerAgent')){
 try{$t=Get-ScheduledTask -TaskName $name -TaskPath '\';$i=Get-ScheduledTaskInfo -TaskName $name -TaskPath '\';Write-Output ('TASK_'+$name+'='+$t.State+'_RESULT_'+$i.LastTaskResult)}catch{Write-Output ('TASK_'+$name+'=UNAVAILABLE')}
}
$files=@((Join-Path $spool 'Receipts\receipt.json'),(Join-Path $spool ('History\receipt-'+$req.nonce+'.json')))
$found=$false
foreach($f in $files){
 if(Test-Path -LiteralPath $f -PathType Leaf){
  $r=Get-Content -LiteralPath $f -Raw|ConvertFrom-Json
  if($r.nonce -ceq $req.nonce -and $r.source_commit -ceq $req.source_commit -and $r.result -cin @('SUCCESS','FAILED_NO_RETRY')){Write-Output ('EXACT_RECEIPT='+$r.result);$found=$true}
 }
}
if(-not $found){Write-Output 'EXACT_RECEIPT=MISSING'}
$f=Join-Path $spool ('Receipts\odyssey-stage-'+$req.nonce+'.json')
if(Test-Path -LiteralPath $f -PathType Leaf){
 $r=Get-Content -LiteralPath $f -Raw|ConvertFrom-Json
 if($r.nonce -ceq $req.nonce -and $r.reason -cmatch '^[A-Z0-9_]{3,120}$'){Write-Output ('EXACT_STAGE='+$r.reason)}
}else{Write-Output 'EXACT_STAGE=MISSING'}

# Observe task permissions and exact local files, only if already readable.
$helperTask=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-Laptop-HostOps' -TaskPath '\'
$ownerTask=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'
$service=New-Object -ComObject 'Schedule.Service'
$service.Connect()
foreach($t in @($helperTask,$ownerTask)){
 try{
   $sd=[Security.AccessControl.RawSecurityDescriptor]::new($service.GetFolder('\').GetTask($t.TaskName).GetSecurityDescriptor(4))
   $aces=@($sd.DiscretionaryAcl|Where-Object{$_.SecurityIdentifier.Value -ceq 'S-1-5-20'}|ForEach-Object{ '{0:X8}' -f $_.AccessMask })
   Write-Output ('TASK_RIGHTS_'+$t.TaskName+'='+($aces -join ','))
 }catch{Write-Output ('TASK_RIGHTS_'+$t.TaskName+'=UNREADABLE')}
}
$arg=[string]$helperTask.Actions[0].Arguments
if($arg -match '-File\s+"([^"]+\\OwnerBridge\\Maintenance\\owner-laptop-ops-helper\.ps1)"'){
 $helper=$Matches[1];$maintenance=Split-Path -Parent $helper;$root=Split-Path -Parent $maintenance
 foreach($pair in @(@('HELPER',$helper),@('CONTROL',(Join-Path $maintenance 'owner-control.ps1')),@('PRODUCER',(Join-Path $root 'app\poc\p2-sub-discovery\agy_v13_native_producer.py')))){
  try{
   $h=(Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
   Write-Output ('FILE_'+$pair[0]+'_SHA256='+$h)
  }catch{Write-Output ('FILE_'+$pair[0]+'_STATUS=UNREADABLE_OR_ABSENT')}
 }
 $run=Join-Path (Split-Path -Parent $root) ('LaptopHostOps\run-'+$req.nonce)
 foreach($pair in @(@('RUN_MANIFEST','manifest.json'),@('RUN_SCRIPT','operation.ps1'),@('RUN_LOG','full-owner-output.log'))){
   try{$f=Get-Item -LiteralPath (Join-Path $run $pair[1]) -ErrorAction Stop;Write-Output ('PRIVATE_'+$pair[0]+'_BYTES='+$f.Length)}catch{Write-Output ('PRIVATE_'+$pair[0]+'=UNREADABLE_OR_ABSENT')}
 }
}else{Write-Output 'HELPER_PATH=UNRECOGNIZED'}
# Query only exact task event IDs and result codes, not raw event messages.
try{
 $events=@(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TaskScheduler/Operational';StartTime=([DateTimeOffset]::FromUnixTimeSeconds([long]$req.requested_utc_epoch).LocalDateTime.AddSeconds(-5));Id=100,101,102,103,111,129,200,201,202,203,322,329} -ErrorAction Stop)
 foreach($ev in @($events|Where-Object{$_.Message -like '*TorrentTV-Vietsub-Laptop-HostOps*'}|Select-Object -First 16)){
   Write-Output ('HELPER_EVENT='+$ev.Id+'_'+$ev.TimeCreated.ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))
 }
}catch{Write-Output 'HELPER_EVENTS=UNAVAILABLE'}
