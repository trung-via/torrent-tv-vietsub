# G2.3: reuse #191 paired remote protocol; input is private G2.2 receipt.
# Explicit Human playback authorization for the retained Sintel receipt only.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$history=Join-Path $spool 'History'
$outbox=Join-Path $spool 'Receipts'
$originalSource='02a02788a3d06fc28b4f7b023e0fc0294bb7a74d'
$repairSource='75bcbf030d724fa877e793c7d470bf18865d90b7'
function ReadDoc([string]$path){
 if(-not (Test-Path -LiteralPath $path -PathType Leaf)){return $null}
 $item=Get-Item -LiteralPath $path
 if($item.Length -le 0 -or $item.Length -gt 8192 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'G23_RECEIPT_FILE_INVALID'}
 return Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -Depth 12
}
function BoundReceipt([string]$source,[string]$reasonPattern){
 $boundNonces=@()
 $paths=@(Get-ChildItem -LiteralPath $history -Filter 'receipt-*.json' -File|ForEach-Object FullName)
 $paths+=Join-Path $outbox 'receipt.json'
 foreach($path in $paths){
  $r=ReadDoc $path
  if(-not $r -or $r.source_commit -cne $source -or $r.result -cne 'SUCCESS' -or $r.nonce -cnotmatch '^[a-f0-9]{32}$'){continue}
  $q=ReadDoc (Join-Path $history ('request-'+$r.nonce+'.json'))
  if(-not $q){$q=ReadDoc (Join-Path $spool 'Requests\request.json')}
  $st=ReadDoc (Join-Path $outbox ('odyssey-stage-'+$r.nonce+'.json'))
  if($q -and $st -and $q.nonce -ceq $r.nonce -and $q.source_commit -ceq $source -and $st.nonce -ceq $r.nonce -and $st.reason -cmatch $reasonPattern){$boundNonces+= $r.nonce}
 }
 $unique=@($boundNonces|Sort-Object -Unique)
 if($unique.Count -ne 1){throw 'G23_PRIOR_RECEIPT_BINDING'}
 return [string]$unique[0]
}
$RequestId=BoundReceipt $originalSource '^G2_SINTEL_NO_EXACT_MATCH_REPORTED_MS60488$'
$repairNonce=BoundReceipt $repairSource '^G2_RESUME_LIBRARY_PASS_ADDED_MS5234_TEST1$'
$LibraryReceipt=Join-Path $outbox ('g2-'+$RequestId+'.library.json')
Write-Host 'G23_RETAINED_SINTEL_RECEIPT=BOUND'
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win'){throw 'G23_WRONG_RUNNER'}
$adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
$pkg='com.spacesarmat.omp.test'
$serial=$null;$forward=$null;$ws=$null;$stage='DEVICE'
try{

 $stage='LIBRARY_RECEIPT'
 if(-not [IO.Path]::IsPathFullyQualified($LibraryReceipt) -or -not (Test-Path -LiteralPath $LibraryReceipt -PathType Leaf)){throw 'RECEIPT_MISSING'}
 $parent=Get-Item -LiteralPath (Split-Path -Parent $LibraryReceipt)
 if($parent.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'RECEIPT_ROOT_INVALID'}
 $item=Get-Item -LiteralPath $LibraryReceipt
 if($item.Length -gt 8192 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'RECEIPT_INVALID'}
 $selected=Get-Content -LiteralPath $LibraryReceipt -Raw|ConvertFrom-Json -Depth 8
 if($selected.schema -cne 'TTV-G2-LIBRARY-RECEIPT-V1' -or $selected.status -cne 'LIBRARY_READY' -or
    $selected.play -isnot [bool] -or $selected.play -or [string]$selected.request_id -cne $RequestId -or
    [string]$selected.selection_digest -cnotmatch '^[a-f0-9]{64}$' -or [string]$selected.torrent_hash -cnotmatch '^[a-f0-9]{40}$' -or
    ($selected.file_id -isnot [int] -and $selected.file_id -isnot [long]) -or $selected.file_id -lt 0 -or $selected.file_id -gt [int]::MaxValue){throw 'RECEIPT_INVALID'}
 $hash=[string]$selected.torrent_hash
 if($hash -cne '08ada5a7a6183aae1e09d831df6748d566095a10'){throw 'SINTEL_IDENTITY_MISMATCH'}
 $idx=[int]$selected.file_id
 function Ts([hashtable]$payload){
  $r=Invoke-WebRequest -Uri 'http://127.0.0.1:8090/torrents' -Method POST -ContentType 'application/json' -Body ($payload|ConvertTo-Json -Compress) -TimeoutSec 5 -NoProxy -MaximumRedirection 0
  if($r.StatusCode -ne 200){throw 'TS_HTTP'}
  return ,($r.Content|ConvertFrom-Json -Depth 50 -NoEnumerate)
 }

 $rows=Ts @{action='list'}
 $boundNonces=@($rows|Where-Object{$_ -and $_.PSObject.Properties['hash'] -and [string]$_.hash -ieq $hash})
 if($boundNonces.Count -ne 1){throw 'LIBRARY_HASH_NOT_UNIQUE'}
 $m=Ts @{action='get';hash=$hash}
 if($null -eq $m -or -not $m.PSObject.Properties['hash'] -or [string]$m.hash -ine $hash){throw 'METADATA_HASH_MISMATCH'}
 $files=@()
 if($m.PSObject.Properties['file_stats'] -and $m.file_stats){$files=@($m.file_stats)}
 elseif($m.PSObject.Properties['data'] -and $m.data){try{$d=([string]$m.data|ConvertFrom-Json -Depth 30);$files=@($d.TorrServer.Files)}catch{}}
 $videos=@($files|Where-Object{$_ -and $_.PSObject.Properties['id'] -and [string]$_.id -match '^\d+$' -and [long]$_.id -eq $idx -and $_.PSObject.Properties['path'] -and [string]$_.path -match '(?i)\.(mp4|mkv|webm|avi|mov|m4v|ts|m2ts)$' -and [string]$_.path -notmatch '(?i)(?:^|[\\/\s._-])(sample|trailer|extras?|bonus)(?:[\\/\s._-]|$)'})
 if($videos.Count -ne 1){throw 'SELECTED_VIDEO_MISMATCH'}
 Write-Host 'G23_EXACT_HASH_FILE=RESOLVED'
 $stage='DEVICE'
 $devices=@(& $adb devices 2>$null)
 $auth=@($devices|Where-Object{$_ -match '^\S+\s+device(\s|$)'})
 if($LASTEXITCODE -ne 0 -or $auth.Count -ne 1 -or @($devices|Where-Object{$_ -match '^\S+\s+(offline|unauthorized)(\s|$)'}).Count){throw 'DEVICE'}
 $serial=($auth[0] -split '\s+')[0]
 if(((& $adb -s $serial shell getprop ro.product.model 2>$null)|Out-String).Trim() -cne 'MiTV-ASTR0'){throw 'MODEL'}
 if($serial -notmatch '^((?:\d{1,3}\.){3}\d{1,3}):\d+$'){throw 'LAN_ADB_REQUIRED'}
 $ip=$Matches[1]
 if($ip -notmatch '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)'){throw 'PRIVATE_LAN_REQUIRED'}
 # Read-only reconciliation of the existing launch attempt.
 $stage='READ_ONLY'
 $dir=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\G23'
 $attempt=ReadDoc (Join-Path $dir ('g23-'+$RequestId+'-launch-attempt.json'))
 if(-not $attempt -or $attempt.attempt -cne $RequestId -or $attempt.hash -cne $hash -or $attempt.file -ne $idx -or $attempt.state -cne 'DISPATCH_STARTED'){throw 'ATTEMPT_BINDING'}
 Write-Host 'G23_AUDIT_ATTEMPT=BOUND'
 # Read the actual display and video surface, without altering playback.
 Add-Type -AssemblyName System.Drawing
 function ReadSurface{
  $list=@(& $adb -s $serial shell dumpsys SurfaceFlinger --list 2>$null)
  $layers=@($list|Where-Object{$_ -match 'SurfaceView|BLAST' -and $_ -match [regex]::Escape($pkg) -and $_ -match 'PlayerActivity'})
  $latest=[long]0;$valid=0
  foreach($layer in $layers){
   $safe=$layer.Trim()
   if($safe -notmatch '^[a-zA-Z0-9 ._()/\[\]#:=+\-]+$'){continue}
   $lines=@(& $adb -s $serial shell "dumpsys SurfaceFlinger --latency '$safe'" 2>$null)
   foreach($line in $lines){
    if($line -match '^\s*(\d+)\s+(\d+)\s+(\d+)\s*$'){
     $present=[long]$Matches[2]
     if($present -gt 0 -and $present -lt [long]::MaxValue){$valid++;$latest=[Math]::Max($latest,$present)}
    }
   }
  }
  return [pscustomobject]@{layers=$layers.Count;valid=$valid;latest=$latest}
 }
 function ReadFrame{
  $tmp=Join-Path ([IO.Path]::GetTempPath()) ('ttv-g23-'+[guid]::NewGuid().ToString('N')+'.png')
  try{
   # PowerShell 7.4+ preserves native stdout bytes on redirection.
   & $adb -s $serial exec-out screencap -p > $tmp
   if($LASTEXITCODE -ne 0){throw 'SCREEN_READ'}
   $bmp=[Drawing.Bitmap]::new($tmp)
   try{
    $values=[System.Collections.Generic.List[int]]::new()
    $lo=255;$hi=0
    for($y=1;$y -le 24;$y++){
     for($x=1;$x -le 40;$x++){
      $px=$bmp.GetPixel([int]($bmp.Width*(0.12+0.76*$x/41)),[int]($bmp.Height*(0.2+0.6*$y/25)))
      $v=[int](($px.R+$px.G+$px.B)/3)
      $values.Add($v);$lo=[Math]::Min($lo,$v);$hi=[Math]::Max($hi,$v)
     }
    }
    return [pscustomobject]@{samples=$values.ToArray();contrast=$hi-$lo}
   }finally{$bmp.Dispose()}
  }finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
 }
 function Foreground{
  $ac=((& $adb -s $serial shell dumpsys activity activities 2>$null)|Out-String)
  return [bool](@($ac -split '\r?\n'|Where-Object{$_ -match 'mResumedActivity|topResumedActivity' -and $_ -match [regex]::Escape($pkg+'/') -and $_ -match 'PlayerActivity'}).Count)
 }
 $fg1=Foreground
 if(-not $fg1){Write-Host 'G23_DISPLAY=PLAYER_NOT_FOREGROUND';exit 0}
 $a=ReadSurface
 $f1=ReadFrame
 Start-Sleep -Seconds 5
 $fg2=Foreground
 $b=ReadSurface
 $f2=ReadFrame
 Start-Sleep -Seconds 5
 $fg3=Foreground
 $c=ReadSurface
 $f3=ReadFrame
 function Difference($x,$y){
  $changed=0
  for($i=0;$i -lt $x.samples.Count;$i++){if([Math]::Abs($x.samples[$i]-$y.samples[$i]) -ge 15){$changed++}}
  return $changed
 }
 $d1=Difference $f1 $f2;$d2=Difference $f2 $f3
 Write-Host ('G23_DISPLAY_FG='+$fg1+','+$fg2+','+$fg3+' CONTRAST='+$f1.contrast+','+$f2.contrast+','+$f3.contrast+' CHANGED='+$d1+','+$d2+'/960')
 Write-Host ('G23_SURFACE_LAYERS='+$a.layers+','+$b.layers+','+$c.layers+' VALID='+$a.valid+','+$b.valid+','+$c.valid+' PRESENT_ADVANCED='+($a.latest -gt 0 -and $b.latest -gt $a.latest -and $c.latest -gt $b.latest))
 # Frame change is evidence of rendered motion, not by itself proof of film identity.
 Write-Host 'G23_DISPLAY=READ_ONLY_COMPLETE'

}catch{
 Write-Host ('G23_AUDIT_HOLD_STAGE='+$stage)
 Write-Host ('G23_AUDIT_ERROR_TYPE='+$_.Exception.GetType().Name)
 exit 1
}
