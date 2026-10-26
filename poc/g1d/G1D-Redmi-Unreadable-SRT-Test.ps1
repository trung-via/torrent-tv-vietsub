# G1d PERMISSION-DENIED SRT test. Human-run only. Do not install/reset app or change markers/registry.
# Stage copies the original bytes to an unreadable *probe*, preserving the original inode as a protected backup.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [ValidateSet('Preflight','StageUnreadable','InspectUnreadable','Restore','VerifyRestored')]
  [string]$Phase,
  [string]$ApkPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
$pkg = 'com.spacesarmat.omp.test'
$original = 'files/p1-g1-external.vi.srt'
$backup = 'files/p1-g1-external.vi.srt.g1d-perm-backup'
$discard = 'files/p1-g1-external.vi.srt.g1d-perm-discard'
$priorBackups = @(
  'files/p1-g1-external.vi.srt.g1d-backup',
  'files/p1-g1-external.vi.srt.g1d-utf8-backup',
  'files/p1-g1-external.vi.srt.g1d-utf8-discard',
  'files/p1-g1-external.vi.srt.g1d-syntax-backup',
  'files/p1-g1-external.vi.srt.g1d-syntax-discard',
  'files/p1-g1-external.vi.srt.g1d-changed-backup',
  'files/p1-g1-external.vi.srt.g1d-changed-discard'
)
$registry = 'shared_prefs/p1-g1c-subtitles.xml'
$marker = 'files/p1-g1c.register'
$legacyMarker = 'files/p1-g1.enable'
$expectedSrt = 'c96fe148c2bac63bc2bfc3768e4b3fc3d280cbbff52ad9cc03aae7679ff82f95'
$expectedApk = 'ae132b6ea76e68dddde5a4632ec2d75c5e94f26bee71e063936520a13af39617'

if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) { throw 'STOP: adb.exe missing' }
$devices = @(& $adb devices -l)
if ($LASTEXITCODE -ne 0) { throw 'STOP: adb devices failed' }
$attached = @($devices | Where-Object { $_ -match '^\s*\S+\s+(device|offline|unauthorized)\b' })
if ($attached.Count -ne 1) { throw 'STOP: need exactly one authorized ADB device' }
$m = [regex]::Match($attached[0], '^\s*(\S+)\s+device\b')
if (-not $m.Success) { throw 'STOP: device offline/unauthorized' }
$serial = $m.Groups[1].Value
$model = (& $adb -s $serial shell getprop ro.product.model | Out-String).Trim()
$api = (& $adb -s $serial shell getprop ro.build.version.sdk | Out-String).Trim()
$abi = (& $adb -s $serial shell getprop ro.product.cpu.abi | Out-String).Trim()
if ($model -cne 'MiTV-ASTR0' -or $api -cne '30' -or $abi -cne 'armeabi-v7a') {
  throw 'STOP: wrong TV/API/ABI'
}
Write-Host 'G1D_PERM_REDMI_MATCH'

