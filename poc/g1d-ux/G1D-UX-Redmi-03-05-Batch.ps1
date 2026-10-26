# G1d UX03-05: guarded Human-operated real-TV batch on exact PR29 ARM32.
# One batch authorization, but mandatory protected restore and STOP between cases.
# No TV install/uninstall, pm clear, registry edits or network setting changes.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Preflight','RunBatch','Recover','VerifyRestored')]
    [string]$Phase,
    [ValidateSet('BadSyntax','ChangedValid','Unreadable')]
    [string]$Case,
    [string]$ApkPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
$pkg = 'com.spacesarmat.omp.test'
$original = 'files/p1-g1-external.vi.srt'
$registry = 'shared_prefs/p1-g1c-subtitles.xml'
$marker = 'files/p1-g1c.register'
$legacyMarker = 'files/p1-g1.enable'
$expectedSrt = 'c96fe148c2bac63bc2bfc3768e4b3fc3d280cbbff52ad9cc03aae7679ff82f95'
$expectedApk = '8f4df47952d00d75bb6234a7620c4fc41e26995fab263d8d2db60292bc94fd85'
$protected = @(
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
$remotePaths = @(
    '/data/local/tmp/p1-g1d-ux02-badutf8-20261026.bin',
    '/data/local/tmp/p1-g1d-ux03-syntax-20261026.bin',
    '/data/local/tmp/p1-g1d-ux04-changed-20261026.bin'
)

# Deterministic fixtures borrowed conceptually from historically scoped SEL-01 tests.
$badSyntaxText = '1' + [char]10 + '00:00:00.000 --> 00:00:02.000' +
    [char]10 + 'G1D_UX03_BAD_SYNTAX' + [char]10
$changedText = '1' + [char]10 + '00:00:00,000 --> 00:00:02,000' +
    [char]10 + 'G1D_UX04_VALID_BUT_CHANGED_NOT_REGISTERED' + [char]10
[byte[]]$badSyntaxBytes = [Text.Encoding]::ASCII.GetBytes($badSyntaxText)
[byte[]]$changedBytes = [Text.Encoding]::ASCII.GetBytes($changedText)
$validCue = '(?m)^\d{1,6}\r?\n\d{2}:\d{2}:\d{2},\d{3}\s*-->\s*\d{2}:\d{2}:\d{2},\d{3}'
if ([regex]::IsMatch($badSyntaxText,$validCue) -or
    -not [regex]::IsMatch($changedText,$validCue) -or
    $badSyntaxBytes.Length -gt 256 -or $changedBytes.Length -gt 256) {
    throw 'STOP: invalid UX03/UX04 synthetic fixture definitions'
}
function Hash-Bytes([byte[]]$bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
    } finally { $sha.Dispose() }
}
$syntaxSha = Hash-Bytes $badSyntaxBytes
$changedSha = Hash-Bytes $changedBytes
if ($syntaxSha -ceq $expectedSrt -or $changedSha -ceq $expectedSrt -or
    $syntaxSha -ceq $changedSha) {
    throw 'STOP: synthetic SRT hash collides with original/other fixture'
}

if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    throw 'STOP: previously approved adb.exe not found'
}
$devices = @(& $adb devices -l)
if ($LASTEXITCODE -ne 0) { throw 'STOP: adb devices failed' }
$attached = @($devices | Where-Object { $_ -match '^\s*\S+\s+(device|offline|unauthorized)\b' })
if ($attached.Count -ne 1) { throw 'STOP: exactly one authorized ADB device required' }
$m = [regex]::Match($attached[0], '^\s*(\S+)\s+device\b')
if (-not $m.Success) { throw 'STOP: ADB device offline/unauthorized' }
$serial = $m.Groups[1].Value
$model = (& $adb -s $serial shell getprop ro.product.model | Out-String).Trim()
$api = (& $adb -s $serial shell getprop ro.build.version.sdk | Out-String).Trim()
$abi = (& $adb -s $serial shell getprop ro.product.cpu.abi | Out-String).Trim()
if ($model -cne 'MiTV-ASTR0' -or $api -cne '30' -or $abi -cne 'armeabi-v7a') {
    throw 'STOP: wrong TV model/API/ARM32'
}
Write-Host 'G1D_UX_BATCH_ARM32_DEVICE_PASS'

