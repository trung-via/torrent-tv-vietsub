$ErrorActionPreference='Stop'
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$nonce=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes('ttv-production-movie-v1:7235850295'))).ToLowerInvariant().Substring(0,32)
$r=Get-Content -LiteralPath (Join-Path $spool 'Receipts\receipt.json') -Raw|ConvertFrom-Json
$q=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($r.nonce -cne $nonce -or $q.nonce -cne $nonce -or $r.source_commit -cne '7ec2eccfba633625d845b37264d44083173fb576' -or $q.source_commit -cne $r.source_commit -or $r.schema -cne 'TTV-LAPTOP-HOSTOPS-RECEIPT-V1'){throw 'MOVIE_ORIGINAL_RECEIPT_DRIFT'}
if($r.result -cnotin @('SUCCESS','FAILED_NO_RETRY')){throw 'MOVIE_ORIGINAL_RECEIPT_UNKNOWN'}
if($r.operation -cnotin @('NONE','owner-production-movie')){throw 'MOVIE_ORIGINAL_OPERATION_UNKNOWN'}
Write-Output ('MOVIE_ORIGINAL_RESULT='+$r.result)
Write-Output ('MOVIE_ORIGINAL_OPERATION='+$r.operation)
Write-Output ('MOVIE_STAGE_RECEIPT_PRESENT='+[bool](Test-Path -LiteralPath (Join-Path $spool ('Receipts\odyssey-stage-'+$nonce+'.json')) -PathType Leaf))
Write-Output ('MOVIE_LIBRARY_RECEIPT_PRESENT='+[bool](Test-Path -LiteralPath (Join-Path $spool ('Receipts\g2-'+$nonce+'.library.json')) -PathType Leaf))
$t=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-Laptop-HostOps' -TaskPath '\'
Write-Output ('MOVIE_HELPER_TASK_STATE='+[string]$t.State)
$a=@($t.Actions)[0]
if([string]$a.Arguments -match '-File "([^"]+)"$'){
  try {
    $helper=Get-Content -LiteralPath $Matches[1] -Raw -ErrorAction Stop
    Write-Output ('MOVIE_HELPER_OLD_BRANCH_ONLY='+[bool]($helper.Contains('git/ref/heads/hostops/owner-laptop-ops-dispatch') -and -not $helper.Contains('production-movie-v2')))
  } catch { Write-Output 'MOVIE_HELPER_READ_UNAVAILABLE' }
}
