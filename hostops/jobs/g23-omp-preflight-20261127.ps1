# G2.3 remote-play read-only feasibility; never pair, launch, add, or read tokens.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win') { throw 'G23_WRONG_RUNNER' }
Write-Host 'G23_SCOPE=READ_ONLY'
Write-Host ('G23_UTC='+[DateTime]::UtcNow.ToString('o'))
function Get-JsonLocal([string]$uri,[string]$method='GET',[string]$body='') {
  try {
    $p=@{Uri=$uri;Method=$method;TimeoutSec=3;MaximumRedirection=0;NoProxy=$true;ErrorAction='Stop'}
    if($method -eq 'POST'){$p.ContentType='application/json';$p.Body=$body}
    $r=Invoke-WebRequest @p
    return @{ok=($r.StatusCode -eq 200);value=($r.Content | ConvertFrom-Json -Depth 30 -NoEnumerate)}
  } catch { return @{ok=$false;value=$null} }
}
$ts=Get-JsonLocal 'http://127.0.0.1:8090/torrents' 'POST' '{"action":"list"}'
if($ts.ok){Write-Host 'G23_TS_LIBRARY=REACHABLE';Write-Host ('G23_TS_COUNT='+@($ts.value | Where-Object {$_ -ne $null}).Count)}
else{Write-Host 'G23_TS_LIBRARY=UNVERIFIED_DEFAULT_PORT_OR_AUTH'}
$adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
if(-not (Test-Path -LiteralPath $adb -PathType Leaf)){Write-Host 'G23_ADB=NOT_FOUND';exit 0}
$lines=@(& $adb devices 2>$null)
if($LASTEXITCODE -ne 0){Write-Host 'G23_ADB=UNAVAILABLE';exit 0}
$auth=@($lines | Where-Object {$_ -match '^\S+\s+device(\s|$)'})
$other=@($lines | Where-Object {$_ -match '^\S+\s+(offline|unauthorized)(\s|$)'})
if($auth.Count -ne 1 -or $other.Count -gt 0){Write-Host 'G23_ADB=SINGLE_AUTHORIZED_DEVICE_REQUIRED';exit 0}
$serial=($auth[0] -split '\s+')[0]
$model=((& $adb -s $serial shell getprop ro.product.model 2>$null)|Out-String).Trim()
if($LASTEXITCODE -ne 0 -or $model -cne 'MiTV-ASTR0'){Write-Host 'G23_ADB=EXPECTED_REDMi_NOT_VERIFIED';exit 0}
Write-Host 'G23_ADB=EXPECTED_MODEL_REACHABLE'
$pkg='com.spacesarmat.omp.test'
$pm=@(& $adb -s $serial shell pm path $pkg 2>$null)
if($LASTEXITCODE -ne 0 -or -not @($pm | Where-Object {$_ -match '^package:.*base\.apk$'}).Count){Write-Host 'G23_OMP=EXPECTED_DEBUG_PACKAGE_NOT_FOUND';exit 0}
Write-Host 'G23_OMP=DEBUG_PACKAGE_PRESENT'
# Resolve only the authenticated Redmi's own WLAN IP; do not scan the LAN.
$ip=$null
if($serial -match '^((?:\d{1,3}\.){3}\d{1,3}):\d+$'){$ip=$Matches[1]}
else{
  $addr=((& $adb -s $serial shell ip -4 addr show wlan0 2>$null)|Out-String)
  if($addr -match '\binet ((?:\d{1,3}\.){3}\d{1,3})/'){$ip=$Matches[1]}
}
if(-not $ip -or $ip -notmatch '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)'){Write-Host 'G23_OMP=LAN_ENDPOINT_UNVERIFIED';exit 0}
$found=0
foreach($port in 8095..8099){
  $r=Get-JsonLocal ("http://"+$ip+":"+$port+"/omp/info")
  if($r.ok -and $null -ne $r.value -and $null -ne $r.value.PSObject.Properties['foreground'] -and $null -ne $r.value.PSObject.Properties['paired'] -and $null -ne $r.value.PSObject.Properties['version']){
    $found++
    Write-Host ('G23_OMP_INFO_PORT='+$port)
    Write-Host ('G23_OMP_FOREGROUND='+[bool]$r.value.foreground)
  }
}
Write-Host ('G23_OMP_ENDPOINT_COUNT='+$found)
Write-Host 'G23_PAIRING=NOT_ATTEMPTED'
Write-Host 'G23_PLAYBACK=NOT_ATTEMPTED'
exit 0