function Test-AppEntry([string]$path) {
    & $adb -s $serial shell run-as $pkg test -e $path
    if ($LASTEXITCODE -eq 0) { return $true }
    if ($LASTEXITCODE -eq 1) { return $false }
    throw 'STOP: app-private entry probe failed'
}
function Test-AppFile([string]$path) {
    & $adb -s $serial shell run-as $pkg test -f $path
    if ($LASTEXITCODE -eq 0) { return $true }
    if ($LASTEXITCODE -eq 1) { return $false }
    throw 'STOP: app-private regular-file probe failed'
}
function Test-RemoteEntry([string]$path) {
    & $adb -s $serial shell test -e $path
    if ($LASTEXITCODE -eq 0) { return $true }
    if ($LASTEXITCODE -eq 1) { return $false }
    throw 'STOP: remote fixture entry probe failed'
}
function Hash-App([string]$path) {
    $lines = @(& $adb -s $serial shell run-as $pkg sha256sum $path)
    if ($LASTEXITCODE -ne 0) { throw 'STOP: app-private SHA256 cannot be read' }
    $m = [regex]::Match(($lines | Out-String).Trim(), '^([0-9a-fA-F]{64})\s+')
    if (-not $m.Success) { throw 'STOP: app-private SHA256 malformed' }
    return $m.Groups[1].Value.ToLowerInvariant()
}
function Hash-Remote([string]$path) {
    $lines = @(& $adb -s $serial shell sha256sum $path)
    if ($LASTEXITCODE -ne 0) { throw 'STOP: synthetic remote SHA256 failed' }
    $m = [regex]::Match(($lines | Out-String).Trim(), '^([0-9a-fA-F]{64})\s+')
    if (-not $m.Success) { throw 'STOP: synthetic remote SHA256 malformed' }
    return $m.Groups[1].Value.ToLowerInvariant()
}
function Require-AppHash([string]$path,[string]$sha) {
    if ((Hash-App $path) -cne $sha) { throw 'STOP: app-private protected checksum mismatch' }
}
function Hash-Registry {
    if (-not (Test-AppFile $registry)) { throw 'STOP: G1c registry missing/not regular' }
    # Actual sha256sum works for the valid mode-660 XML; test -r did not.
    return (Hash-App $registry)
}
function Mode-App([string]$path) {
    $lines = @(& $adb -s $serial shell run-as $pkg stat -c '%a' $path)
    if ($LASTEXITCODE -ne 0) { throw 'STOP: stat app-private SRT mode failed' }
    $v = ($lines | Out-String).Trim()
    if ($v -notmatch '^[0-7]{1,4}$') { throw 'STOP: invalid POSIX mode' }
    return ([int]::Parse($v)).ToString()
}
function Require-NoMarkers {
    if (Test-AppEntry $marker) { throw 'STOP: pending G1c registration marker' }
    if (Test-AppEntry $legacyMarker) { throw 'STOP: pending G1b registration marker' }
}
function Require-CleanBaseline {
    $null = Hash-Registry
    Require-NoMarkers
    foreach ($path in $protected) {
        if (Test-AppEntry $path) { throw 'STOP: protected backup/discard exists; restore first' }
    }
    foreach ($path in $remotePaths) {
        if (Test-RemoteEntry $path) { throw 'STOP: remote fixture still exists' }
    }
    if (-not (Test-AppFile $original)) { throw 'STOP: original SRT missing' }
    Require-AppHash $original $expectedSrt
    $mode = Mode-App $original
    if ($mode -ceq '0') { throw 'STOP: original SRT has no readable permissions' }
    Write-Host 'G1D_UX_BATCH_SRT_REGISTRY_CLEAN_PASS'
}
# Capture ADB stderr only for native pull/push to support Windows PS 5.1.
function Invoke-AdbCaptured([string[]]$Argv) {
    $prior = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $lines = @(& $adb @Argv 2>&1)
        $nativeExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prior }
    return @{ ExitCode = $nativeExit }
}
function Hash-InstalledApk {
    $lines = @(& $adb -s $serial shell pm path $pkg)
    if ($LASTEXITCODE -ne 0) { throw 'STOP: pm path failed' }
    $lines = @($lines | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^package:' })
    if ($lines.Count -ne 1) { throw 'STOP: installed APK split/missing' }
    $m = [regex]::Match($lines[0], '^package:(/.+/base\.apk)$')
    if (-not $m.Success) { throw 'STOP: unexpected installed base.apk path' }
    $temp = Join-Path $env:TEMP ('g1d-ux-batch-apk-' + [Guid]::NewGuid().ToString('N') + '.apk')
    try {
        $pull = Invoke-AdbCaptured -Argv @('-s',$serial,'pull',$m.Groups[1].Value,$temp)
        if ($pull.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $temp -PathType Leaf)) {
            throw 'STOP: installed APK cannot be pulled'
        }
        return (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLowerInvariant()
    } finally {
        if (Test-Path -LiteralPath $temp -PathType Leaf) { Remove-Item -LiteralPath $temp -Force }
    }
}
function Require-PinnedInstalledApk {
    if ([string]::IsNullOrWhiteSpace($ApkPath) -or
        -not (Test-Path -LiteralPath $ApkPath -PathType Leaf)) {
        throw 'STOP: provide verified PR29 ARM32 APK using -ApkPath'
    }
    if ((Get-FileHash -LiteralPath $ApkPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedApk) {
        throw 'STOP: local APK SHA256 differs from PR29'
    }
    if ((Hash-InstalledApk) -cne $expectedApk) {
        throw 'STOP: installed Redmi APK SHA256 differs from PR29'
    }
    Write-Host 'G1D_UX_BATCH_INSTALLED_APK_SHA_PASS'
}
function Get-Case([string]$which) {
    switch ($which) {
        'BadSyntax' {
            return @{ Id='UX03'; Backup='files/p1-g1-external.vi.srt.g1d-syntax-backup';
                Discard='files/p1-g1-external.vi.srt.g1d-syntax-discard';
                Remote='/data/local/tmp/p1-g1d-ux03-syntax-20261026.bin';
                Fixture=$badSyntaxBytes; Digest=$syntaxSha; Unreadable=$false }
        }
        'ChangedValid' {
            return @{ Id='UX04'; Backup='files/p1-g1-external.vi.srt.g1d-changed-backup';
                Discard='files/p1-g1-external.vi.srt.g1d-changed-discard';
                Remote='/data/local/tmp/p1-g1d-ux04-changed-20261026.bin';
                Fixture=$changedBytes; Digest=$changedSha; Unreadable=$false }
        }
        'Unreadable' {
            return @{ Id='UX05'; Backup='files/p1-g1-external.vi.srt.g1d-perm-backup';
                Discard='files/p1-g1-external.vi.srt.g1d-perm-discard';
                Remote=''; Fixture=$null; Digest=$expectedSrt; Unreadable=$true }
        }
    }
    throw 'STOP: unknown batch case'
}
function Cleanup-RemoteExact($cfg) {
    if ($cfg.Unreadable -or -not (Test-RemoteEntry $cfg.Remote)) { return }
    if ((Hash-Remote $cfg.Remote) -cne $cfg.Digest) {
        throw 'STOP: unknown data in fixed remote fixture path; never delete'
    }
    & $adb -s $serial shell rm $cfg.Remote
    if ($LASTEXITCODE -ne 0 -or (Test-RemoteEntry $cfg.Remote)) {
        throw 'STOP: remote fixture cleanup failed'
    }
}
function Test-ProbeReadDenied {
    # Actual attempted app-UID read, not test -r (known false-negative on XML).
    $prior = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $lines = @(& $adb -s $serial shell run-as $pkg sha256sum $original 2>&1)
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prior }
    if ($exitCode -eq 0) { throw 'STOP: permission-denied probe remained SHA256-readable' }
    if (($lines | Out-String) -notmatch 'Permission denied|EACCES') {
        throw 'STOP: probe SHA256 failed for reason other than permission denied'
    }
}
function Require-Staged($cfg) {
    $null = Hash-Registry
    Require-NoMarkers
    if (Test-AppEntry $cfg.Discard) { throw 'STOP: unexpected case discard occupied' }
    if (-not (Test-AppFile $cfg.Backup) -or -not (Test-AppFile $original)) {
        throw 'STOP: staged original or protected backup missing'
    }
    Require-AppHash $cfg.Backup $expectedSrt
    if ($cfg.Unreadable) {
        if ((Mode-App $original) -cne '0') { throw 'STOP: unreadable probe is not mode 000' }
        Test-ProbeReadDenied
    } else {
        Require-AppHash $original $cfg.Digest
    }
    Write-Host ('G1D_' + $cfg.Id + '_STAGED_SHA_AND_BACKUP_PASS_NOT_TV_UX_PASS')
}
function Stage-Case($cfg) {
    Require-PinnedInstalledApk
    Require-CleanBaseline
    $registryBefore = Hash-Registry
    $priorMode = Mode-App $original
    if ($cfg.Unreadable) {
        # The original inode is protected BEFORE any copy chmod.
        & $adb -s $serial shell run-as $pkg mv $original $cfg.Backup
        if ($LASTEXITCODE -ne 0) { throw 'STOP: cannot preserve original SRT inode' }
        Require-AppHash $cfg.Backup $expectedSrt
        if ((Mode-App $cfg.Backup) -cne $priorMode) {
            throw 'STOP: original protected SRT permissions changed unexpectedly'
        }
        & $adb -s $serial shell run-as $pkg cp $cfg.Backup $original
        if ($LASTEXITCODE -ne 0) { throw 'STOP: cannot copy disposable SRT probe; recover' }
        Require-AppHash $original $expectedSrt
        & $adb -s $serial shell run-as $pkg chmod 000 $original
        if ($LASTEXITCODE -ne 0) { throw 'STOP: cannot deny read on probe; recover' }
    } else {
        $temp = Join-Path $env:TEMP ('g1d-' + $cfg.Id + '-fixture-' + [Guid]::NewGuid().ToString('N') + '.bin')
        try {
            [IO.File]::WriteAllBytes($temp,[byte[]]$cfg.Fixture)
            if ((Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLowerInvariant() -cne $cfg.Digest) {
                throw 'STOP: synthetic local fixture SHA mismatch'
            }
            if (Test-RemoteEntry $cfg.Remote) { throw 'STOP: remote fixed path occupied' }
            $push = Invoke-AdbCaptured -Argv @('-s',$serial,'push',$temp,$cfg.Remote)
            if ($push.ExitCode -ne 0 -or (Hash-Remote $cfg.Remote) -cne $cfg.Digest) {
                throw 'STOP: synthetic remote fixture push/hash failed'
            }
            Require-PinnedInstalledApk
            # The synthetic remote path is now legitimately occupied. Recheck
            # the entire app-private baseline and all OTHER remote paths.
            $null = Hash-Registry
            Require-NoMarkers
            foreach ($path in $protected) {
                if (Test-AppEntry $path) { throw 'STOP: backup/fixture unexpectedly staged' }
            }
            if (-not (Test-AppFile $original)) { throw 'STOP: original SRT missing' }
            Require-AppHash $original $expectedSrt
            foreach ($path in $remotePaths) {
                if ($path -cne $cfg.Remote -and (Test-RemoteEntry $path)) {
                    throw 'STOP: unrelated remote synthetic fixture appeared'
                }
            }
            if ((Hash-Remote $cfg.Remote) -cne $cfg.Digest) {
                throw 'STOP: just-pushed synthetic fixture changed'
            }
            if ((Hash-Registry) -cne $registryBefore) {
                throw 'STOP: G1c registry changed before protected rename'
            }
            & $adb -s $serial shell run-as $pkg mv $original $cfg.Backup
            if ($LASTEXITCODE -ne 0) { throw 'STOP: cannot protect original SRT' }
            Require-AppHash $cfg.Backup $expectedSrt
            & $adb -s $serial shell run-as $pkg cp $cfg.Remote $original
            if ($LASTEXITCODE -ne 0) { throw 'STOP: synthetic SRT copy failed; recover' }
        } finally {
            if (Test-Path -LiteralPath $temp -PathType Leaf) {
                Remove-Item -LiteralPath $temp -Force
            }
            Cleanup-RemoteExact $cfg
        }
    }
    Require-Staged $cfg
    if ((Hash-Registry) -cne $registryBefore) { throw 'STOP: registry changed during Stage' }
    Write-Host ('G1D_' + $cfg.Id + '_STAGE_PASS_NOT_TV_UX_PASS')
}
function Restore-Case($cfg) {
    # Recovery may run after interrupted Stage and NEVER needs local APK/prefs.
    # In particular: unknown SRT file is NOT overwritten/deleted.
    if (-not (Test-AppFile $cfg.Backup)) { throw 'STOP: protected original backup missing' }
    Require-AppHash $cfg.Backup $expectedSrt
    if (Test-AppEntry $cfg.Discard) { throw 'STOP: discard path occupied; preserve backup' }
    if (Test-AppEntry $original) {
        if (-not (Test-AppFile $original)) { throw 'STOP: current SRT is not a regular file' }
        if ($cfg.Unreadable) {
            $probeMode = Mode-App $original
            if ($probeMode -ceq '0') {
                & $adb -s $serial shell run-as $pkg chmod 600 $original
                if ($LASTEXITCODE -ne 0) { throw 'STOP: failed to make disposable probe readable' }
            }
            Require-AppHash $original $expectedSrt
        } else {
            Require-AppHash $original $cfg.Digest
        }
        & $adb -s $serial shell run-as $pkg mv $original $cfg.Discard
        if ($LASTEXITCODE -ne 0) { throw 'STOP: failed to isolate disposable test file' }
    }
    if (Test-AppEntry $original) { throw 'STOP: original path occupied; refuse overwrite' }
    Require-AppHash $cfg.Backup $expectedSrt
    & $adb -s $serial shell run-as $pkg mv $cfg.Backup $original
    if ($LASTEXITCODE -ne 0) { throw 'STOP: cannot restore original SRT; backup may survive' }
    Require-AppHash $original $expectedSrt
    if (Test-AppEntry $cfg.Backup) { throw 'STOP: protected backup remains unexpectedly' }
    if ((Mode-App $original) -ceq '0') { throw 'STOP: restored original has mode 000' }
    Write-Host ('G1D_' + $cfg.Id + '_ORIGINAL_SRT_RESTORED_SHA_PASS')
    if (Test-AppEntry $cfg.Discard) {
        Require-AppHash $cfg.Discard $cfg.Digest
        & $adb -s $serial shell run-as $pkg rm $cfg.Discard
        if ($LASTEXITCODE -ne 0 -or (Test-AppEntry $cfg.Discard)) {
            throw 'STOP: original restored, but synthetic discard cleanup failed'
        }
    }
    Cleanup-RemoteExact $cfg
}
function Restore-IfProtected($cfg) {
    if (Test-AppEntry $cfg.Backup) {
        Restore-Case $cfg
        Write-Host ('G1D_' + $cfg.Id + '_RESTORE_CLEANUP_PASS')
    } else {
        # If Stage failed before touching original, baseline still has to be clean.
        Write-Host ('G1D_' + $cfg.Id + '_NO_BACKUP_TO_RESTORE')
    }
    Require-CleanBaseline
    Write-Host ('G1D_' + $cfg.Id + '_RESTORED_BASELINE_PASS_NOT_TV_UX_PASS')
}
function Require-PassWord([string]$message) {
    $answer = Read-Host $message
    if ($answer -ceq 'PASS') { return $true }
    if ($answer -ceq 'FAIL') { return $false }
    throw 'STOP: answer must be PASS or FAIL; recovery is attempted'
}
function Run-OneCase($cfg) {
    Write-Host ('CASE ' + $cfg.Id + ': close VLC on TV; press ENTER when closed')
    $null = Read-Host 'Press ENTER after closing VLC'
    $onTv = $false
    $stageCompleted = $false
    try {
        Stage-Case $cfg
        $stageCompleted = $true
        Write-Host ('CASE ' + $cfg.Id + ': now open registered film A, saved G1c ON, in a NEW VLC session')
        Write-Host 'Check ONE nonblocking Vietnamese warning, no G1c track, AV/remote/seek OK, no data leak.'
        $onTv = Require-PassWord ('Type PASS or FAIL for ' + $cfg.Id + ' negative real-TV checks, after closing VLC')
    } finally {
        # Even if visual check FAIL or PowerShell throws, attempt guarded recovery.
        # If recovery STOPs, do not run another case.
        Restore-IfProtected $cfg
    }
    if (-not $stageCompleted) { throw ('STOP: ' + $cfg.Id + ' never finished Stage') }
    Write-Host ('CASE ' + $cfg.Id + ': reopen film A in NEW VLC session after Restore.')
    Write-Host 'Check saved G1c ON, Vietnamese cues, AV okay, NO warning.'
    $returned = Require-PassWord ('Type PASS or FAIL for ' + $cfg.Id + ' post-Restore TV smoke')
    if (-not $returned) { throw ('STOP: ' + $cfg.Id + ' TV restore smoke failed') }
    if (-not $onTv) { throw ('STOP: ' + $cfg.Id + ' warning or player checks failed') }
    Write-Host ('G1D_' + $cfg.Id + '_TV_WARNING_AND_RESTORE_HUMAN_PASS')
}
switch ($Phase) {
    'Preflight' {
        Require-PinnedInstalledApk
        Require-CleanBaseline
        Write-Host 'G1D_UX_BATCH_PREFLIGHT_READ_ONLY_PASS'
    }
    'RunBatch' {
        Require-PinnedInstalledApk
        Require-CleanBaseline
        $approved = Read-Host 'Type RUN G1D UX03 UX04 UX05 BATCH to run exactly THREE staged cases with mandatory Restore'
        if ($approved -cne 'RUN G1D UX03 UX04 UX05 BATCH') {
            throw 'STOP: whole-case batch not approved'
        }
        foreach ($name in @('BadSyntax','ChangedValid','Unreadable')) {
            Require-PinnedInstalledApk
            Require-CleanBaseline
            $cfg = Get-Case $name
            Run-OneCase $cfg
        }
        Require-PinnedInstalledApk
        Require-CleanBaseline
        Write-Host 'G1D_UX03_UX04_UX05_BATCH_TV_HUMAN_PASS'
    }
    'Recover' {
        if ([string]::IsNullOrWhiteSpace($Case)) {
            throw 'STOP: -Case BadSyntax, ChangedValid, or Unreadable required'
        }
        $cfg = Get-Case $Case
        # Does not ask for APK or require the G1c registry to be available.
        # Human must explicitly request per-case recovery and inspect STOPs.
        $approved = Read-Host ('Type RECOVER ' + $cfg.Id + ' SRT to restore known protected original')
        if ($approved -cne ('RECOVER ' + $cfg.Id + ' SRT')) { throw 'STOP: Recover not approved' }
        Restore-IfProtected $cfg
    }
    'VerifyRestored' {
        Require-PinnedInstalledApk
        Require-CleanBaseline
        Write-Host 'G1D_UX_BATCH_VERIFY_RESTORED_READ_ONLY_PASS'
    }
}
