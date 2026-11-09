# Only read Android system font inventories; no shell writes, APK changes or TV control.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Write-Host 'VI_FONT_PREFLIGHT_BEGIN'
if($env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or $env:RUNNER_OS -cne 'Windows'){
  Write-Host 'VI_FONT_STATUS=WRONG_RUNNER';exit 0
}
$adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
if(-not (Test-Path -LiteralPath $adb -PathType Leaf)){Write-Host 'VI_FONT_STATUS=ADB_MISSING';exit 0}
function Read-Adb([string[]]$Arguments){
  foreach($arg in $Arguments){if([string]::IsNullOrWhiteSpace($arg) -or $arg -match '\s'){throw 'INVALID_ARGUMENT'}}
  $p=New-Object System.Diagnostics.ProcessStartInfo
  $p.FileName=$adb
  $p.Arguments=($Arguments -join ' ')
  $p.UseShellExecute=$false
  $p.RedirectStandardOutput=$true
  $p.RedirectStandardError=$true
  $p.CreateNoWindow=$true
  $proc=[System.Diagnostics.Process]::Start($p)
  try {
    $out=$proc.StandardOutput.ReadToEnd()
    $null=$proc.StandardError.ReadToEnd()
    if(-not $proc.WaitForExit(30000)){$proc.Kill();throw 'TIMEOUT'}
    return [PSCustomObject]@{Code=$proc.ExitCode;Text=$out}
  }finally{$proc.Dispose()}
}
try{
  $ds=Read-Adb -Arguments @('devices','-l')
  if($ds.Code -ne 0){throw 'DEVICES_FAILED'}
  $found=@()
  foreach($line in ($ds.Text -split '\r?\n')){if($line -match '^\s*(\S+)\s+device(?:\s|$)'){$found += [string]$Matches[1]}}
  Write-Host ('VI_FONT_DEVICE_COUNT=' + $found.Count)
  if($found.Count -ne 1){Write-Host 'VI_FONT_STATUS=DEVICE_AMBIGUOUS';exit 0}
  $serial=[string]$found[0]
  $model=Read-Adb -Arguments @('-s',$serial,'shell','getprop','ro.product.model')
  if($model.Code -ne 0 -or $model.Text.Trim() -cne 'MiTV-ASTR0'){Write-Host 'VI_FONT_STATUS=WRONG_DEVICE';exit 0}
  Write-Host 'VI_FONT_MODEL=MiTV-ASTR0'
  $list=Read-Adb -Arguments @('-s',$serial,'shell','ls','-1','/system/fonts')
  if($list.Code -ne 0){Write-Host 'VI_FONT_STATUS=SYSTEM_FONT_LIST_UNAVAILABLE';exit 0}
  $files=@(($list.Text -split '\r?\n') | ForEach-Object {$_.Trim()} |
    Where-Object {$_ -match '^[A-Za-z0-9_.-]+\.(?:ttf|otf|ttc)$'})
  Write-Host ('VI_FONT_SYSTEM_FILE_COUNT=' + $files.Count)
  foreach($family in @('Roboto','NotoSans','DroidSans','Fallback')){
    $foundFont=@($files | Where-Object {$_ -match $family})
    Write-Host ('VI_FONT_'+$family.ToUpperInvariant()+'_COUNT='+$foundFont.Count)
    foreach($name in @($foundFont | Select-Object -First 3)){Write-Host ('VI_FONT_EXAMPLE='+$name)}
  }
  $conf=Read-Adb -Arguments @('-s',$serial,'shell','cat','/system/etc/fonts.xml')
  if($conf.Code -eq 0){
    Write-Host 'VI_FONT_CONFIG_READ=TRUE'
    Write-Host ('VI_FONT_CONFIG_HAS_NOTOSANS='+$conf.Text.Contains('NotoSans').ToString().ToUpperInvariant())
    Write-Host ('VI_FONT_CONFIG_HAS_VI_LANG='+([regex]::IsMatch($conf.Text,'(?i)lang="[^"]*vi(?:-[A-Za-z0-9]+)*"')).ToString().ToUpperInvariant())
  } else {Write-Host 'VI_FONT_CONFIG_READ=FALSE'}
  Write-Host 'VI_FONT_STATUS=READ_ONLY_OK'
}catch{Write-Host ('VI_FONT_STATUS=ERROR_'+$_.Exception.GetType().Name)}
Write-Host 'VI_FONT_PLAYER_UNCHANGED=TRUE'
Write-Host 'VI_FONT_RENDERING_NOT_PROVEN=TRUE'
Write-Host 'VI_FONT_PREFLIGHT_END'
exit 0
