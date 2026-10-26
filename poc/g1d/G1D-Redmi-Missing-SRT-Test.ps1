# G1d missing independent SRT test — HUMAN-RUN ONLY.
# No Windows settings, firewall, ADB connect, install/uninstall, app data clear or marker changes.
# StageMissing atomically RENAMES the original SRT to an app-private backup. Restore renames it back.
# Test only legally accessible media; do not share torrent URL, magnet, raw hash or TV serial.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Preflight','StageMissing','ObserveMissing','Restore','VerifyRestored')]
    [string]$Phase,
    [string]$ApkPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
$pkg = 'com.spacesarmat.omp.test'
$original = 'files/p1-g1-external.vi.srt'
$backup = 'files/p1-g1-external.vi.srt.g1d-backup'
$registry = 'shared_prefs/p1-g1c-subtitles.xml'
$marker = 'files/p1-g1c.register'
$g1bMarker = 'files/p1-g1.enable'
$expectedSrt = 'c96fe148c2bac63bc2bfc3768e4b3fc3d280cbbff52ad9cc03aae7679ff82f95'
$expectedApk = 'ae132b6ea76e68dddde5a4632ec2d75c5e94f26bee71e063936520a13af39617'

if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    throw 'STOP: adb.exe not found at previously authorized path'
}

$rawDevices = @(& $adb devices -l)
if ($LASTEXITCODE -ne 0) { throw 'STOP: adb devices failed' }
$attached = @($rawDevices | Where-Object { $_ -match '^\s*\S+\s+(device|offline|unauthorized)\b' })
if ($attached.Count -ne 1 -or $attached[0] -notmatch '^\s*(\S+)\s+device\b') {
    throw 'STOP: expected exactly one authorized connected ADB device'
}
$serial = $Matches[1]

$model = (& $adb -s $serial shell getprop ro.product.model | Out-String).Trim()
$api = (& $adb -s $serial shell getprop ro.build.version.sdk | Out-String).Trim()
$abi = (& $adb -s $serial shell getprop ro.product.cpu.abi | Out-String).Trim()
if ($model -cne 'MiTV-ASTR0' -or $api -cne '30' -or $abi -cne 'armeabi-v7a') {
    throw 'STOP: wrong device model/API/ABI'
}
Write-Host 'G1D_REDMI_MATCH: MiTV-ASTR0 / API 30 / armeabi-v7a'

