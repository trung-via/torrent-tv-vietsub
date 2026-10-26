# G1d VALID-CHANGED synthetic SRT test. HUMAN-RUN ONLY. No install, data reset, marker or registry writes.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [ValidateSet('Preflight','StageChangedValid','InspectChangedValid','Restore','VerifyRestored')]
  [string]$Phase,
  [string]$ApkPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
$pkg = 'com.spacesarmat.omp.test'
$original = 'files/p1-g1-external.vi.srt'
$backup = 'files/p1-g1-external.vi.srt.g1d-changed-backup'
$discard = 'files/p1-g1-external.vi.srt.g1d-changed-discard'
$oldBackup = 'files/p1-g1-external.vi.srt.g1d-backup'
$remoteFixture = '/data/local/tmp/p1-g1d-changedvalid-20261026.bin'
$registry = 'shared_prefs/p1-g1c-subtitles.xml'
$marker = 'files/p1-g1c.register'
$legacyMarker = 'files/p1-g1.enable'
$expectedSrt = 'c96fe148c2bac63bc2bfc3768e4b3fc3d280cbbff52ad9cc03aae7679ff82f95'
$expectedApk = 'ae132b6ea76e68dddde5a4632ec2d75c5e94f26bee71e063936520a13af39617'
# Modified valid SRT: strict UTF-8 and a correct comma-delimited SRT cue,
# but altered bytes deliberately mismatch all previously registered SRT hashes.
$head = '1' + [char]10 + '00:00:00,000 --> 00:00:02,000' + [char]10
$buf = New-Object 'System.Collections.Generic.List[byte]'
$buf.AddRange([Text.Encoding]::ASCII.GetBytes($head))

$buf.AddRange([Text.Encoding]::ASCII.GetBytes('G1D_VALID_CHANGED_DO_NOT_REGISTER' + [char]10))
[byte[]]$fixtureBytes = $buf.ToArray()
$shaObj = [Security.Cryptography.SHA256]::Create()
try { $fixtureSha = -join ($shaObj.ComputeHash($fixtureBytes) | ForEach-Object { $_.ToString('x2') }) }
finally { $shaObj.Dispose() }
# Self-check: valid strict UTF-8 and exact Kotlin cue signature DO match,
# yet the content SHA256 intentionally differs from the registered original.
$changedStrict = [Text.UTF8Encoding]::new($false, $true)
$fixtureText = $changedStrict.GetString($fixtureBytes)
$validCuePattern = '(?m)^\d{1,6}\r?\n\d{2}:\d{2}:\d{2},\d{3}\s*-->\s*\d{2}:\d{2}:\d{2},\d{3}'
if ($fixtureBytes.Length -gt 256 -or
    -not ([regex]::IsMatch($fixtureText, $validCuePattern)) -or
    $fixtureSha -ceq $expectedSrt) {
  throw 'STOP: valid-but-changed SRT fixture failed preflight self-check'
}
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
if ($model -cne 'MiTV-ASTR0' -or $api -cne '30' -or $abi -cne 'armeabi-v7a') { throw 'STOP: wrong TV/API/ABI' }
Write-Host 'G1D_CHANGED_REDMI_MATCH'

