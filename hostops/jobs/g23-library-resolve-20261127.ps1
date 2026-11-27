# Owner-approved OMP pairing through existing UI and protocol. Keep all secrets local.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win'){throw 'G23_WRONG_RUNNER'}
$adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
$pkg='com.spacesarmat.omp.test'
$serial=$null;$forward=$null;$ws=$null;$stage='DEVICE'
try{
 $devices=@(& $adb devices 2>$null)
 $auth=@($devices|Where-Object{$_ -match '^\S+\s+device(\s|$)'})
 if($LASTEXITCODE -ne 0 -or $auth.Count -ne 1 -or @($devices|Where-Object{$_ -match '^\S+\s+(offline|unauthorized)(\s|$)'}).Count){throw 'DEVICE'}
 $serial=($auth[0] -split '\s+')[0]
 if(((& $adb -s $serial shell getprop ro.product.model 2>$null)|Out-String).Trim() -cne 'MiTV-ASTR0'){throw 'MODEL'}
 if($serial -notmatch '^((?:\d{1,3}\.){3}\d{1,3}):\d+$'){throw 'LAN_ADB_REQUIRED'}
 $ip=$Matches[1]
 if($ip -notmatch '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)'){throw 'PRIVATE_LAN_REQUIRED'}
 $stage='POWER'
 $power=((& $adb -s $serial shell dumpsys power 2>$null)|Out-String)
 if($power -match 'mWakefulness=(Asleep|Dozing)' -and $power -match 'Display Power:\s*state=OFF'){
  & $adb -s $serial shell input keyevent KEYCODE_POWER 2>$null|Out-Null
  if($LASTEXITCODE -ne 0){throw 'POWER'}
  Start-Sleep -Seconds 4
  $power=((& $adb -s $serial shell dumpsys power 2>$null)|Out-String)
 }
 if($power -notmatch 'mWakefulness=Awake' -or $power -notmatch 'Display Power:\s*state=ON'){throw 'POWER_UNVERIFIED'}
 Write-Host 'G23_TV_AWAKE=YES'
 $stage='OMP_FOREGROUND'
 $act=((& $adb -s $serial shell dumpsys activity activities 2>$null)|Out-String)
 $resumed=@($act -split '\r?\n'|Where-Object{$_ -match 'mResumedActivity|topResumedActivity'})
 if(-not @($resumed|Where-Object{$_ -match [regex]::Escape($pkg+'/')}).Count){
  $a=((& $adb -s $serial shell am start -W -n ($pkg+'/com.spacesarmat.omp.MainActivity') 2>$null)|Out-String)
  if($LASTEXITCODE -ne 0 -or $a -match '(Error|Exception|Status:\s*timeout)'){throw 'START'}
  Start-Sleep -Seconds 3
 }
 $stage='OMP_INFO'
 $base=$null
 foreach($port in 8095..8099){
  try{
   $u='http://'+$ip+':'+$port
   $info=Invoke-RestMethod -Uri ($u+'/omp/info') -TimeoutSec 3 -MaximumRedirection 0 -NoProxy
   if($null -ne $info.PSObject.Properties['paired'] -and $null -ne $info.PSObject.Properties['version'] -and $null -ne $info.PSObject.Properties['foreground']){$base=$u;break}
  }catch{}
 }
 if(-not $base){throw 'API'}
 Write-Host 'G23_OMP_INFO=PASS'
 $stage='TOKEN_STORE'
 if(-not $env:LOCALAPPDATA){throw 'NO_LOCAL_PROFILE'}
 $dir=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\G23'
 $path=Join-Path $dir 'omp-remote-token.dpapi'
 $token=$null
 if(Test-Path -LiteralPath $path){
  $secure=(Get-Content -LiteralPath $path -Raw).Trim()|ConvertTo-SecureString
  $token=[System.Net.NetworkCredential]::new('', $secure).Password
  if($token -notmatch '^[a-f0-9]{32}$'){throw 'STORED_TOKEN_INVALID'}
  $i=Invoke-RestMethod -Uri ($base+'/omp/info') -Headers @{Authorization=('Bearer '+$token)} -TimeoutSec 4 -MaximumRedirection 0 -NoProxy
  if($i.paired -ne $true){throw 'STORED_TOKEN_NOT_PAIRED'}
  Write-Host 'G23_PAIR=REUSED_VERIFIED'
 }else{throw 'EXISTING_TOKEN_REQUIRED'}
 Write-Host 'G23_TOKEN_SCOPE=WINDOWS_RUNNER_DPAPI_CURRENT_USER'
 $stage='LIBRARY_READ'
 function Ts([hashtable]$payload){
  $r=Invoke-WebRequest -Uri 'http://127.0.0.1:8090/torrents' -Method POST -ContentType 'application/json' -Body ($payload|ConvertTo-Json -Compress) -TimeoutSec 5 -NoProxy -MaximumRedirection 0
  if($r.StatusCode -ne 200){throw 'TS_HTTP'}
  return ,($r.Content|ConvertFrom-Json -Depth 50 -NoEnumerate)
 }
 $rows=Ts @{action='list'}
 if($null -eq $rows){$rows=@()}
 if($rows -isnot [array]){throw 'TS_LIST_SCHEMA'}
 $valid=@($rows|Where-Object{$null -ne $_ -and $_.PSObject.Properties['hash'] -and [string]$_.hash -match '^[a-fA-F0-9]{40}$'})
 Write-Host ('G23_LIBRARY_COUNT='+$rows.Length)
 Write-Host ('G23_VALID_HASH_COUNT='+$valid.Count)
 $stage='FIXTURE_RESOLVE'
 $openTitles=@('Big Buck Bunny','Sintel','Tears of Steel','Elephants Dream','Cosmos Laundromat','Spring')
 $possible=@()
 foreach($row in $valid){
  if(-not $row.PSObject.Properties['title']){continue}
  $title=[string]$row.title
  $normalized=($title -replace '[._-]+',' ' -replace '\s+',' ').Trim()
  foreach($label in $openTitles){
   if($normalized -match ('(?i)(?:^|\b)'+[regex]::Escape($label)+'(?:\b|$)')){
    $possible+=@{row=$row;label=$label};break
   }
  }
 }
 Write-Host ('G23_POSSIBLE_OPEN_FIXTURE_COUNT='+$possible.Count)
 $resolved=0
 foreach($p in $possible){
  $m=Ts @{action='get';hash=[string]$p.row.hash}
  if($null -eq $m -or -not $m.PSObject.Properties['hash'] -or [string]$m.hash -ine [string]$p.row.hash){continue}
  $files=@()
  if($m.PSObject.Properties['file_stats'] -and $m.file_stats){$files=@($m.file_stats)}
  elseif($m.PSObject.Properties['data'] -and $m.data){
   try{$d=([string]$m.data|ConvertFrom-Json -Depth 30);$files=@($d.TorrServer.Files)}catch{}
  }
  $video=@($files|Where-Object{$_ -and $_.PSObject.Properties['id'] -and [string]$_.id -match '^\d+$' -and $_.PSObject.Properties['path'] -and [string]$_.path -match '(?i)\.(mp4|mkv|webm|avi|mov|m4v)$'})
  if($video.Count -eq 1){$resolved++}
 }
 Write-Host ('G23_POSSIBLE_FIXTURE_SINGLE_VIDEO_COUNT='+$resolved)
 # No arbitrary media selection: title match alone does not establish fixture authorization.
 Write-Host 'G23_PLAY=NOT_ATTEMPTED_FIXTURE_AUTHORIZATION_UNVERIFIED'
}catch{
 Write-Host ('G23_HOLD_STAGE='+$stage)
 Write-Host ('G23_ERROR_TYPE='+$_.Exception.GetType().Name)
 exit 1
}finally{
 if($ws){$ws.Dispose()}
 if($serial -and $forward -match '^\d{1,5}$'){& $adb -s $serial forward --remove ('tcp:'+$forward) 2>$null|Out-Null}
}
