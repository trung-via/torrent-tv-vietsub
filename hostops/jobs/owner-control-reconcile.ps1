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
