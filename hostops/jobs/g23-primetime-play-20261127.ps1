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
 $stage='SELECT_OWNER_CHOICE'
 $matched=@($valid|Where-Object{
  $title=if($_.PSObject.Properties['title']){[string]$_.title}else{''}
  $name=if($_.PSObject.Properties['name']){[string]$_.name}else{''}
  $n=(($title+' '+$name) -replace '[._-]+',' ')
  $n -match '(?i)\bprime\s*time\b' -and $n -match '\b2026\b'
 })
 Write-Host ('G23_REQUESTED_TITLE_MATCH_COUNT='+$matched.Count)
 if($matched.Count -ne 1){Write-Host 'G23_PLAY=HOLD_TITLE_NOT_UNIQUE';exit 0}
 $hash=([string]$matched[0].hash).ToLowerInvariant()
 $m=Ts @{action='get';hash=$hash}
 if($null -eq $m -or -not $m.PSObject.Properties['hash'] -or [string]$m.hash -ine $hash){throw 'METADATA_HASH_MISMATCH'}
 $files=@()
 if($m.PSObject.Properties['file_stats'] -and $m.file_stats){$files=@($m.file_stats)}
 elseif($m.PSObject.Properties['data'] -and $m.data){try{$d=([string]$m.data|ConvertFrom-Json -Depth 30);$files=@($d.TorrServer.Files)}catch{}}
 $videos=@($files|Where-Object{$_ -and $_.PSObject.Properties['id'] -and [string]$_.id -match '^\d+$' -and $_.PSObject.Properties['path'] -and [string]$_.path -match '(?i)\.(mp4|mkv|webm|avi|mov|m4v|ts|m2ts)$' -and [string]$_.path -notmatch '(?i)(?:^|[\\/\s._-])(sample|trailer|extras?|bonus)(?:[\\/\s._-]|$)'})
 Write-Host ('G23_PRIMARY_VIDEO_COUNT='+$videos.Count)
 if($videos.Count -ne 1){Write-Host 'G23_PLAY=HOLD_FILE_NOT_UNIQUE';exit 0}
 $idx=[int]$videos[0].id
 Write-Host 'G23_EXACT_HASH_FILE=RESOLVED'
 $stage='PLAYBACK_PRECHECK'
 function PlayerForeground{
  $ac=((& $adb -s $serial shell dumpsys activity activities 2>$null)|Out-String)
  return [bool](@($ac -split '\r?\n'|Where-Object{$_ -match 'mResumedActivity|topResumedActivity' -and $_ -match [regex]::Escape($pkg+'/') -and $_ -match 'PlayerActivity'}).Count)
 }
 if(PlayerForeground){Write-Host 'G23_PLAY=HOLD_EXISTING_PLAYER_FOREGROUND';exit 0}
 function ReadViewed{
  try{
   $r=Invoke-WebRequest -Uri 'http://127.0.0.1:8090/viewed' -Method POST -ContentType 'application/json' -Body '{"action":"list"}' -TimeoutSec 5 -NoProxy -MaximumRedirection 0
   $v=$r.Content|ConvertFrom-Json -Depth 30 -NoEnumerate
   $x=@($v|Where-Object{$_ -and $_.PSObject.Properties['hash'] -and [string]$_.hash -ieq $hash -and $_.PSObject.Properties['file_index'] -and [int]$_.file_index -eq $idx -and $_.PSObject.Properties['timecode']})
   if($x.Count -eq 1 -and [string]$x[0].timecode -match '^\d+$'){return [long]$x[0].timecode}
  }catch{}
  return $null
 }
 $before=ReadViewed
 $start=0
 if($null -ne $before -and $before -ge 10){$start=$before}
 $stage='LAUNCH_ONCE'
 # One-shot receipt prevents duplicate dispatch after uncertain HTTP response.
 $receipt=Join-Path $dir 'g23-primetime-20261127-launch-attempt.json'
 if(Test-Path -LiteralPath $receipt){Write-Host 'G23_PLAY=HOLD_PRIOR_ATTEMPT_EXISTS';exit 0}
 $marker=@{attempt='g23-primetime-play-20261127';utc=[DateTime]::UtcNow.ToString('o');state='DISPATCH_STARTED';hash=$hash;file=$idx}|ConvertTo-Json -Compress
 [IO.File]::WriteAllText($receipt,$marker)
 $body=@{params=@{torrent=$hash;file=$idx;t=$start;from='Torrent TV Windows Runner'}}|ConvertTo-Json -Depth 4 -Compress
 $r=Invoke-RestMethod -Uri ($base+'/omp/launch') -Method POST -Headers @{Authorization=('Bearer '+$token)} -ContentType 'application/json' -Body $body -TimeoutSec 8 -NoProxy -MaximumRedirection 0
 if($r.ok -ne $true){throw 'LAUNCH_NOT_ACKNOWLEDGED'}
 Write-Host 'G23_LAUNCH=ACK'
 $stage='OBSERVE_PLAYER'
 $last=$null;$advanced=$false;$seen=$false
 for($n=0;$n -lt 9;$n++){
  Start-Sleep -Seconds 5
  $fg=PlayerForeground
  if($fg){$seen=$true}
  $pos=ReadViewed
  if($fg -and $null -ne $pos -and $null -ne $last -and $pos -gt $last -and $pos -gt $start){$advanced=$true;break}
  if($fg -and $null -ne $pos){$last=$pos}
 }
 Write-Host ('G23_NATIVE_PLAYER_FOREGROUND='+$seen)
 Write-Host ('G23_EXACT_FILE_PROGRESS_ADVANCED='+$advanced)
 if($seen -and $advanced){Write-Host 'G23_PLAY=EXACT_PROGRESS_PASS'}else{Write-Host 'G23_PLAY=ACK_ONLY_NATIVE_PROGRESS_UNVERIFIED'}
}catch{
 Write-Host ('G23_HOLD_STAGE='+$stage)
 Write-Host ('G23_ERROR_TYPE='+$_.Exception.GetType().Name)
 exit 1
}finally{
 if($ws){$ws.Dispose()}
 if($serial -and $forward -match '^\d{1,5}$'){& $adb -s $serial forward --remove ('tcp:'+$forward) 2>$null|Out-Null}
}
