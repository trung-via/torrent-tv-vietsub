# HUMAN-RUN ONLY. Read-only TV Preflight, protected adb install -r, read-only Verify.
# No uninstall, data clear, registration, chmod, or network change.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [ValidateSet('Preflight','InstallKeepData','VerifyInstalled')]
  [string]$Phase,
  [Parameter(Mandatory=$true)][string]$NewApkPath,
  [string]$OldApkPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
$aapt2 = 'C:\TOOL\Android-SDK\build-tools\36.0.0\aapt2.exe'
$apksigner = 'C:\TOOL\Android-SDK\build-tools\36.0.0\apksigner.bat'
$pkg = 'com.spacesarmat.omp.test'
$oldSha = 'ae132b6ea76e68dddde5a4632ec2d75c5e94f26bee71e063936520a13af39617'
$newSha = '8f4df47952d00d75bb6234a7620c4fc41e26995fab263d8d2db60292bc94fd85'
$srtSha = 'c96fe148c2bac63bc2bfc3768e4b3fc3d280cbbff52ad9cc03aae7679ff82f95'
$srt = 'files/p1-g1-external.vi.srt'
$registry = 'shared_prefs/p1-g1c-subtitles.xml'
$protected = @(
  'files/p1-g1c.register',
  'files/p1-g1.enable',
  'files/p1-g1-external.vi.srt.g1d-backup',
  'files/p1-g1-external.vi.srt.g1d-utf8-backup',
  'files/p1-g1-external.vi.srt.g1d-utf8-discard',
  'files/p1-g1-external.vi.srt.g1d-syntax-backup',
  'files/p1-g1-external.vi.srt.g1d-syntax-discard',
  'files/p1-g1-external.vi.srt.g1d-changed-backup',
  'files/p1-g1-external.vi.srt.g1d-changed-discard',
  'files/p1-g1-external.vi.srt.g1d-perm-backup',
  'files/p1-g1-external.vi.srt.g1d-perm-discard'
)
foreach ($tool in @($adb,$aapt2,$apksigner)) {
  if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw 'STOP: required SDK tool missing' }
}
if (-not (Test-Path -LiteralPath $NewApkPath -PathType Leaf)) { throw 'STOP: new ARM32 APK missing' }
$NewApkPath = (Resolve-Path -LiteralPath $NewApkPath).Path
if ((Get-FileHash -LiteralPath $NewApkPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $newSha) {
  throw 'STOP: PR29 ARM32 debug APK SHA256 mismatch'
}
if ($Phase -ne 'VerifyInstalled') {
  if (-not $OldApkPath -or -not (Test-Path -LiteralPath $OldApkPath -PathType Leaf)) {
    throw 'STOP: supply audited old SEL-01 APK for comparison'
  }
  $OldApkPath = (Resolve-Path -LiteralPath $OldApkPath).Path
  if ((Get-FileHash -LiteralPath $OldApkPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $oldSha) {
    throw 'STOP: old SEL-01 APK SHA256 mismatch'
  }
}
function Read-PackageName([string]$apk) {
  $out = @(& $aapt2 dump badging $apk 2>&1)
  if ($LASTEXITCODE -ne 0) { throw 'STOP: APK badging inspection failed' }
  $m = [regex]::Match(($out -join [Environment]::NewLine), "(?m)^package:\s+name='([^']+)'")
  if (-not $m.Success) { throw 'STOP: cannot establish APK package identity' }
  return $m.Groups[1].Value
}
function Read-Certificate([string]$apk) {
  $out = @(& $apksigner verify --print-certs $apk 2>&1)
  if ($LASTEXITCODE -ne 0) { throw 'STOP: APK signature verification failed' }
  $m = [regex]::Match(($out -join [Environment]::NewLine), '(?im)^\s*Signer #1 certificate SHA-256 digest:\s*([a-f0-9]{64})\s*$')
  if (-not $m.Success) { throw 'STOP: cannot parse signing certificate fingerprint' }
  return $m.Groups[1].Value.ToLowerInvariant()
}
if ((Read-PackageName $NewApkPath) -cne $pkg) { throw 'STOP: new APK is not expected debug package' }
$newCert = Read-Certificate $NewApkPath
if ($Phase -ne 'VerifyInstalled') {
  if ((Read-PackageName $OldApkPath) -cne $pkg) { throw 'STOP: old package identity mismatch' }
  if ((Read-Certificate $OldApkPath) -cne $newCert) {
    throw 'STOP: signing certificate differs; NEVER uninstall or clear app data'
  }
}
$devices = @(& $adb devices -l)
if ($LASTEXITCODE -ne 0) { throw 'STOP: adb devices failed' }
$attached = @($devices | Where-Object { $_ -match '^\s*\S+\s+(device|offline|unauthorized)\b' })
if ($attached.Count -ne 1) { throw 'STOP: need exactly one ADB device entry' }
$d = [regex]::Match($attached[0], '^\s*(\S+)\s+device\b')
if (-not $d.Success) { throw 'STOP: ADB device unauthorized/offline' }
$serial = $d.Groups[1].Value
$model = (& $adb -s $serial shell getprop ro.product.model | Out-String).Trim()
$api = (& $adb -s $serial shell getprop ro.build.version.sdk | Out-String).Trim()
$abi = (& $adb -s $serial shell getprop ro.product.cpu.abi | Out-String).Trim()
if ($model -cne 'MiTV-ASTR0' -or $api -cne '30' -or $abi -cne 'armeabi-v7a') {
  throw 'STOP: wrong Redmi model / API / ABI'
}
Write-Host 'G1D_UX_REDMI_ARM32_DEVICE_PASS'
function Test-AppEntry([string]$name) {
  & $adb -s $serial shell run-as $pkg test -e $name
  if ($LASTEXITCODE -eq 0) { return $true }
  if ($LASTEXITCODE -eq 1) { return $false }
  throw 'STOP: run-as cannot inspect app-private entry'
}
function Test-AppFile([string]$name) {
  & $adb -s $serial shell run-as $pkg test -f $name
  if ($LASTEXITCODE -eq 0) { return $true }
  if ($LASTEXITCODE -eq 1) { return $false }
  throw 'STOP: run-as file inspection failed'
}
function Test-AppReadable([string]$name) {
  & $adb -s $serial shell run-as $pkg test -r $name
  if ($LASTEXITCODE -eq 0) { return $true }
  if ($LASTEXITCODE -eq 1) { return $false }
  throw 'STOP: run-as readability inspection failed'
}
function Hash-App([string]$name) {
  $out = @(& $adb -s $serial shell run-as $pkg sha256sum $name)
  if ($LASTEXITCODE -ne 0) { throw 'STOP: app-private sha256sum failed' }
  $m = [regex]::Match(($out | Out-String).Trim(), '^([a-fA-F0-9]{64})\s+')
  if (-not $m.Success) { throw 'STOP: invalid app-private SHA256' }
  return $m.Groups[1].Value.ToLowerInvariant()
}
function Read-AppBaseline {
  foreach ($entry in $protected) {
    if (Test-AppEntry $entry) { throw 'STOP: registration marker or protected G1d backup remains' }
  }
  if (-not (Test-AppFile $srt) -or -not (Test-AppReadable $srt)) {
    throw 'STOP: original SRT not a readable regular file'
  }
  if ((Hash-App $srt) -cne $srtSha) { throw 'STOP: original SRT SHA256 mismatch' }
  if (-not (Test-AppFile $registry) -or -not (Test-AppReadable $registry)) {
    throw 'STOP: saved G1c registry missing/unreadable'
  }
  return (Hash-App $registry)
}

# ADB writes successful progress to stderr in Windows PowerShell 5.1.
# Capture only this known native-program behavior without weakening the
# global Stop preference. ADB's actual exit code and artifact hashes still
# determine success. Never echo command output (may contain private paths).
function Invoke-AdbCaptured([string[]]$Argv) {
  $priorPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $combined = @(& $adb @Argv 2>&1)
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $priorPreference
  }
  return @{
    ExitCode = $exitCode
    Text = (($combined | ForEach-Object { [string]$_ }) -join ' ')
  }
}
function Read-InstalledApkSha {
  $paths = @(& $adb -s $serial shell pm path $pkg)
  if ($LASTEXITCODE -ne 0) { throw 'STOP: pm path failed' }
  $paths = @($paths | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^package:' })
  if ($paths.Count -ne 1) { throw 'STOP: installed package is split or not found' }
  $parsed = [regex]::Match($paths[0], '^package:(/.+/base\.apk)$')
  if (-not $parsed.Success) { throw 'STOP: installed APK base path layout differs from reviewed path' }
  $remote = $parsed.Groups[1].Value
  $tmp = Join-Path $env:TEMP ('g1d-ux-base-' + [Guid]::NewGuid().ToString('N') + '.apk')
  try {
    $pull = Invoke-AdbCaptured @('-s', $serial, 'pull', $remote, $tmp)
    if ($pull.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $tmp -PathType Leaf)) {
      throw 'STOP: installed APK could not be pulled read-only'
    }
    if ((Read-PackageName $tmp) -cne $pkg) { throw 'STOP: installed package name mismatch' }
    if ((Read-Certificate $tmp) -cne $newCert) { throw 'STOP: installed package signature mismatch' }
    return (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
  } finally {
    if (Test-Path -LiteralPath $tmp -PathType Leaf) { Remove-Item -LiteralPath $tmp -Force }
  }
}
function Check-Device([string]$expectedSha) {
  $installedSha = Read-InstalledApkSha
  if ($installedSha -cne $expectedSha) { throw 'STOP: installed APK does not match pinned expected build' }
  return (Read-AppBaseline)
}
switch ($Phase) {
  'Preflight' {
    $prefs = Check-Device $oldSha
    Write-Host 'G1D_UX_OLD_INSTALLED_SHA_CERT_PASS'
    Write-Host 'G1D_UX_SRT_AND_REGISTRY_PREFLIGHT_PASS'
    Write-Host 'G1D_UX_INSTALL_PREFLIGHT_READ_ONLY_TV_PASS'
  }
  'InstallKeepData' {
    $beforePrefs = Check-Device $oldSha
    Write-Host 'G1D_UX_INSTALL_PINS_AND_DATA_PREFLIGHT_PASS'
    $answer = Read-Host 'CLOSE VLC PLAYER. Type INSTALL G1D UX KEEP DATA to run adb install -r'
    if ($answer -cne 'INSTALL G1D UX KEEP DATA') { throw 'STOP: install not approved at device gate' }
    $againPrefs = Check-Device $oldSha
    if ($againPrefs -cne $beforePrefs) { throw 'STOP: registry changed before installation' }
    $install = Invoke-AdbCaptured @('-s', $serial, 'install', '-r', $NewApkPath)
    $ok = $install.ExitCode -eq 0 -and ($install.Text -match '(^|\s)Success(\s|$)')
    if (-not $ok) {
      $reason = [regex]::Match($install.Text, 'INSTALL_FAILED_[A-Z0-9_]+')
      if ($reason.Success) { throw ('STOP: adb install -r failed: ' + $reason.Value) }
      throw 'STOP: adb install -r failed; do not uninstall or clear data'
    }
    Write-Host 'G1D_UX_ADB_INSTALL_R_SUCCESS_NOT_TV_UX_PASS'
    $afterPrefs = Check-Device $newSha
    if ($afterPrefs -cne $beforePrefs) {
      throw 'STOP: registry changed after install; preserve app data and investigate'
    }
    Write-Host 'G1D_UX_INSTALLED_NEW_SHA_CERT_AND_DATA_PRESERVED_PASS_NOT_TV_UX_PASS'
  }
  'VerifyInstalled' {
    $prefs = Check-Device $newSha
    Write-Host 'G1D_UX_VERIFY_NEW_INSTALLED_SHA_CERT_AND_SRT_REGISTRY_PASS_NOT_TV_UX_PASS'
  }
}
