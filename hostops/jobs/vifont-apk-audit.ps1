# Read-only binary/signing compatibility audit before any proposed Redmi Debug font A/B.
# Reads private retained candidate APK, uses adb only to read the installed test APK.
# No install, playback manipulation, device write, chmod, service or data modifications.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Write-Host 'VI_FONT_BINARY_PREFLIGHT_BEGIN'
if($env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_EVENT_NAME -cne 'issue_comment' -or
   $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub'){
    throw 'VI_FONT_AUDIT_WRONG_RUNNER'
}
$root='C:\TOOL\TorrentTV-Runner\private-artifacts\G1P2'
$dir=Join-Path $root 'FONT-CANDIDATE-42649389062-1'
$apk=Join-Path $dir 'app-armeabi-v7a-debug.apk'
$evidence=Join-Path $dir 'VI-FONT-EVIDENCE.txt'
if(-not (Test-Path -LiteralPath $apk -PathType Leaf) -or
   -not (Test-Path -LiteralPath $evidence -PathType Leaf)){
    throw 'VI_FONT_AUDIT_CANDIDATE_NOT_RETAINED'
}
$expected='1ede7c2d346512af08ef8c5933416ac4e7e60b62a4588d29f03b251b2af38a59'
$sha=(Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
if($sha -cne $expected){throw 'VI_FONT_AUDIT_CANDIDATE_HASH_DRIFT'}
$manifest=Get-Content -LiteralPath $evidence
if(@($manifest | Where-Object {$_ -ceq 'apk_sha256='+$expected}).Count -ne 1){
    throw 'VI_FONT_AUDIT_EVIDENCE_DRIFT'
}
Write-Host 'VI_FONT_PRIVATE_CANDIDATE_SHA_PASS'
$tools='C:\TOOL\Android-SDK\build-tools'
$dirs=@(Get-ChildItem -LiteralPath $tools -Directory | Sort-Object Name -Descending)
$signer=$null
$aapt=$null
foreach($d in $dirs){
    if(-not $signer -and (Test-Path -LiteralPath (Join-Path $d.FullName 'apksigner.bat'))){
        $signer=Join-Path $d.FullName 'apksigner.bat'
    }
    if(-not $aapt -and (Test-Path -LiteralPath (Join-Path $d.FullName 'aapt.exe'))){
        $aapt=Join-Path $d.FullName 'aapt.exe'
    }
}
if(-not $signer -or -not $aapt){throw 'VI_FONT_AUDIT_SIGNER_OR_AAPT_NOT_FOUND'}
$badging=@(& $aapt dump badging $apk 2>&1)
if($LASTEXITCODE -ne 0 -or @($badging | Where-Object {
  "$_" -match "^package:\s+name='com\.spacesarmat\.omp\.test'"
}).Count -ne 1){throw 'VI_FONT_AUDIT_APK_WRONG_PACKAGE'}
Write-Host 'VI_FONT_CANDIDATE_TEST_PACKAGE_PASS'
. (Join-Path $env:GITHUB_WORKSPACE 'poc\g1-p2-auto\apk-signer-digests.ps1')
$apksignerOutput=@(& $signer verify --print-certs $apk 2>&1)
if($LASTEXITCODE -ne 0){throw 'VI_FONT_AUDIT_CANDIDATE_SIGNATURE_INVALID'}
$certs=@(Get-ApkSignerSha256Digests -OutputLines $apksignerOutput)
if($certs.Count -ne 1){throw 'VI_FONT_AUDIT_CANDIDATE_CERT_UNKNOWN'}
Write-Host 'VI_FONT_CANDIDATE_DEBUG_SIGNING_PASS'

$adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
if(-not (Test-Path -LiteralPath $adb -PathType Leaf)){throw 'VI_FONT_AUDIT_ADB_MISSING'}
function RunAdb([string[]]$a){
  foreach($z in $a){if([string]::IsNullOrWhiteSpace($z) -or $z -match '\s'){throw 'VI_FONT_AUDIT_INVALID_ADB_ARG'}}
  $pi=New-Object System.Diagnostics.ProcessStartInfo
  $pi.FileName=$adb
  $pi.Arguments=($a -join ' ')
  $pi.UseShellExecute=$false
  $pi.CreateNoWindow=$true
  $pi.RedirectStandardOutput=$true
  $pi.RedirectStandardError=$true
  $p=[System.Diagnostics.Process]::Start($pi)
  try{
    $out=$p.StandardOutput.ReadToEnd()
    $null=$p.StandardError.ReadToEnd()
    if(-not $p.WaitForExit(60000)){$p.Kill();throw 'VI_FONT_AUDIT_ADB_TIMEOUT'}
    return [PSCustomObject]@{Code=$p.ExitCode;Out=$out}
  }finally{$p.Dispose()}
}
$devices=RunAdb @('devices','-l')
if($devices.Code -ne 0){throw 'VI_FONT_AUDIT_ADB_DEVICES_FAIL'}
$ids=@()
foreach($line in ($devices.Out -split '\r?\n')){
 if($line -match '^\s*(\S+)\s+device(?:\s|$)'){$ids += [string]$Matches[1]}
}
if($ids.Count -ne 1){Write-Host 'VI_FONT_INSTALLED_CERT=UNAVAILABLE_DEVICE_COUNT';exit 0}
$serial=$ids[0]
$model=RunAdb @('-s',$serial,'shell','getprop','ro.product.model')
if($model.Code -ne 0 -or $model.Out.Trim() -cne 'MiTV-ASTR0'){
  Write-Host 'VI_FONT_INSTALLED_CERT=UNAVAILABLE_WRONG_MODEL';exit 0
}
$paths=RunAdb @('-s',$serial,'shell','pm','path','com.spacesarmat.omp.test')
if($paths.Code -ne 0){Write-Host 'VI_FONT_INSTALLED_CERT=UNAVAILABLE_PM_PATH';exit 0}
$pathLines=@(($paths.Out -split '\r?\n') | Where-Object {$_ -match '^package:/'})
$basePath=@($pathLines | Where-Object {$_ -match '/base\.apk\s*$'})
if($basePath.Count -ne 1){
   Write-Host 'VI_FONT_INSTALLED_CERT=UNAVAILABLE_BASE_APK_AMBIGUOUS'
   exit 0
}
$remote=($basePath[0] -replace '^package:','').Trim()
$local=Join-Path $env:RUNNER_TEMP ('vi-font-installed-'+$env:GITHUB_RUN_ID+'.apk')
try{
    $pull=RunAdb @('-s',$serial,'pull',$remote,$local)
    if($pull.Code -ne 0 -or -not (Test-Path -LiteralPath $local -PathType Leaf)){
       Write-Host 'VI_FONT_INSTALLED_CERT=UNAVAILABLE_ADB_PULL'
       exit 0
    }
    $installedOutput=@(& $signer verify --print-certs $local 2>&1)
    if($LASTEXITCODE -ne 0){
       Write-Host 'VI_FONT_INSTALLED_CERT=UNAVAILABLE_SIGNER'
       exit 0
    }
    $oldCerts=@(Get-ApkSignerSha256Digests -OutputLines $installedOutput)
    if($oldCerts.Count -ne 1){
       Write-Host 'VI_FONT_INSTALLED_CERT=UNAVAILABLE_PARSE'
       exit 0
    }
    if($oldCerts[0] -ceq $certs[0]){
       Write-Host 'VI_FONT_CANDIDATE_VS_INSTALLED_SIGNER=MATCH'
    }else{
       Write-Host 'VI_FONT_CANDIDATE_VS_INSTALLED_SIGNER=MISMATCH'
    }
}finally{
  if(Test-Path -LiteralPath $local -PathType Leaf){
    Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue
  }
}
Write-Host 'VI_FONT_BINARY_PREFLIGHT_NO_INSTALL=TRUE'
Write-Host 'VI_FONT_BINARY_PREFLIGHT_END'
exit 0