function Test-AppFile([string]$relative) {
    & $adb -s $serial shell run-as $pkg test -f $relative
    $result = $LASTEXITCODE
    if ($result -eq 0) { return $true }
    if ($result -eq 1) { return $false }
    throw 'STOP: app-private run-as file test failed'
}
function Assert-RemoteDigest([string]$relative) {
    $raw = @(& $adb -s $serial shell run-as $pkg sha256sum $relative)
    if ($LASTEXITCODE -ne 0) { throw 'STOP: app-private SHA256 command failed' }
    $line = ($raw | Out-String).Trim()
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+') { throw 'STOP: invalid sha256sum output' }
    if ($Matches[1].ToLowerInvariant() -cne $expectedSrt) {
        throw 'STOP: external SRT SHA256 mismatch'
    }
    Write-Host 'G1D_SRT_SHA256_MATCH'
}
function Assert-Baseline {
    if (-not (Test-AppFile $registry)) { throw 'STOP: existing G1c registry missing' }
    if (Test-AppFile $marker) { throw 'STOP: pending G1c registration marker' }
    if (Test-AppFile $g1bMarker) { throw 'STOP: pending legacy G1b marker' }
    if (Test-AppFile $backup) {
        throw 'STOP: G1d backup already exists; use Restore, NEVER overwrite it'
    }
    if (-not (Test-AppFile $original)) { throw 'STOP: original SRT missing; do not stage' }
    Assert-RemoteDigest $original
    Write-Host 'G1D_BASELINE_PASS'
}
function Assert-StagedMissing {
    if (-not (Test-AppFile $registry)) { throw 'STOP: saved registry missing' }
    if (Test-AppFile $marker) { throw 'STOP: unexpected G1c marker; Restore is still available' }
    if (Test-AppFile $g1bMarker) { throw 'STOP: unexpected G1b marker; Restore is still available' }
    if (Test-AppFile $original) { throw 'STOP: original SRT still present' }
    if (-not (Test-AppFile $backup)) { throw 'STOP: protected G1d backup is missing' }
    Assert-RemoteDigest $backup
    Write-Host 'G1D_MISSING_FILE_STAGED'
}
function Assert-LocalApk {
    if ([string]::IsNullOrWhiteSpace($ApkPath) -or
        -not (Test-Path -LiteralPath $ApkPath -PathType Leaf)) {
        throw 'STOP: StageMissing requires -ApkPath pointing to audited SEL-01 ARM32 APK'
    }
    $digest = (Get-FileHash -LiteralPath $ApkPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($digest -cne $expectedApk) { throw 'STOP: SEL-01 ARM32 APK SHA256 mismatch' }
    Write-Host 'G1D_SEL01_APK_SHA256_MATCH'
}

switch ($Phase) {
    'Preflight' {
        Assert-Baseline
        Write-Host 'G1D_PREFLIGHT_PASS_READ_ONLY'
    }
    'StageMissing' {
        Assert-LocalApk
        Assert-Baseline
        $yes = Read-Host 'CLOSE TV PLAYER. Type STAGE G1D MISSING to temporarily rename only the independent SRT'
        if ($yes -cne 'STAGE G1D MISSING') { throw 'STOP: staging not approved' }
        # Repeat the guard immediately before the single rename.
        Assert-Baseline
        & $adb -s $serial shell run-as $pkg mv $original $backup
        if ($LASTEXITCODE -ne 0) { throw 'STOP: rename failed; inspect state with Preflight or Restore' }
        try {
            Assert-StagedMissing
        } catch {
            # Roll back only if we can prove the protected backup is intact.
            $stageReason = $_.Exception.Message
            if (-not (Test-AppFile $original) -and (Test-AppFile $backup)) {
                Assert-RemoteDigest $backup
                & $adb -s $serial shell run-as $pkg mv $backup $original
                if ($LASTEXITCODE -eq 0) {
                    Assert-RemoteDigest $original
                    Write-Host 'G1D_STAGE_ROLLED_BACK'
                }
            }
            throw "STOP: post-stage verification failed; inspect backup/original. $stageReason"
        }
        Write-Host 'NEXT: open SAME registered video A via VLC, confirm no G1c track and video/audio still work; then run Restore'
    }
    'ObserveMissing' {
        Assert-StagedMissing
        Write-Host 'G1D_MISSING_PRECONDITIONS_PASS_NOT_TV_RENDER_PASS'
        Write-Host 'Human evidence needed: G1c track absent, no crash, playback/audio survive'
        Write-Host 'NEXT: Restore the SRT immediately after observation'
    }
    'Restore' {
        # Recovery does NOT depend on APK path, registry presence or marker state.
        if (Test-AppFile $original) {
            throw 'STOP: original path occupied; do not overwrite or delete either file'
        }
        if (-not (Test-AppFile $backup)) { throw 'STOP: protected backup missing' }
        Assert-RemoteDigest $backup
        $yes = Read-Host 'Type RESTORE G1D SRT to restore the exact original independent SRT'
        if ($yes -cne 'RESTORE G1D SRT') { throw 'STOP: restore not approved' }
        if (Test-AppFile $original) { throw 'STOP: original path appeared unexpectedly' }
        Assert-RemoteDigest $backup
        & $adb -s $serial shell run-as $pkg mv $backup $original
        if ($LASTEXITCODE -ne 0) { throw 'STOP: restore rename failed; preserve backup and investigate' }
        Assert-RemoteDigest $original
        if (Test-AppFile $backup) { throw 'STOP: backup still present after restore' }
        Write-Host 'G1D_ORIGINAL_SRT_RESTORED_HASH_PASS'
        Write-Host 'NEXT: open SAME film A via VLC without Register; verify G1c track and Vietnamese cues restored'
    }
    'VerifyRestored' {
        Assert-Baseline
        Write-Host 'G1D_RESTORE_PREFLIGHT_PASS_NOT_TV_RENDER_PASS'
    }
}