function Test-AppEntry([string]$p) {
  & $adb -s $serial shell run-as $pkg test -e $p
  if ($LASTEXITCODE -eq 0) { return $true }
  if ($LASTEXITCODE -eq 1) { return $false }
  throw 'STOP: run-as file existence check failed'
}
function Test-AppFile([string]$p) {
  & $adb -s $serial shell run-as $pkg test -f $p
  if ($LASTEXITCODE -eq 0) { return $true }
  if ($LASTEXITCODE -eq 1) { return $false }
  throw 'STOP: run-as regular file check failed'
}
function Test-RemoteEntry {
  & $adb -s $serial shell test -e $remoteFixture
  if ($LASTEXITCODE -eq 0) { return $true }
  if ($LASTEXITCODE -eq 1) { return $false }
  throw 'STOP: remote fixture existence check failed'
}
function Hash-App([string]$p) {
  $out = @(& $adb -s $serial shell run-as $pkg sha256sum $p)
  if ($LASTEXITCODE -ne 0) { throw 'STOP: app-private sha256sum failed' }
  $m = [regex]::Match(($out | Out-String).Trim(), '^([a-fA-F0-9]{64})\s+')
  if (-not $m.Success) { throw 'STOP: invalid app-private hash result' }
  return $m.Groups[1].Value.ToLowerInvariant()
}
function Hash-Remote {
  $out = @(& $adb -s $serial shell sha256sum $remoteFixture)
  if ($LASTEXITCODE -ne 0) { throw 'STOP: remote sha256sum failed' }
  $m = [regex]::Match(($out | Out-String).Trim(), '^([a-fA-F0-9]{64})\s+')
  if (-not $m.Success) { throw 'STOP: invalid remote hash result' }
  return $m.Groups[1].Value.ToLowerInvariant()
}
function Require-AppHash([string]$p,[string]$expected) {
  if ((Hash-App $p) -cne $expected) { throw 'STOP: protected app-private SHA256 mismatch' }
}
function Require-Registry {
  if (-not (Test-AppFile $registry)) { throw 'STOP: G1c registry missing' }
  if ((Test-AppEntry $marker) -or (Test-AppEntry $legacyMarker)) { throw 'STOP: registration marker present' }
}
function Require-Baseline {
  Require-Registry
  foreach ($p in @($backup,$discard,$oldBackup)) {
    if (Test-AppEntry $p) { throw 'STOP: protected backup/discard path occupied' }
  }
  if (-not (Test-AppFile $original)) { throw 'STOP: original SRT missing' }
  Require-AppHash $original $expectedSrt
  Write-Host 'G1D_CHANGED_BASELINE_PASS'
}
function Require-Staged {
  Require-Registry
  if (-not (Test-AppFile $original) -or -not (Test-AppFile $backup)) { throw 'STOP: staged SRT/backup missing' }
  if (Test-AppEntry $discard) { throw 'STOP: discard already exists' }
  Require-AppHash $original $fixtureSha
  Require-AppHash $backup $expectedSrt
  Write-Host 'G1D_CHANGED_STAGED_HASH_PASS_NOT_TV_PASS'
}
function Remove-RemoteIfExact {
  if (-not (Test-RemoteEntry)) { return }
  if ((Hash-Remote) -cne $fixtureSha) { throw 'STOP: remote fixture hash mismatch; do not delete' }
  & $adb -s $serial shell rm $remoteFixture
  if ($LASTEXITCODE -ne 0 -or (Test-RemoteEntry)) { throw 'STOP: remote fixture cleanup failed' }
}
switch ($Phase) {
  'Preflight' {
    Require-Baseline
    if (Test-RemoteEntry) { throw 'STOP: remote fixture path occupied' }
    Write-Host 'G1D_CHANGED_PREFLIGHT_READ_ONLY_PASS'
  }
  'StageChangedValid' {
    if (-not $ApkPath -or -not (Test-Path -LiteralPath $ApkPath -PathType Leaf)) {
      throw 'STOP: specify previously audited SEL-01 APK using -ApkPath'
    }
    if ((Get-FileHash -LiteralPath $ApkPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedApk) {
      throw 'STOP: unexpected APK SHA256'
    }
    Require-Baseline
    if (Test-RemoteEntry) { throw 'STOP: remote fixture path occupied' }
    $ok = Read-Host 'CLOSE VLC PLAYER. Type STAGE G1D VALID CHANGED to temporarily stage a synthetic invalid SRT'
    if ($ok -cne 'STAGE G1D VALID CHANGED') { throw 'STOP: staging not approved' }
    Require-Baseline
    if (Test-RemoteEntry) { throw 'STOP: remote fixture path became occupied' }
    $local = Join-Path ([IO.Path]::GetTempPath()) ('g1d-changed-' + [guid]::NewGuid().ToString('N') + '.bin')
    try {
      [IO.File]::WriteAllBytes($local,$fixtureBytes)
      if ((Get-FileHash -LiteralPath $local -Algorithm SHA256).Hash.ToLowerInvariant() -cne $fixtureSha) {
        throw 'STOP: local synthetic fixture hash mismatch'
      }
      & $adb -s $serial push $local $remoteFixture | Out-Null
      if ($LASTEXITCODE -ne 0) { throw 'STOP: adb push failed; original SRT untouched unless explicitly moved' }
      if ((Hash-Remote) -cne $fixtureSha) { throw 'STOP: remote fixture hash mismatch; original untouched' }
      Require-Baseline
      & $adb -s $serial shell run-as $pkg mv $original $backup
      if ($LASTEXITCODE -ne 0) { throw 'STOP: protected SRT backup failed' }
      Require-AppHash $backup $expectedSrt
      & $adb -s $serial shell run-as $pkg cp $remoteFixture $original
      if ($LASTEXITCODE -ne 0) { throw 'STOP: fixture copy failed; run Restore to recover original' }
      Require-Staged
      Write-Host 'G1D_CHANGED_FIXTURE_STAGED'
      Write-Host 'NEXT: open registered A with VLC; G1c must be absent, playback stable. Then RESTORE immediately'
    } finally {
      if (Test-Path -LiteralPath $local -PathType Leaf) { Remove-Item -LiteralPath $local -Force }
      Remove-RemoteIfExact
    }
  }
  'InspectChangedValid' {
    Require-Staged
    Write-Host 'G1D_CHANGED_READY_FOR_VLC_TEST_NOT_REAL_TV_PASS'
  }
  'Restore' {
    if (-not (Test-AppFile $backup)) { throw 'STOP: protected SRT backup missing' }
    Require-AppHash $backup $expectedSrt
    if (Test-AppEntry $discard) { throw 'STOP: discard path occupied; do not overwrite' }
    if (Test-AppEntry $original) {
      if (-not (Test-AppFile $original)) { throw 'STOP: original path not regular file' }
      Require-AppHash $original $fixtureSha
    }
    $ok = Read-Host 'Type RESTORE G1D CHANGED to restore exact original SRT'
    if ($ok -cne 'RESTORE G1D CHANGED') { throw 'STOP: restore not approved' }
    Require-AppHash $backup $expectedSrt
    if (Test-AppEntry $discard) { throw 'STOP: discard path became occupied' }
    if (Test-AppEntry $original) {
      Require-AppHash $original $fixtureSha
      & $adb -s $serial shell run-as $pkg mv $original $discard
      if ($LASTEXITCODE -ne 0) { throw 'STOP: moving fixture to discard failed; protected backup intact' }
    }
    if (Test-AppEntry $original) { throw 'STOP: target still occupied; protected backup intact' }
    & $adb -s $serial shell run-as $pkg mv $backup $original
    if ($LASTEXITCODE -ne 0) { throw 'STOP: restoring backup failed; do not delete protected files' }
    Require-AppHash $original $expectedSrt
    if (Test-AppEntry $backup) { throw 'STOP: backup path remains' }
    Write-Host 'G1D_CHANGED_ORIGINAL_SRT_RESTORED_HASH_PASS'
    if (Test-AppEntry $discard) {
      Require-AppHash $discard $fixtureSha
      & $adb -s $serial shell run-as $pkg rm $discard
      if ($LASTEXITCODE -ne 0 -or (Test-AppEntry $discard)) {
        throw 'STOP: original restored but synthetic discard cleanup failed'
      }
    }
    Remove-RemoteIfExact
    Write-Host 'NEXT: reopen registered A using VLC, without re-registration; verify exact G1c track and Vietnamese cues'
  }
  'VerifyRestored' {
    Require-Baseline
    if (Test-RemoteEntry) { throw 'STOP: remote fixture still present' }
    Write-Host 'G1D_CHANGED_RESTORED_BASELINE_READ_ONLY_PASS_NOT_TV_PASS'
  }
}
