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
 }else{
  $stage='WEBVIEW_DISCOVERY'
  $pidText=((& $adb -s $serial shell pidof $pkg 2>$null)|Out-String).Trim()
  if($pidText -notmatch '^\d+$'){throw 'PID'}
  $forward=((& $adb -s $serial forward tcp:0 ('localabstract:webview_devtools_remote_'+$pidText) 2>$null)|Out-String).Trim()
  if($LASTEXITCODE -ne 0 -or $forward -notmatch '^\d{1,5}$'){throw 'FORWARD'}
  $targets=@(Invoke-RestMethod -Uri ('http://127.0.0.1:'+$forward+'/json/list') -TimeoutSec 4 -NoProxy)
  $pages=@($targets|Where-Object{$_.type -eq 'page' -and $_.url -match '^https?://localhost(?:[/:]|$)' -and $_.webSocketDebuggerUrl})
  if($pages.Count -ne 1){throw 'PAGE'}
  $uri=[uri]$pages[0].webSocketDebuggerUrl
  if($uri.Host -notin @('localhost','127.0.0.1') -or $uri.Scheme -ne 'ws' -or $uri.Port -ne [int]$forward){throw 'CDP_ENDPOINT'}
  $ws=[System.Net.WebSockets.ClientWebSocket]::new()
  $cancel=[System.Threading.CancellationTokenSource]::new(10000)
  try{$ws.ConnectAsync($uri,$cancel.Token).GetAwaiter().GetResult()}finally{$cancel.Dispose()}
  $script:seq=0
  function Eval([string]$expression){
   $script:seq++
   $id=$script:seq
   $payload=@{id=$id;method='Runtime.evaluate';params=@{expression=$expression;returnByValue=$true}}|ConvertTo-Json -Depth 6 -Compress
   $bytes=[Text.Encoding]::UTF8.GetBytes($payload)
   $cts=[System.Threading.CancellationTokenSource]::new(8000)
   try{
    $ws.SendAsync([ArraySegment[byte]]::new($bytes),[System.Net.WebSockets.WebSocketMessageType]::Text,$true,$cts.Token).GetAwaiter().GetResult() | Out-Null
    do{
     $ms=[IO.MemoryStream]::new()
     try{
      $buf=[byte[]]::new(4096)
      do{$rr=$ws.ReceiveAsync([ArraySegment[byte]]::new($buf),$cts.Token).GetAwaiter().GetResult();if($rr.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close){throw 'WS_CLOSED'};$ms.Write($buf,0,$rr.Count)}until($rr.EndOfMessage)
      $msg=[Text.Encoding]::UTF8.GetString($ms.ToArray())|ConvertFrom-Json -AsHashtable
     }finally{$ms.Dispose()}
    }until($msg.Contains('id') -and $msg.id -eq $id)
    if($msg.Contains('error') -or $msg.result.Contains('exceptionDetails')){throw 'CDP_EVAL'}
    return $msg.result.result.value
   }finally{$cts.Dispose()}
  }
  $stage='PAIR_UI_OBSERVE'
  # Inspect only fixed, non-sensitive DOM markers; never log text, URL, code, or page contents.
  $observe="(()=>JSON.stringify({ready:document.readyState,screens:document.querySelectorAll('.screen').length,focus:document.querySelectorAll('[data-fk]').length,library:!!document.querySelector('.screen.library'),settings:!!document.querySelector('.screen.settings'),pair:!!document.querySelector('.pair-phone'),connect:!!document.querySelector('.screen.connect'),torrent:!!document.querySelector('.screen.torrent'),host:!!document.querySelector('.screen-host'),libButton:!!document.querySelector('[data-fk=lib-btn-settings]'),pairButton:!!document.querySelector('[data-fk=set-pair]'),dialog:!!document.querySelector('[role=dialog]'),app:!!document.querySelector('#app,#root'),visible:document.visibilityState==='visible'}))()"
  $view=$null
  for($attempt=0;$attempt -lt 4;$attempt++){
   $view=(Eval $observe)|ConvertFrom-Json
   if($view.screens -gt 0 -or $view.focus -gt 0){break}
   Start-Sleep -Seconds 2
  }
  Write-Host ('G23_UI_MARKERS='+($view|ConvertTo-Json -Compress))
  $stage='PAIR_UI_CLASSIFY'
  if($view.pair){$screen='PAIR'}
  elseif($view.pairButton){$screen='SETTINGS'}
  elseif($view.libButton -or $view.library){$screen='LIBRARY'}
  elseif($view.connect){$screen='CONNECT'}
  else{$screen='OTHER'}
  Write-Host ('G23_UI_SCREEN='+$screen)
  if($screen -eq 'LIBRARY'){
   $stage='PAIR_UI_SETTINGS_CLICK'
   if($view.libButton){
    $clicked=Eval "(()=>{const e=document.querySelector('[data-fk=lib-btn-settings]');if(!e||!e.getClientRects().length)return false;e.click();return true})()"
    if(-not $clicked){throw 'SETTINGS_CLICK'}
   }else{
    # Upstream Library.tsx handles the blue key by opening Settings.
    & $adb -s $serial shell input keyevent KEYCODE_PROG_BLUE 2>$null|Out-Null
    if($LASTEXITCODE -ne 0){throw 'SETTINGS_CLICK'}
   }
   Start-Sleep -Seconds 1
  }elseif($screen -notin @('SETTINGS','PAIR')){throw 'UI_NOT_LIBRARY'}
  if($screen -ne 'PAIR'){
   $stage='PAIR_UI_PAIR_CLICK'
   $clicked=Eval "(()=>{const e=document.querySelector('[data-fk=set-pair]');if(!e||!e.getClientRects().length)return false;e.click();return true})()"
   if(-not $clicked){throw 'PAIR_CLICK'}
   Start-Sleep -Seconds 1
  }
  $stage='PAIR_UI_CODE'
  $code=Eval "(()=>{if(!document.querySelector('.pair-phone'))return '';return Array.from(document.querySelectorAll('.pair-digit')).filter(e=>e.getClientRects().length).map(e=>e.textContent.trim()).join('')})()"
  if($code -notmatch '^\d{6}$'){throw 'PAIR_CODE_UNAVAILABLE'}
  $stage='PAIR_REQUEST'
  $body=@{code=$code;phone='Torrent TV Windows Runner'}|ConvertTo-Json -Compress
  $reply=Invoke-RestMethod -Uri ($base+'/omp/pair') -Method POST -ContentType 'application/json' -Body $body -TimeoutSec 5 -MaximumRedirection 0 -NoProxy
  $token=[string]$reply.token
  if($token -notmatch '^[a-f0-9]{32}$'){throw 'PAIR_REPLY_INVALID'}
  $stage='PAIR_PERSIST'
  New-Item -ItemType Directory -Path $dir -Force|Out-Null
  $cipher=ConvertTo-SecureString -String $token -AsPlainText -Force|ConvertFrom-SecureString
  [IO.File]::WriteAllText(($path+'.tmp'),$cipher)
  Move-Item -LiteralPath ($path+'.tmp') -Destination $path
  $stage='PAIR_VERIFY'
  $i=Invoke-RestMethod -Uri ($base+'/omp/info') -Headers @{Authorization=('Bearer '+$token)} -TimeoutSec 4 -MaximumRedirection 0 -NoProxy
  if($i.paired -ne $true){throw 'PAIR_NOT_VERIFIED'}
  Write-Host 'G23_PAIR=NEW_VERIFIED'
 }
 Write-Host 'G23_TOKEN_SCOPE=WINDOWS_RUNNER_DPAPI_CURRENT_USER'
 # Inspect only existing-library metadata. No play unless an authorized fixture is established separately.
 $stage='LIBRARY'
 $list=@(Invoke-RestMethod -Uri 'http://127.0.0.1:8090/torrents' -Method POST -ContentType 'application/json' -Body '{"action":"list"}' -TimeoutSec 5 -NoProxy -MaximumRedirection 0)
 Write-Host ('G23_LIBRARY_COUNT='+$list.Count)
 $fixture=@($list|Where-Object{[string]$_.title -match '(?i)big[ ._-]+buck[ ._-]+bunny|tears[ ._-]+of[ ._-]+steel|sintel|ttv[ ._-]+fixture'})
 Write-Host ('G23_POSSIBLE_FIXTURE_COUNT='+$fixture.Count)
 Write-Host 'G23_PLAY=NOT_ATTEMPTED'
}catch{
 Write-Host ('G23_HOLD_STAGE='+$stage)
 Write-Host ('G23_ERROR_TYPE='+$_.Exception.GetType().Name)
 $reason=$_.Exception.Message
 if($reason -in @('UI_NOT_LIBRARY','SETTINGS_CLICK','PAIR_CLICK','PAIR_CODE_UNAVAILABLE','CDP_EVAL','WS_CLOSED')){Write-Host ('G23_REASON='+$reason)}
 exit 1
}finally{
 if($ws){$ws.Dispose()}
 if($serial -and $forward -match '^\d{1,5}$'){& $adb -s $serial forward --remove ('tcp:'+$forward) 2>$null|Out-Null}
}
