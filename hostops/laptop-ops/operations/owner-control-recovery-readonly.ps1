# Owner-local read-only audit of archived timeout. Never starts provider or changes task.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$code='RECON_UNKNOWN'
try{
 $old=@(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -File -Filter 'unknown-effect-*.json'|ForEach-Object{Get-Content -LiteralPath $_.FullName -Raw|ConvertFrom-Json}|Where-Object{$_.source_commit -ceq '40b23c6556bc4258b69392e6990ba4bca9e16cf3' -and $_.state -ceq 'ARCHIVED_NO_REPLAY'})
 if($old.Count -ne 1 -or $old[0].nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'ARCHIVE_MISSING'}
 $base=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
 $owner=Join-Path $base 'OwnerBridge'
 $local=Join-Path $owner 'Maintenance\owner-control.ps1'
 $producer=Join-Path $owner 'app\poc\p2-sub-discovery\agy_v13_native_producer.py'
 $run=Join-Path $base ('LaptopHostOps\run-'+$old[0].nonce)
 $control='MISSING'
 if(Test-Path -LiteralPath $local -PathType Leaf){
   $saved=Join-Path $run 'operation.ps1'
   $control='OTHER'
   if((Test-Path -LiteralPath $saved -PathType Leaf) -and (Get-FileHash -LiteralPath $saved).Hash -ceq (Get-FileHash -LiteralPath $local).Hash){$control='MATCH'}
 }
 $prod='OTHER'
 if(Test-Path -LiteralPath $producer -PathType Leaf){
   $hash=(Get-FileHash -LiteralPath $producer -Algorithm SHA256).Hash.ToLowerInvariant()
   if($hash -ceq '0b22620bfbb7dfe0ac107702a243cb2db2be1f234df8f0bcc21491170f95e8df'){$prod='OLD'}
   else{
     $py='import hashlib,pathlib,sys;b=pathlib.Path(sys.argv[1]).read_bytes();print(hashlib.sha1(b"blob "+str(len(b)).encode()+b"\0"+b).hexdigest())'
     $out=@(& py -3 -I -B -c $py $producer)
     if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and $out[0] -ceq 'c003713574b8650601c37ed18789fd4bfd423181'){$prod='FIXED'}
   }
 }
 $log=Join-Path $run 'full-owner-output.log'
 $logStatus='MISSING'
 if(Test-Path -LiteralPath $log -PathType Leaf){
   $tail=(Get-Content -LiteralPath $log -Tail 80 -ErrorAction Stop|Out-String)
   if($tail -match 'CHOOSE_ONE_ACTION'){$logStatus='PARAM'}
   elseif($tail -match 'OWNER_CONTROL_EXCEPTION_([A-Z0-9_]{3,45})'){$logStatus='EXCEPTION'}
   elseif($tail -match 'CONTROL_INSTALLED_([A-Z0-9_]{3,45})'){$logStatus=$Matches[1]}
   elseif($tail -match 'OWNER_OPS_FAILURE'){$logStatus='FAILED'}
   elseif([string]::IsNullOrWhiteSpace($tail)){$logStatus='EMPTY'}
   else{$logStatus='OTHER'}
 }
 $task=(Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\').State.ToString().ToUpperInvariant()
 $code='RECON_C_'+$control+'_P_'+$prod+'_T_'+$task+'_L_'+$logStatus
}catch{$code='RECON_READ_UNAVAILABLE'}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
