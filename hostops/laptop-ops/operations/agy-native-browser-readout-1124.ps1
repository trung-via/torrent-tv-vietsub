# One ordinary provider page navigation on the already restored dedicated browser.
# No restart, alternate profile, challenge solving, retries, model calls or downloads.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$profile=Join-Path $root 'CDP9555Profile'
function Listener([int]$port){
 @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue|Select-Object -ExpandProperty OwningProcess -Unique|Sort-Object)
}
$w0=@(Listener 9444)
$b0=@(Listener 9555)
$task='TorrentTV-Vietsub-OwnerAgent'
$o0=Export-ScheduledTask -TaskName $task -TaskPath '\'
$q0=[string](Get-ScheduledTask -TaskName $task -TaskPath '\').State
$opened=0
$code='TR05V2_BROWSER_NOT_VERIFIED'
function State($tab){
 $u=$null
 if(-not [Uri]::TryCreate([string]$tab.url,[UriKind]::Absolute,[ref]$u)){return 'OTHER'}
 if($u.Host -notin @('www.opensubtitles.org','opensubtitles.org')){return 'OTHER'}
 if($u.AbsolutePath -match '/\.within\.website/' -or [string]$tab.title -match 'making sure you.re not a bot|captcha|access denied|just a moment|forbidden'){return 'BLOCKED'}
 if([string]$tab.title -match 'log.?in|sign.?in|authentication required'){return 'AUTH'}
 if([string]$tab.title -match 'subtitles' -and [string]$tab.title -match 'download|movie|search'){return 'SITE_VISIBLE'}
 return 'UNVERIFIED'
}
if($b0.Count -eq 1){
 $ls=@(Get-NetTCPConnection -LocalPort 9555 -State Listen -ErrorAction SilentlyContinue)
 $p=Get-CimInstance Win32_Process -Filter ('ProcessId='+$b0[0])
 if($p -and $p.Name -eq 'chrome.exe' -and $p.CommandLine -and $p.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0 -and $p.CommandLine -match '(?:^|\s|")--remote-debugging-port=9555(?:\s|"|\z)' -and @($ls|Where-Object {$_.LocalAddress -notin @('127.0.0.1','::1')}).Count -eq 0){
  try{
   $v=Invoke-RestMethod -Uri 'http://127.0.0.1:9555/json/version' -NoProxy -TimeoutSec 5
   if([string]$v.webSocketDebuggerUrl -notmatch '^ws://127\.0\.0\.1:9555/'){throw 'CDP_ENDPOINT'}
   $tabs=Invoke-RestMethod -Uri 'http://127.0.0.1:9555/json/list' -NoProxy -TimeoutSec 5
   $site=@($tabs|Where-Object {$_.type -eq 'page'}|ForEach-Object {State $_}|Where-Object {$_ -ne 'OTHER'})
   if($site -contains 'BLOCKED'){$code='TR05V2_ACCESS_BLOCKED'}
   elseif($site -contains 'AUTH'){$code='TR05V2_AUTH_REQUIRED'}
   elseif($site -contains 'SITE_VISIBLE'){$code='TR05V2_SITE_VISIBLE_EXISTING'}
   elseif($site.Count -gt 0){$code='TR05V2_ACCESS_UNVERIFIED'}
   else{
    # Normal homepage navigation only, exactly once on the fixed browser.
    $new=Invoke-RestMethod -Method Put -Uri 'http://127.0.0.1:9555/json/new?https://www.opensubtitles.org/en' -NoProxy -TimeoutSec 5
    $opened=1
    $code='TR05V2_ACCESS_UNVERIFIED'
    for($i=0;$i -lt 20;$i++){
     $tabs=Invoke-RestMethod -Uri 'http://127.0.0.1:9555/json/list' -NoProxy -TimeoutSec 5
     $tab=@($tabs|Where-Object {$_.id -eq $new.id -and $_.type -eq 'page'})
     if($tab.Count -ne 1){break}
     $st=State $tab[0]
     if($st -eq 'BLOCKED'){$code='TR05V2_ACCESS_BLOCKED';break}
     if($st -eq 'AUTH'){$code='TR05V2_AUTH_REQUIRED';break}
     if($st -eq 'SITE_VISIBLE'){$code='TR05V2_SITE_VISIBLE_NEW';break}
     Start-Sleep -Milliseconds 500
    }
   }
  }catch{$code='TR05V2_LOCAL_CDP_ERROR'}
 }
}
$w=[int](($w0 -join ',') -ceq (@(Listener 9444) -join ','))
$b=[int](($b0 -join ',') -ceq (@(Listener 9555) -join ','))
$o=[int]($o0 -ceq (Export-ScheduledTask -TaskName $task -TaskPath '\'))
$q=[int]($q0 -ceq [string](Get-ScheduledTask -TaskName $task -TaskPath '\').State)
$code=$code+'_N'+$opened+'W'+$w+'B'+$b+'O'+$o+'Q'+$q
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
