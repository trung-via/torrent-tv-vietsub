# G1d UX-01: missing saved external SRT on exact PR29 ARM32 debug build.
# Human-run ONLY; stage/restore one app-private SRT; no install/clear/network changes.
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
$expectedApk = '8f4df47952d00d75bb6234a7620c4fc41e26995fab263d8d2db60292bc94fd85'
$otherProtected = @(
    'files/p1-g1-external.vi.srt.g1d-utf8-backup',
    'files/p1-g1-external.vi.srt.g1d-utf8-discard',
    'files/p1-g1-external.vi.srt.g1d-syntax-backup',
    'files/p1-g1-external.vi.srt.g1d-syntax-discard',
    'files/p1-g1-external.vi.srt.g1d-changed-backup',
    'files/p1-g1-external.vi.srt.g1d-changed-discard',
    'files/p1-g1-external.vi.srt.g1d-perm-backup',
    'files/p1-g1-external.vi.srt.g1d-perm-discard'
)
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    throw 'STOP: dedicated Windows adb.exe missing'
}
$devices = @(& $adb devices -l)
if ($LASTEXITCODE -ne 0) { throw 'STOP: adb devices failed' }
$connected = @($devices | Where-Object { $_ -match '^\s*\S+\s+(device|offline|unauthorized)\b' })
if ($connected.Count -ne 1) { throw 'STOP: expected exactly one ADB device entry' }
$match = [regex]::Match($connected[0], '^\s*(\S+)\s+device\b')
if (-not $match.Success) { throw 'STOP: ADB device unauthorized/offline' }
$serial = $match.Groups[1].Value
$model = (& $adb -s $serial shell getprop ro.product.model | Out-String).Trim()
$api = (& $adb -s $serial shell getprop ro.build.version.sdk | Out-String).Trim()
$abi = (& $adb -s $serial shell getprop ro.product.cpu.abi | Out-String).Trim()
if ($model -cne 'MiTV-ASTR0' -or $api -cne '30' -or $abi -cne 'armeabi-v7a') {
    throw 'STOP: wrong Redmi TV model/API/ABI'
}
Write-Host 'G1D_UX01_REDMI_ARM32_DEVICE_PASS'

