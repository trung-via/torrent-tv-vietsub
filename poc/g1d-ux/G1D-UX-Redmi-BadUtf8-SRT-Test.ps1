# G1d UX-02: strict invalid UTF-8 SRT warning on human-owned Redmi.
# HUMAN-RUN ONLY; must never install APK, clear app data, or edit registry.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Preflight','StageBadUtf8','InspectBadUtf8','Restore','VerifyRestored')]
    [string]$Phase,
    [string]$ApkPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
$pkg = 'com.spacesarmat.omp.test'
$original = 'files/p1-g1-external.vi.srt'
$backup = 'files/p1-g1-external.vi.srt.g1d-utf8-backup'
$discard = 'files/p1-g1-external.vi.srt.g1d-utf8-discard'
$registry = 'shared_prefs/p1-g1c-subtitles.xml'
$marker = 'files/p1-g1c.register'
$g1bMarker = 'files/p1-g1.enable'
$remoteFixture = '/data/local/tmp/p1-g1d-ux02-badutf8-20261026.bin'
$expectedSrt = 'c96fe148c2bac63bc2bfc3768e4b3fc3d280cbbff52ad9cc03aae7679ff82f95'
$expectedApk = '8f4df47952d00d75bb6234a7620c4fc41e26995fab263d8d2db60292bc94fd85'
$otherProtected = @(
    'files/p1-g1-external.vi.srt.g1d-backup',
    'files/p1-g1-external.vi.srt.g1d-syntax-backup',
    'files/p1-g1-external.vi.srt.g1d-syntax-discard',
    'files/p1-g1-external.vi.srt.g1d-changed-backup',
    'files/p1-g1-external.vi.srt.g1d-changed-discard',
    'files/p1-g1-external.vi.srt.g1d-perm-backup',
    'files/p1-g1-external.vi.srt.g1d-perm-discard'
)

# Valid SRT time-code structure; intentionally invalid byte FF in cue text.
# This must not become a genuine subtitle that can be selected on the TV.
$head = '1' + [char]10 + '00:00:00,000 --> 00:00:02,000' + [char]10
$bytes = New-Object 'System.Collections.Generic.List[byte]'
$bytes.AddRange([Text.Encoding]::ASCII.GetBytes($head))
$bytes.Add([byte]255)
$bytes.AddRange([Text.Encoding]::ASCII.GetBytes('G1D_UX02_BAD_UTF8' + [char]10))
[byte[]]$fixtureBytes = $bytes.ToArray()
if ($fixtureBytes.Length -gt 256 -or $fixtureBytes -notcontains [byte]255) {
    throw 'STOP: invalid synthetic bad-UTF8 fixture bytes'
}
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $fixtureSha = -join ($sha.ComputeHash($fixtureBytes) | ForEach-Object { $_.ToString('x2') })
} finally {
    $sha.Dispose()
}

if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) { throw 'STOP: authorized adb.exe not found' }
$deviceLines = @(& $adb devices -l)
if ($LASTEXITCODE -ne 0) { throw 'STOP: adb devices failed' }
$attached = @($deviceLines | Where-Object { $_ -match '^\s*\S+\s+(device|offline|unauthorized)\b' })
if ($attached.Count -ne 1) { throw 'STOP: expected exactly one authorized ADB device entry' }
$found = [regex]::Match($attached[0], '^\s*(\S+)\s+device\b')
if (-not $found.Success) { throw 'STOP: ADB device offline/unauthorized' }
$serial = $found.Groups[1].Value
$model = (& $adb -s $serial shell getprop ro.product.model | Out-String).Trim()
$api = (& $adb -s $serial shell getprop ro.build.version.sdk | Out-String).Trim()
$abi = (& $adb -s $serial shell getprop ro.product.cpu.abi | Out-String).Trim()
if ($model -cne 'MiTV-ASTR0' -or $api -cne '30' -or $abi -cne 'armeabi-v7a') {
    throw 'STOP: wrong Redmi TV model/API/ABI'
}
Write-Host 'G1D_UX02_REDMI_ARM32_DEVICE_PASS'

