# Compare installed source to the already verified standalone G2 candidate.
# No install, start/stop, provider, TV or TorrServer operation.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$d2=Join-Path $owner 'app\poc\p2-sub-discovery'
$files=[ordered]@{
 'agy_owner_warm_session.py'='9cbc45c643d99cc9655fe9a7357eafd07cd227d0'
 'agy_v13_native_producer.py'='cfd8af916f73eff84cbb46ca75f0eab184540641'
 'owner_g2_discovery.py'='2707298aaa10e38c79f44505a6853ed31336ff0d'
 'owner_g2_submit.py'='196da5a5e560faa9f780428073e67a75e956d73b'
 'owner_movie_handoff.py'='0e5d351af58d089bd53d3fd78b4a6f46509ecbbb'
 'owner_p3_p4_runtime.py'='33277f5ea67cabf95cb096ba87a6c2c659bfb6e1'
 'owner_session_bridge.py'='3b6faaeb4481ea8c1a06b0bcd777dbdad336070e'
 'agy_v13_browser_evidence.py'='37913c008f2cc521494ac076fe1e7b8fa2ba08b2'
 'start-owner-session-agent.ps1'='bcf78d240aca9a73d1f2d6bf679d2ea7fd0f085b'
}
$code='G2_DEPLOY_LOCAL_ERROR'
try{
 $t=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'
 $state=([string]$t.State).ToUpperInvariant()
 if($state -cnotin @('DISABLED','READY','RUNNING','QUEUED')){$state='UNKNOWN'}
 $mask=''
 foreach($name in $files.Keys){
  $path=if($name -ceq 'start-owner-session-agent.ps1'){Join-Path $owner $name}else{Join-Path $d2 $name}
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){$mask+='A';continue}
  $item=Get-Item -LiteralPath $path
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){$mask+='U';continue}
  $blob=(& git hash-object --no-filters -- $path 2>$null|Out-String).Trim()
  if($LASTEXITCODE -ne 0 -or $blob -cnotmatch '^[a-f0-9]{40}$'){$mask+='U'}
  elseif($blob -ceq $files[$name]){$mask+='M'}else{$mask+='D'}
 }
 # Configuration presence only. No environment secrets or values are logged.
 $launch=Join-Path $owner 'start-owner-session-agent.ps1'
 $text=if(Test-Path -LiteralPath $launch -PathType Leaf){Get-Content -LiteralPath $launch -Raw}else{''}
 function Flag([string]$name){
  if($text -match ('(?im)^\s*\$env:'+ [regex]::Escape($name) +'\s*=\s*[''"]1[''"]')){return 'L'}
  if([Environment]::GetEnvironmentVariable($name,'User') -ceq '1'){return 'U'}
  if([Environment]::GetEnvironmentVariable($name,'Machine') -ceq '1'){return 'M'}
  if([Environment]::GetEnvironmentVariable($name,'Process') -ceq '1'){return 'P'}
  return '0'
 }
 $code='G2_DEPLOY_T'+$state+'_F'+$mask+'_N'+(Flag 'TTV_NATIVE_V13')+'_W'+(Flag 'TTV_G2_WARM')
}catch{$code='G2_DEPLOY_LOCAL_ERROR'}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
