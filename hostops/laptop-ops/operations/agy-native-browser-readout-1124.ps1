# Read-only fixed 9555 observation. No navigation, browser start, provider call, or AGY invocation.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$profile=Join-Path $root 'CDP9555Profile'
$ls=@(Get-NetTCPConnection -LocalPort 9555 -State Listen -ErrorAction SilentlyContinue)
$ids=@($ls|Select-Object -ExpandProperty OwningProcess -Unique)
$code='TR05V2_9555_ABSENT'
if($ids.Count -gt 1){$code='TR05V2_9555_MULTIPLE'}
elseif($ids.Count -eq 1){
 $p=Get-CimInstance Win32_Process -Filter ("ProcessId="+$ids[0])
 if(-not $p -or $p.Name -ne 'chrome.exe' -or -not $p.CommandLine -or $p.CommandLine -notmatch '(?:^|\s|")--remote-debugging-port=9555(?:\s|"|\z)' -or @($ls|Where-Object {$_.LocalAddress -notin @('127.0.0.1','::1')}).Count -ne 0){$code='TR05V2_9555_IDENTITY_UNVERIFIED'}
 elseif($p.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -lt 0){$code='TR05V2_9555_PROFILE_OTHER'}
 else{
  try{
   $ver=Invoke-RestMethod -Uri 'http://127.0.0.1:9555/json/version' -NoProxy -TimeoutSec 5
   if([string]$ver.webSocketDebuggerUrl -notmatch '^ws://127\.0\.0\.1:9555/'){throw 'ENDPOINT'}
   $tabs=@(Invoke-RestMethod -Uri 'http://127.0.0.1:9555/json/list' -NoProxy -TimeoutSec 5 | Where-Object {$_.type -eq 'page'})
   $blocked=0;$normal=0
   foreach($tab in $tabs){
    $u=$null
    if([Uri]::TryCreate([string]$tab.url,[UriKind]::Absolute,[ref]$u) -and $u.Host -in @('www.opensubtitles.org','opensubtitles.org')){
     if($u.AbsolutePath -match '/\.within\.website/' -or [string]$tab.title -match 'making sure you.re not a bot|captcha|access denied'){ $blocked++ }
     else{$normal++}
    }
   }
   $code=if($blocked -gt 0){'TR05V2_9555_CHALLENGE_VISIBLE'}elseif($normal -gt 0){'TR05V2_9555_SITE_TAB_PRESENT'}else{'TR05V2_9555_NO_SITE_TAB'}
  }catch{$code='TR05V2_9555_CDP_READ_ERROR'}
 }
}
$task=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-Laptop-HostOps' -TaskPath '\'
$code=$code+'_L'+[int]([string]$task.Settings.ExecutionTimeLimit -eq 'PT0S')
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
