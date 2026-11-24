# Read only the exact failed AGY trained attempt. No new provider call.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'AGY_OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$prior=@(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -Filter 'receipt-*.json' -File | ForEach-Object {
 if($_.Length -le 2048 -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  try {$r=Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
   if($r.source_commit -ceq '8cda19a0d2ebed69a87bc5e3e85db5552991939d' -and $r.operation -ceq 'agy-spiderman-model-compare-1124' -and $r.nonce -cmatch '^[a-f0-9]{32}$'){$r}
  }catch{}
 }
})
$code='AGY_PRIOR_RECEIPT_NOT_UNIQUE'
if($prior.Count -eq 1){
 $run=Join-Path $env:LOCALAPPDATA ('TorrentTVVietsub\AGYWebsiteSmoke\spiderman-ab-'+$prior[0].nonce)
 $f=Join-Path (Join-Path $run 'H') 'result-private.json'
 $code='AGY_PRIOR_RESULT_NOT_AVAILABLE'
 if(Test-Path -LiteralPath $f -PathType Leaf){
  $item=Get-Item -LiteralPath $f
  if($item.Length -le 16384 -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){
   $r=Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
   if($r.status -ceq 'SEARCH_BLOCKED'){
    $s=[string]$r.reason
    $tags=@()
    foreach($http in @('401','403','406','429','503')){if($s -match ('\b'+$http+'\b')){$tags+=('HTTP_'+$http)}}
    if($s -match '(?i)captcha|challenge|cloudflare|verify.{0,20}human'){$tags+='CHALLENGE'}
    if($s -match '(?i)login|sign.in|authentication|log.in'){$tags+='LOGIN'}
    if($s -match '(?i)sandbox|network access|tool.{0,30}(unavailable|disabled)|browser.{0,30}(unavailable|disabled)|permission denied'){$tags+='TOOL_LIMIT'}
    if($s -match '(?i)timeout|timed out|connection refused|dns|resolve host'){$tags+='NETWORK'}
    if($s -match '(?i)robots\.txt|robot exclusion'){$tags+='ROBOTS'}
    if($tags.Count -eq 0){$tags+='OTHER'}
    $code='H_REPORTED_'+($tags -join '_')
   }else{$code='AGY_PRIOR_STATUS_MISMATCH'}
  }
 }
}
$chrome=Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'
if(Test-Path -LiteralPath $chrome -PathType Leaf){$code+='_CHROME_PRESENT'}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