function Test-AppEntry([string]$p) {
  & $adb -s $serial shell run-as $pkg test -e $p
  if ($LASTEXITCODE -eq 0) { return $true }
  if ($LASTEXITCODE -eq 1) { return $false }
  throw 'STOP: run-as entry test failed'
}
function Test-AppFile([string]$p) {
  & $adb -s $serial shell run-as $pkg test -f $p
  if ($LASTEXITCODE -eq 0) { return $true }
  if ($LASTEXITCODE -eq 1) { return $false }
  throw 'STOP: run-as regular-file test failed'
}
function Test-AppReadable([string]$p) {
  & $adb -s $serial shell run-as $pkg test -r $p
  if ($LASTEXITCODE -eq 0) { return $true }
  if ($LASTEXITCODE -eq 1) { return $false }
  throw 'STOP: run-as read-permission test failed'
}
function Mode-App([string]$p) {
  $out = @(& $adb -s $serial shell run-as $pkg stat -c '%a' $p)
  if ($LASTEXITCODE -ne 0) { throw 'STOP: app-private stat failed' }
  $mode = ($out | Out-String).Trim()
  if ($mode -notmatch '^[0-7]{1,4}$') { throw 'STOP: unexpected app-private POSIX mode' }
  return ([int]::Parse($mode)).ToString()
}
function Hash-App([string]$p) {
  $out = @(& $adb -s $serial shell run-as $pkg sha256sum $p)
  if ($LASTEXITCODE -ne 0) { throw 'STOP: app-private sha256sum failed' }
  $m = [regex]::Match(($out | Out-String).Trim(), '^([a-fA-F0-9]{64})\s+')
  if (-not $m.Success) { throw 'STOP: invalid sha256sum result' }
  return $m.Groups[1].Value.ToLowerInvariant()
}
function Require-AppHash([string]$p,[string]$digest) {
  if ((Hash-App $p) -cne $digest) { throw 'STOP: protected SRT SHA256 mismatch' }
}
function Require-Registry {
  if (-not (Test-AppFile $registry)) { throw 'STOP: saved G1c registry missing' }
  if ((Test-AppEntry $marker) -or (Test-AppEntry $legacyMarker)) {
    throw 'STOP: registration marker present; no permissions test permitted'
  }
}
function Require-Baseline {
  Require-Registry
  foreach ($p in (@($backup,$discard) + $priorBackups)) {
    if (Test-AppEntry $p) { throw 'STOP: protected backup/discard path already occupied' }
  }
  if (-not (Test-AppFile $original)) { throw 'STOP: original SRT missing' }
  if (-not (Test-AppReadable $original)) { throw 'STOP: original SRT not readable at baseline' }
  $mode = Mode-App $original
  if ($mode -ceq '0') { throw 'STOP: original has no read permission at baseline' }
  Require-AppHash $original $expectedSrt
  Write-Host 'G1D_PERM_BASELINE_PASS'
}
function Require-Staged {
  Require-Registry
  if (-not (Test-AppFile $backup) -or -not (Test-AppFile $original)) {
    throw 'STOP: staged backup/probe missing'
  }
  if (Test-AppEntry $discard) { throw 'STOP: discard path unexpectedly occupied' }
  Require-AppHash $backup $expectedSrt
  if ((Mode-App $original) -cne '0') { throw 'STOP: probe not in POSIX mode 000' }
  if (Test-AppReadable $original) { throw 'STOP: probe remains readable under app UID' }
  Write-Host 'G1D_PERM_STAGED_NO_READ_PASS_NOT_TV_PASS'
}
switch ($Phase) {
  'Preflight' {
    Require-Baseline
    Write-Host 'G1D_PERM_PREFLIGHT_READ_ONLY_PASS'
  }
  'StageUnreadable' {
    if (-not $ApkPath -or -not (Test-Path -LiteralPath $ApkPath -PathType Leaf)) {
      throw 'STOP: specify previously audited SEL-01 APK using -ApkPath'
    }
    if ((Get-FileHash -LiteralPath $ApkPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedApk) {
      throw 'STOP: unexpected APK SHA256'
    }
    Require-Baseline
    $ok = Read-Host 'CLOSE VLC PLAYER. Type STAGE G1D DENY READ to stage an unreadable SRT copy'
    if ($ok -cne 'STAGE G1D DENY READ') { throw 'STOP: staging not approved' }
    Require-Baseline
    $originalMode = Mode-App $original
    & $adb -s $serial shell run-as $pkg mv $original $backup
    if ($LASTEXITCODE -ne 0) { throw 'STOP: original-to-backup move failed; inspect before any retry' }
    Require-AppHash $backup $expectedSrt
    if ((Mode-App $backup) -cne $originalMode) { throw 'STOP: original backup mode changed; preserve backup' }
    & $adb -s $serial shell run-as $pkg cp $backup $original
    if ($LASTEXITCODE -ne 0) { throw 'STOP: probe copy failed; run Restore to recover original' }
    Require-AppHash $original $expectedSrt
    & $adb -s $serial shell run-as $pkg chmod 000 $original
    if ($LASTEXITCODE -ne 0) { throw 'STOP: probe chmod failed; run Restore to recover original' }
    Require-Staged
    Write-Host 'G1D_PERM_FIXTURE_STAGED'
    Write-Host 'NEXT: open registered A with VLC; G1c must be absent, AV stable. Then RESTORE immediately.'
  }
  'InspectUnreadable' {
    Require-Staged
    Write-Host 'G1D_PERM_READY_FOR_VLC_TEST_NOT_REAL_TV_PASS'
  }
  'Restore' {
    Require-Registry
    if (-not (Test-AppFile $backup)) { throw 'STOP: protected original backup missing' }
    Require-AppHash $backup $expectedSrt
    $originalMode = Mode-App $backup
    if ($originalMode -ceq '0' -or -not (Test-AppReadable $backup)) {
      throw 'STOP: protected backup mode/readability changed; do not mutate'
    }
    if (Test-AppEntry $discard) { throw 'STOP: synthetic discard already exists; preserve backup' }
    if (Test-AppEntry $original) {
      if (-not (Test-AppFile $original)) { throw 'STOP: current SRT path not a regular file' }
      $currentMode = Mode-App $original
      if ($currentMode -cne '0') {
        if (-not (Test-AppReadable $original)) {
          throw 'STOP: unexpected unreadable nonzero-mode SRT; preserve backup'
        }
        Require-AppHash $original $expectedSrt
      }
    }
    $ok = Read-Host 'Type RESTORE G1D PERM to restore original readable SRT'
    if ($ok -cne 'RESTORE G1D PERM') { throw 'STOP: restore not approved' }
    Require-Registry
    Require-AppHash $backup $expectedSrt
    if ((Mode-App $backup) -cne $originalMode -or -not (Test-AppReadable $backup)) {
      throw 'STOP: protected backup changed before restore'
    }
    if (Test-AppEntry $discard) { throw 'STOP: discard path became occupied; preserve backup' }
    if (Test-AppEntry $original) {
      if (-not (Test-AppFile $original)) { throw 'STOP: current SRT path not regular' }
      $currentMode = Mode-App $original
      if ($currentMode -ceq '0') {
        & $adb -s $serial shell run-as $pkg chmod 600 $original
        if ($LASTEXITCODE -ne 0) { throw 'STOP: probe chmod 600 failed; backup intact' }
      } elseif (-not (Test-AppReadable $original)) {
        throw 'STOP: unreadable nonzero-mode SRT; backup intact'
      }
      Require-AppHash $original $expectedSrt
      & $adb -s $serial shell run-as $pkg mv $original $discard
      if ($LASTEXITCODE -ne 0) { throw 'STOP: moving probe to discard failed; backup intact' }
    }
    if (Test-AppEntry $original) { throw 'STOP: restore target remains occupied; backup intact' }
    & $adb -s $serial shell run-as $pkg mv $backup $original
    if ($LASTEXITCODE -ne 0) { throw 'STOP: restoring protected original failed; do not delete backup' }
    Require-AppHash $original $expectedSrt
    if ((Mode-App $original) -cne $originalMode -or -not (Test-AppReadable $original)) {
      throw 'STOP: original restored but mode/readability unexpected'
    }
    if (Test-AppEntry $backup) { throw 'STOP: original backup path remains after restore' }
    Write-Host 'G1D_PERM_ORIGINAL_SRT_RESTORED_HASH_AND_MODE_PASS'
    if (Test-AppEntry $discard) {
      Require-AppHash $discard $expectedSrt
      & $adb -s $serial shell run-as $pkg rm $discard
      if ($LASTEXITCODE -ne 0 -or (Test-AppEntry $discard)) {
        throw 'STOP: original restored but probe cleanup failed'
      }
    }
    Write-Host 'NEXT: reopen registered A using VLC without re-registration and verify G1c + Vietsub cues'
  }
  'VerifyRestored' {
    Require-Baseline
    Write-Host 'G1D_PERM_RESTORED_BASELINE_READ_ONLY_PASS_NOT_TV_PASS'
  }
}