function Test-AppEntry([string]$name) {
    & $adb -s $serial shell run-as $pkg test -e $name
    if ($LASTEXITCODE -eq 0) { return $true }
    if ($LASTEXITCODE -eq 1) { return $false }
    throw 'STOP: app-private entry check failed'
}
function Test-AppFile([string]$name) {
    & $adb -s $serial shell run-as $pkg test -f $name
    if ($LASTEXITCODE -eq 0) { return $true }
    if ($LASTEXITCODE -eq 1) { return $false }
    throw 'STOP: app-private file check failed'
}
function Hash-App([string]$name) {
    $output = @(& $adb -s $serial shell run-as $pkg sha256sum $name)
    if ($LASTEXITCODE -ne 0) { throw 'STOP: app-private hash/read failed' }
    $m = [regex]::Match(($output | Out-String).Trim(), '^([a-fA-F0-9]{64})\s+')
    if (-not $m.Success) { throw 'STOP: app-private hash invalid' }
    return $m.Groups[1].Value.ToLowerInvariant()
}
function Assert-SrtHash([string]$name) {
    if ((Hash-App $name) -cne $expectedSrt) { throw 'STOP: original SRT hash mismatch' }
}
function Hash-Registry {
    if (-not (Test-AppFile $registry)) { throw 'STOP: registry missing/not regular' }
    # On this Redmi run-as test -r returned 1, but a direct sha256sum read
    # succeeds for the valid UID-owned mode-660 G1c XML.
    return (Hash-App $registry)
}
function Assert-NoMarkers {
    if (Test-AppEntry $marker) { throw 'STOP: G1c registration marker is present' }
    if (Test-AppEntry $g1bMarker) { throw 'STOP: legacy G1b marker is present' }
}
function Assert-Baseline {
    $null = Hash-Registry
    Assert-NoMarkers
    if (Test-AppEntry $backup) { throw 'STOP: G1d missing-SRT protected backup already exists' }
    foreach ($name in $otherProtected) {
        if (Test-AppEntry $name) { throw 'STOP: protected backup from another G1d test exists' }
    }
    if (-not (Test-AppFile $original)) { throw 'STOP: original SRT missing' }
    Assert-SrtHash $original
    Write-Host 'G1D_UX01_SRT_AND_REGISTRY_BASELINE_PASS'
}
function Assert-Staged {
    $null = Hash-Registry
    Assert-NoMarkers
    if (Test-AppEntry $original) { throw 'STOP: SRT path unexpectedly occupied' }
    if (-not (Test-AppFile $backup)) { throw 'STOP: protected SRT backup missing' }
    Assert-SrtHash $backup
    Write-Host 'G1D_UX01_MISSING_STAGED_BACKUP_SHA_PASS_NOT_TV_UX_PASS'
}
# adb pull writes successful progress to stderr in Windows PowerShell 5.1.
# Only capture native stderr within a scoped Continue; verify exit and SHA.
function Invoke-AdbPull([string]$remote,[string]$destination) {
    $prior = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $lines = @(& $adb -s $serial pull $remote $destination 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prior
    }
    if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        throw 'STOP: cannot pull installed APK'
    }
}
function Hash-InstalledApk {
    $lines = @(& $adb -s $serial shell pm path $pkg)
    if ($LASTEXITCODE -ne 0) { throw 'STOP: pm path failed' }
    $lines = @($lines | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^package:' })
    if ($lines.Count -ne 1) { throw 'STOP: unexpected split APK or missing package' }
    $m = [regex]::Match($lines[0], '^package:(/.+/base\.apk)$')
    if (-not $m.Success) { throw 'STOP: unexpected base.apk path layout' }
    $temp = Join-Path $env:TEMP ('g1d-ux01-installed-' + [Guid]::NewGuid().ToString('N') + '.apk')
    try {
        Invoke-AdbPull $m.Groups[1].Value $temp
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
        throw 'STOP: -ApkPath must reference verified PR29 ARM32 debug APK'
    }
    $local = (Get-FileHash -LiteralPath $ApkPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($local -cne $expectedApk) { throw 'STOP: local PR29 ARM32 APK SHA256 mismatch' }
    if ((Hash-InstalledApk) -cne $expectedApk) {
        throw 'STOP: actual installed APK SHA256 is not PR29 ARM32 debug'
    }
    Write-Host 'G1D_UX01_EXACT_INSTALLED_APK_SHA_PASS'
}

switch ($Phase) {
    'Preflight' {
        Assert-InstalledPr29
        Assert-Baseline
        Write-Host 'G1D_UX01_PREFLIGHT_READ_ONLY_PASS'
    }
    'StageMissing' {
        Assert-InstalledPr29
        Assert-Baseline
        $registryBefore = Hash-Registry
        $approval = Read-Host 'CLOSE VLC PLAYER. Type STAGE G1D UX MISSING to rename only saved SRT'
        if ($approval -cne 'STAGE G1D UX MISSING') { throw 'STOP: staging not approved' }
        Assert-InstalledPr29
        Assert-Baseline
        if ((Hash-Registry) -cne $registryBefore) { throw 'STOP: registry changed before stage' }
        & $adb -s $serial shell run-as $pkg mv $original $backup
        if ($LASTEXITCODE -ne 0) { throw 'STOP: SRT move failed; inspect before any retry' }
        # On a post-stage STOP, keep the verified protected backup for Restore.
        Assert-Staged
        if ((Hash-Registry) -cne $registryBefore) {
            throw 'STOP: registry changed after stage; preserve backup for Restore'
        }
        Write-Host 'G1D_UX01_STAGE_MISSING_PASS_NOT_TV_UX_PASS'
        Write-Host 'NEXT: open registered A (saved ON) in a fresh VLC session; expect one nonblocking Vietnamese SRT warning. Then Restore.'
    }
    'ObserveMissing' {
        Assert-InstalledPr29
        Assert-Staged
        Write-Host 'G1D_UX01_OBSERVE_READ_ONLY_PASS_NOT_TV_UX_PASS'
        Write-Host 'Human: warning shown once, G1c track absent, AV/seek/remote stable, no private text leaked? Then Restore.'
    }
    'Restore' {
        # Recovery MUST NOT depend on APK path, registry availability or ON state.
        if (Test-AppEntry $original) {
            throw 'STOP: original SRT path occupied; never overwrite'
        }
        if (-not (Test-AppFile $backup)) { throw 'STOP: protected backup not found' }
        Assert-SrtHash $backup
        $approval = Read-Host 'Type RESTORE G1D UX SRT to restore protected original file'
        if ($approval -cne 'RESTORE G1D UX SRT') { throw 'STOP: Restore not approved' }
        if (Test-AppEntry $original) { throw 'STOP: original target became occupied' }
        Assert-SrtHash $backup
        & $adb -s $serial shell run-as $pkg mv $backup $original
        if ($LASTEXITCODE -ne 0) { throw 'STOP: Restore failed; preserve backup' }
        Assert-SrtHash $original
        if (Test-AppEntry $backup) { throw 'STOP: backup remains after Restore' }
        Write-Host 'G1D_UX01_ORIGINAL_SRT_RESTORED_HASH_PASS'
    }
    'VerifyRestored' {
        Assert-InstalledPr29
        Assert-Baseline
        Write-Host 'G1D_UX01_RESTORE_BASELINE_READ_ONLY_PASS_NOT_TV_UX_PASS'
    }
}
