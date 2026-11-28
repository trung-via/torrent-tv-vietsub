Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$code='G21_DIAG_LOCAL_ERROR'
try {
 $found=@(foreach($folder in @('History','Receipts')){
  Get-ChildItem -LiteralPath (Join-Path $spool $folder) -Filter 'receipt*.json' -File -ErrorAction SilentlyContinue|ForEach-Object {
   try{$r=Get-Content -LiteralPath $_.FullName -Raw|ConvertFrom-Json
    if($r.source_commit -ceq '68238a82488e7c3c6034ceedba7e7f217159233a' -and $r.result -ceq 'FAILED_NO_RETRY' -and $r.nonce -cmatch '^[a-f0-9]{32}$'){$r.nonce}
   }catch{}
  }
 })
 $ids=@($found|Sort-Object -Unique)
 if($ids.Count -ne 1){$code='G21_DIAG_RECEIPT_UNRESOLVED'}else{
  $n=$ids[0]
  $log=Join-Path $root ('LaptopHostOps\run-'+$n+'\full-owner-output.log')
  $trial=Join-Path $root ('NativeBrowserTest\g21-student-v2-metadata-'+$n)
  $hasTrial=[int](Test-Path -LiteralPath $trial -PathType Container)
  $hasTrace=[int](Test-Path -LiteralPath (Join-Path $trial 'agy-stdout.jsonl') -PathType Leaf)
  $reason='UNCLASSIFIED'
  if(Test-Path -LiteralPath $log -PathType Leaf){
   $raw=Get-Content -LiteralPath $log -Raw
   $allowed=@('G21_ACTIVE_BROWSER_CONSUMER','G21_EXISTING_G1_BROWSER_CLAIM','G21_EXISTING_CDP_NOT_READY','G21_CDP_PORT_IDENTITY_CONFLICT','G21_CDP_PROFILE_CONFLICT','G21_OTHER_CDP_CHANGED','OWNER_CONTEXT_REQUIRED','OWNER_OPS_PINNED_SOURCE_HASH_MISMATCH')
   $hits=@($allowed|Where-Object {$raw.Contains($_)})
   if($hits.Count -eq 1){$reason=$hits[0]}elseif($hits.Count -gt 1){$reason='MULTIPLE'}
  }else{$reason='NO_PRIVATE_LOG'}
  $code='G21_DIAG_'+$reason+'_DIR'+$hasTrial+'_TRACE'+$hasTrace
 }
}catch{$code='G21_DIAG_LOCAL_ERROR'}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
