# P2-AISUB / Thor v0.3.5: owner-approved PRIVATE LOCAL -> Redmi SRT transfer.
# Never copy subtitle text/bytes to GitHub, Actions artifacts, public URLs or logs.
# Fail closed unless an exact SHA256 byte match is already on this Windows machine.
# Only writes a single dedicated file in the TV's public Downloads folder. No APK install, no playback.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Write-Host 'THOR_TRANSFER_BEGIN'
Write-Host 'THOR_TRANSFER_EXPECTED_CUES=1761'
Write-Host 'THOR_TRANSFER_SOURCE_BYTES_EXPECTED=123768'
if ($env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or $env:RUNNER_OS -cne 'Windows') {
    throw 'THOR_TRANSFER_BLOCKED_UNEXPECTED_RUNNER'
}
$expected = '3d9d4bf37fe31eb5de8a7af32d68c21fb5a342b87778f6f7925a7b43ad26c15b'
$target = '/sdcard/Download/TTV-Thor-v035.vi.srt'
$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
$folders = @()
$home = [Environment]::GetFolderPath('UserProfile')
foreach ($sub in @('Downloads','Desktop','Documents')) {
    $folders += (Join-Path $home $sub)
}
$folders += 'C:\Users\Public\Downloads'
$folders += 'C:\TOOL\TorrentTV-Runner\transfer-inbox'
$profileRoot = 'C:\Users'
if (Test-Path -LiteralPath $profileRoot -PathType Container) {
    $profiles = @(Get-ChildItem -LiteralPath $profileRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @('Public','Default','Default User','All Users') })
    if ($profiles.Count -le 15) {
        foreach ($profile in $profiles) {
            $folders += (Join-Path $profile.FullName 'Downloads')
        }
    }
}
$folders = @($folders | Select-Object -Unique)
$candidates = @()
foreach ($folder in $folders) {
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
    $folderInfo = Get-Item -LiteralPath $folder -Force -ErrorAction SilentlyContinue
    if ($null -eq $folderInfo -or ($folderInfo.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
    $files = @(Get-ChildItem -LiteralPath $folder -File -Filter 'Thor*.srt' -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -eq 123768 -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })
    foreach ($file in $files) {
        $candidates += $file
    }
}
Write-Host ('THOR_TRANSFER_CANDIDATE_COUNT=' + $candidates.Count)
if ($candidates.Count -gt 60) {
    Write-Host 'THOR_TRANSFER_STATUS=BLOCKED_TOO_MANY_CANDIDATES'
    exit 0
}
$matches = @()
foreach ($file in $candidates) {
    try {
        $sha = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        if ($sha -ceq $expected) { $matches += $file.FullName }
    } catch {
        # Never log a local path or the exception content.
        Write-Host 'THOR_TRANSFER_SOURCE_CANDIDATE_READ_ERROR_REDACTED'
    }
}
Write-Host ('THOR_TRANSFER_VERIFIED_LOCAL_COPIES=' + $matches.Count)
if ($matches.Count -eq 0) {
    Write-Host 'THOR_TRANSFER_STATUS=SOURCE_NOT_PRESENT_ON_WINDOWS'
    Write-Host 'THOR_TRANSFER_TV_WRITE=NOT_ATTEMPTED'
    exit 0
}
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    Write-Host 'THOR_TRANSFER_STATUS=ADB_NOT_FOUND'
    exit 0
}
try {
    $devices = @(& $adb devices -l 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'ADB_LIST_FAILED' }
    $ready = @()
    foreach ($line in $devices) {
        if ($line -match '^\s*(\S+)\s+device(?:\s|$)') { $ready += $Matches[1] }
    }
    Write-Host ('THOR_TRANSFER_AUTHORIZED_DEVICE_COUNT=' + $ready.Count)
    if ($ready.Count -ne 1) { Write-Host 'THOR_TRANSFER_STATUS=DEVICE_AMBIGUOUS'; exit 0 }
    $serial = [string]$ready[0]
    $model = @(& $adb -s $serial shell getprop ro.product.model 2>$null)
    if ($LASTEXITCODE -ne 0 -or @($model).Count -ne 1 -or ([string]$model[0]).Trim() -cne 'MiTV-ASTR0') {
        Write-Host 'THOR_TRANSFER_STATUS=NOT_AUTHORIZED_REDMITV'
        exit 0
    }
    # Preserve prior file: only allow idempotent no-op if exact bytes are already there.
    $remoteCheck = @(& $adb -s $serial shell sha256sum $target 2>$null)
    if ($LASTEXITCODE -eq 0 -and $remoteCheck.Count -ge 1) {
        if (([string]$remoteCheck[0]).Trim() -match '^([a-fA-F0-9]{64})\s+') {
            if ($Matches[1].ToLowerInvariant() -ceq $expected) {
                Write-Host 'THOR_TRANSFER_STATUS=ALREADY_PRESENT_SHA_VERIFIED'
                Write-Host 'THOR_TRANSFER_ON_TV_SHA_MATCH=TRUE'
                exit 0
            }
        }
        Write-Host 'THOR_TRANSFER_STATUS=BLOCKED_EXISTING_TARGET_HASH_DIFFERENT'
        exit 0
    }
    # The file is an exact SHA-verified local user copy, never GitHub workflow content.
    $source = [string]$matches[0]
    & $adb -s $serial push $source $target 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Host 'THOR_TRANSFER_STATUS=ADB_PUSH_FAILED'; exit 0 }
    $remote = @(& $adb -s $serial shell sha256sum $target 2>$null)
    if ($LASTEXITCODE -ne 0 -or $remote.Count -ne 1) { Write-Host 'THOR_TRANSFER_STATUS=REMOTE_SHA_UNREADABLE'; exit 0 }
    if (([string]$remote[0]).Trim() -notmatch '^([a-fA-F0-9]{64})\s+') {
        Write-Host 'THOR_TRANSFER_STATUS=REMOTE_SHA_FORMAT_UNEXPECTED'
        exit 0
    }
    if ($Matches[1].ToLowerInvariant() -cne $expected) {
        Write-Host 'THOR_TRANSFER_STATUS=REMOTE_HASH_MISMATCH'
        exit 0
    }
    Write-Host 'THOR_TRANSFER_STATUS=ADB_PUSH_SHA_VERIFIED'
    Write-Host 'THOR_TRANSFER_ON_TV_SHA_MATCH=TRUE'
    Write-Host 'THOR_TRANSFER_OMP_IMPORT_AND_RENDER=NOT_RUN'
    Write-Host 'THOR_TRANSFER_SEEK_RESUME=NOT_RUN'
} catch {
    Write-Host 'THOR_TRANSFER_STATUS=ADB_EXCEPTION_REDACTED'
}
Write-Host 'THOR_TRANSFER_PRIVATE_CONTENT_NOT_PUBLISHED=TRUE'
Write-Host 'THOR_TRANSFER_END'
exit 0