function Test-AppEntry([string]$name) {
    & $adb -s $serial shell run-as $pkg test -e $name
    if ($LASTEXITCODE -eq 0) { return $true }
    if ($LASTEXITCODE -eq 1) { return $false }
    throw 'STOP: app-private entry inspection failed'
}
function Test-AppFile([string]$name) {
    & $adb -s $serial shell run-as $pkg test -f $name
    if ($LASTEXITCODE -eq 0) { return $true }
    if ($LASTEXITCODE -eq 1) { return $false }
    throw 'STOP: app-private file inspection failed'
}
function Test-RemoteEntry {
    & $adb -s $serial shell test -e $remoteFixture
    if ($LASTEXITCODE -eq 0) { return $true }
    if ($LASTEXITCODE -eq 1) { return $false }
    throw 'STOP: remote fixture entry inspection failed'
}
function Hash-App([string]$name) {
    $output = @(& $adb -s $serial shell run-as $pkg sha256sum $name)
    if ($LASTEXITCODE -ne 0) { throw 'STOP: app-private file cannot be hashed/read' }
    $m = [regex]::Match(($output | Out-String).Trim(), '^([0-9a-fA-F]{64})\s+')
    if (-not $m.Success) { throw 'STOP: app-private SHA256 output malformed' }
    return $m.Groups[1].Value.ToLowerInvariant()
}
function Hash-Remote {
    $output = @(& $adb -s $serial shell sha256sum $remoteFixture)
    if ($LASTEXITCODE -ne 0) { throw 'STOP: synthetic fixture cannot be hashed/read' }
    $m = [regex]::Match(($output | Out-String).Trim(), '^([0-9a-fA-F]{64})\s+')
    if (-not $m.Success) { throw 'STOP: fixture SHA256 output malformed' }
    return $m.Groups[1].Value.ToLowerInvariant()
}
function Require-AppHash([string]$name,[string]$value) {
    if ((Hash-App $name) -cne $value) { throw 'STOP: protected file SHA256 mismatch' }
}
function Hash-Registry {
    if (-not (Test-AppFile $registry)) { throw 'STOP: registry missing/not regular file' }
    # On this Android 11 TV, run-as test -r is a known false negative on
    # valid mode-660 XML; direct sha256sum proves real read access instead.
    return (Hash-App $registry)
}
function Assert-NoMarkersOrForeignBackup {
    if (Test-AppEntry $marker) { throw 'STOP: pending G1c registration marker' }
    if (Test-AppEntry $g1bMarker) { throw 'STOP: pending legacy G1b registration marker' }
    foreach ($name in $otherProtected) {
        if (Test-AppEntry $name) { throw 'STOP: another G1d test has protected backup/discard' }
    }
}
function Assert-Baseline {
    $null = Hash-Registry
    Assert-NoMarkersOrForeignBackup
    if ((Test-AppEntry $backup) -or (Test-AppEntry $discard)) {
        throw 'STOP: protected UX02 backup/discard already exists; do not restage'
    }
    if (-not (Test-AppFile $original)) { throw 'STOP: original external SRT missing' }
    Require-AppHash $original $expectedSrt
    Write-Host 'G1D_UX02_SRT_AND_REGISTRY_BASELINE_PASS'
}
function Assert-Staged {
    $null = Hash-Registry
    Assert-NoMarkersOrForeignBackup
    if (Test-AppEntry $discard) { throw 'STOP: UX02 discard exists unexpectedly' }
    if (-not (Test-AppFile $backup) -or -not (Test-AppFile $original)) {
        throw 'STOP: synthetic UTF8 file or protected original backup missing'
    }
    Require-AppHash $backup $expectedSrt
    Require-AppHash $original $fixtureSha
    Write-Host 'G1D_UX02_STAGED_FIXTURE_AND_BACKUP_SHA_PASS_NOT_TV_UX_PASS'
}
function Invoke-AdbCaptured([string[]]$Argv) {
    # Windows PowerShell 5.1 treats normal adb pull/push stderr progress as
    # NativeCommandError. Always validate the real native exit status.
    $priorPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $lines = @(& $adb @Argv 2>&1)
        $nativeExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $priorPreference
    }
    return @{ ExitCode = $nativeExit }
}
function Hash-InstalledApk {
    $lines = @(& $adb -s $serial shell pm path $pkg)
    if ($LASTEXITCODE -ne 0) { throw 'STOP: pm path failed' }
    $lines = @($lines | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^package:' })
    if ($lines.Count -ne 1) { throw 'STOP: installed APK is split/missing' }
    $m = [regex]::Match($lines[0], '^package:(/.+/base\.apk)$')
    if (-not $m.Success) { throw 'STOP: installed base.apk path differs' }
    $temp = Join-Path $env:TEMP ('g1d-ux02-installed-' + [Guid]::NewGuid().ToString('N') + '.apk')
    try {
        $pull = Invoke-AdbCaptured -Argv @('-s',$serial,'pull',$m.Groups[1].Value,$temp)
        if ($pull.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $temp -PathType Leaf)) {
            throw 'STOP: actual installed APK cannot be pulled read-only'
        }
        return (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLowerInvariant()
    } finally {
        if (Test-Path -LiteralPath $temp -PathType Leaf) {
            Remove-Item -LiteralPath $temp -Force
        }
    }
}
function Assert-InstalledPr29 {
    if ([string]::IsNullOrWhiteSpace($ApkPath) -or
        -not (Test-Path -LiteralPath $ApkPath -PathType Leaf)) {
        throw 'STOP: specify verified PR29 ARM32 APK using -ApkPath'
    }
    if ((Get-FileHash -LiteralPath $ApkPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedApk) {
        throw 'STOP: local UX debug APK SHA256 differs from pinned PR29'
    }
    if ((Hash-InstalledApk) -cne $expectedApk) {
        throw 'STOP: actual installed TV APK does not match PR29 ARM32 debug'
    }
    Write-Host 'G1D_UX02_EXACT_INSTALLED_APK_SHA_PASS'
}
function Remove-RemoteIfExact {
    if (-not (Test-RemoteEntry)) { return }
    if ((Hash-Remote) -cne $fixtureSha) {
        throw 'STOP: remote fixture path occupied by unknown bytes; never delete'
    }
    & $adb -s $serial shell rm $remoteFixture
    if ($LASTEXITCODE -ne 0 -or (Test-RemoteEntry)) {
        throw 'STOP: exact synthetic remote fixture cleanup failed'
    }
}
function Assert-NoRemoteFixture {
    if (Test-RemoteEntry) { throw 'STOP: remote synthetic fixture path already occupied' }
}

switch ($Phase) {
    'Preflight' {
        Assert-InstalledPr29
        Assert-Baseline
        Assert-NoRemoteFixture
        Write-Host 'G1D_UX02_PREFLIGHT_READ_ONLY_PASS'
    }
    'StageBadUtf8' {
        Assert-InstalledPr29
        Assert-Baseline
        Assert-NoRemoteFixture
        $registryBefore = Hash-Registry
        $approve = Read-Host 'CLOSE VLC PLAYER. Type STAGE G1D UX BAD UTF8 to stage only the synthetic SRT'
        if ($approve -cne 'STAGE G1D UX BAD UTF8') { throw 'STOP: UX02 staging not approved' }
        Assert-InstalledPr29
        Assert-Baseline
        Assert-NoRemoteFixture
        if ((Hash-Registry) -cne $registryBefore) {
            throw 'STOP: registry changed before staging'
        }
        $local = Join-Path $env:TEMP ('g1d-ux02-fixture-' + [Guid]::NewGuid().ToString('N') + '.bin')
        try {
            [IO.File]::WriteAllBytes($local,$fixtureBytes)
            if ((Get-FileHash -LiteralPath $local -Algorithm SHA256).Hash.ToLowerInvariant() -cne $fixtureSha) {
                throw 'STOP: local synthetic UTF8 fixture hash mismatch'
            }
            $push = Invoke-AdbCaptured -Argv @('-s',$serial,'push',$local,$remoteFixture)
            if ($push.ExitCode -ne 0) { throw 'STOP: adb push synthetic fixture failed; original SRT untouched' }
            if ((Hash-Remote) -cne $fixtureSha) {
                throw 'STOP: remote synthetic fixture hash mismatch; original untouched'
            }
            Assert-InstalledPr29
            Assert-Baseline
            if ((Hash-Registry) -cne $registryBefore) {
                throw 'STOP: registry changed before protected rename'
            }
            & $adb -s $serial shell run-as $pkg mv $original $backup
            if ($LASTEXITCODE -ne 0) { throw 'STOP: protecting original SRT failed; inspect before retry' }
            Require-AppHash $backup $expectedSrt
            & $adb -s $serial shell run-as $pkg cp $remoteFixture $original
            if ($LASTEXITCODE -ne 0) {
                throw 'STOP: copying synthetic SRT failed; preserve backup for Restore'
            }
            Assert-Staged
            if ((Hash-Registry) -cne $registryBefore) {
                throw 'STOP: registry changed during stage; preserve backup'
            }
        } finally {
            if (Test-Path -LiteralPath $local -PathType Leaf) {
                Remove-Item -LiteralPath $local -Force
            }
            Remove-RemoteIfExact
        }
        Write-Host 'G1D_UX02_STAGE_BAD_UTF8_PASS_NOT_TV_UX_PASS'
        Write-Host 'NEXT: fresh VLC load of registered A, saved G1c ON; check one nonblocking Vietnamese SRT warning; Restore immediately.'
    }
    'InspectBadUtf8' {
        Assert-InstalledPr29
        Assert-Staged
        Assert-NoRemoteFixture
        Write-Host 'G1D_UX02_INSPECT_READ_ONLY_PASS_NOT_TV_UX_PASS'
    }
    'Restore' {
        # Recovery never needs APK path, registry, or remote temp fixture.
        # If the fixture copy failed, original may be absent; backup survives.
        if (-not (Test-AppFile $backup)) { throw 'STOP: original SRT protected backup missing' }
        Require-AppHash $backup $expectedSrt
        if (Test-AppEntry $discard) { throw 'STOP: UX02 discard already occupied; no overwrite' }
        if (Test-AppEntry $original) {
            if (-not (Test-AppFile $original)) { throw 'STOP: SRT path not a regular file' }
            Require-AppHash $original $fixtureSha
        }
        $approve = Read-Host 'Type RESTORE G1D UX UTF8 to restore the exact original SRT'
        if ($approve -cne 'RESTORE G1D UX UTF8') { throw 'STOP: UX02 Restore not approved' }
        Require-AppHash $backup $expectedSrt
        if (Test-AppEntry $discard) { throw 'STOP: discard became occupied; preserve backup' }
        if (Test-AppEntry $original) {
            Require-AppHash $original $fixtureSha
            & $adb -s $serial shell run-as $pkg mv $original $discard
            if ($LASTEXITCODE -ne 0) { throw 'STOP: moving synthetic SRT to discard failed; backup safe' }
        }
        if (Test-AppEntry $original) { throw 'STOP: restore target remains occupied; backup safe' }
        & $adb -s $serial shell run-as $pkg mv $backup $original
        if ($LASTEXITCODE -ne 0) { throw 'STOP: restoring protected original failed; preserve backup' }
        Require-AppHash $original $expectedSrt
        if (Test-AppEntry $backup) { throw 'STOP: protected backup still exists after restore' }
        Write-Host 'G1D_UX02_ORIGINAL_SRT_RESTORED_HASH_PASS'
        if (Test-AppEntry $discard) {
            Require-AppHash $discard $fixtureSha
            & $adb -s $serial shell run-as $pkg rm $discard
            if ($LASTEXITCODE -ne 0 -or (Test-AppEntry $discard)) {
                throw 'STOP: restored SRT is intact but fixture discard cleanup failed'
            }
        }
        Remove-RemoteIfExact
        Write-Host 'G1D_UX02_RESTORE_AND_SYNTHETIC_CLEANUP_PASS'
    }
    'VerifyRestored' {
        Assert-InstalledPr29
        Assert-Baseline
        Assert-NoRemoteFixture
        Write-Host 'G1D_UX02_RESTORE_BASELINE_READ_ONLY_PASS_NOT_TV_UX_PASS'
    }
}
