# Owner read-only current request diagnostic; only bounded, fixed enum evidence leaves Owner.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$code='R_TV_READ_UNAVAILABLE'
try {
 $adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
 if(-not (Test-Path -LiteralPath $adb -PathType Leaf)){throw 'ADB_MISSING'}
 if(@(Get-Process -Name adb -ErrorAction SilentlyContinue).Count -eq 0){throw 'ADB_NOT_RUNNING'}
 $devices=@(& $adb devices 2>$null)
 if($LASTEXITCODE -ne 0){throw 'ADB_LIST_FAILED'}
 $rows=@($devices|Where-Object{$_ -match '^\S+\s+device(\s|$)'})
 if($rows.Count -ne 1){$code='R_TV_DEVICE_UNBOUND';throw 'DEVICE_UNBOUND'}
 $serial=($rows[0] -split '\s+')[0]
 $model=(& $adb -s $serial shell getprop ro.product.model 2>$null|Out-String).Trim()
 $abi=(& $adb -s $serial shell getprop ro.product.cpu.abi 2>$null|Out-String).Trim()
 if($model -cne 'MiTV-ASTR0' -or $abi -cne 'armeabi-v7a'){$code='R_TV_IDENTITY_MISMATCH';throw 'IDENTITY'}
 $pkg='com.spacesarmat.omp.test'
 $appPid=(& $adb -s $serial shell pidof $pkg 2>$null|Out-String).Trim()
 if($appPid -notmatch '^\d+$'){$code='R_TV_APP_NOT_RUNNING';throw 'APP_PID'}
 $log=@(& $adb -s $serial logcat -d -t 3000 --pid=$appPid -s 'TorrentTV-Vietsub:I' 'AndroidRuntime:E' 2>$null)
 if($LASTEXITCODE -ne 0){throw 'LOGCAT'}
 $session=@($log|Where-Object{$_ -match 'P4_TV_SESSION_ACCEPTED\s*$'}).Count
 $offer=@($log|Where-Object{$_ -match 'P4_TV_OFFER_RECEIVED_UNVERIFIED\s*$'}).Count
 $overlay=@($log|Where-Object{$_ -match 'P4_TV_OVERLAY_INSTALLED\s*$'}).Count
 $saved=@($log|Where-Object{$_ -match 'P4_TV_SAVED_OVERLAY_RESTORED\s*$'}).Count
 $notready=@($log|Where-Object{$_ -match 'P4_TV_ACTIVATE_NOT_READY\s*$'}).Count
 $crash=@($log|Where-Object{$_ -match 'FATAL EXCEPTION'}).Count
 $last='N'
 foreach($line in $log){
   if($line -match 'P4_TV_SESSION_ACCEPTED\s*$'){$last='S'}
   elseif($line -match 'P4_TV_OFFER_RECEIVED_UNVERIFIED\s*$'){$last='O'}
   elseif($line -match 'P4_TV_OVERLAY_INSTALLED\s*$'){$last='I'}
   elseif($line -match 'P4_TV_SAVED_OVERLAY_RESTORED\s*$'){$last='R'}
 }
 $code="R_TV_S$session"+"O$offer"+"I$overlay"+"R$saved"+"N$notready"+"E$crash"+"L$last"
} catch {
 if($code -eq 'R_TV_READ_UNAVAILABLE'){
   if($_.Exception.Message -eq 'ADB_MISSING'){$code='R_TV_ADB_MISSING'}
   elseif($_.Exception.Message -eq 'ADB_NOT_RUNNING'){$code='R_TV_ADB_NOT_RUNNING'}
 }
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
