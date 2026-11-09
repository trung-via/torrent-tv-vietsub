# Torrent TV / P2-AISUB R3.1 private source discovery.
# READ_ONLY: exact basename checks in the runner account's three standard folders.
# No recursive search, file extraction, private source text, subtitles, network
# requests, Gemini, ADB, process kill/restart or host configuration changes.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$expectedRepo = 'trung-via/torrent-tv-vietsub'
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne $expectedRepo -or
    $env:GITHUB_EVENT_NAME -cne 'issue_comment' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows') {
    throw 'R31_INVENTORY_STOP_WRONG_REPO_OR_RUNNER'
}
$runnerRoot = [IO.Path]::GetFullPath('C:\TOOL\TorrentTV-Runner\_work').TrimEnd('\') + '\'
if ([string]::IsNullOrWhiteSpace($env:GITHUB_WORKSPACE) -or
    -not ([IO.Path]::GetFullPath($env:GITHUB_WORKSPACE).TrimEnd('\') + '\').StartsWith(
        $runnerRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'R31_INVENTORY_STOP_WRONG_WORKSPACE'
}
$repoRoot = (Resolve-Path -LiteralPath $env:GITHUB_WORKSPACE).Path
$head = (& git -C $repoRoot rev-parse HEAD | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $head -notmatch '^[0-9a-f]{40}$') {
    throw 'R31_INVENTORY_STOP_UNPINNED_GIT'
}
$dirty = @(& git -C $repoRoot status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -gt 0) {
    throw 'R31_INVENTORY_STOP_DIRTY_GIT'
}
Write-Host 'R31_INVENTORY_TRUSTED_HOSTOPS_SOURCE_PASS'

$home = [Environment]::GetFolderPath('UserProfile')
if ([string]::IsNullOrWhiteSpace($home) -or
    -not [IO.Path]::IsPathRooted($home)) {
    throw 'R31_INVENTORY_STOP_NO_RUNNER_USER_PROFILE'
}

$folders = @('Downloads', 'Desktop', 'Documents')
$zipName = 'Torrent_TV_AISUB_R3_1_WorkLock_Telemetry.zip'
$scriptName = 'full_srt_trial_r3.py'
$zipHits = @()
$scriptHits = @()
foreach ($folder in $folders) {
    $parent = Join-Path $home $folder
    # Direct exact paths ONLY. No wildcard/directory listing and no recursion.
    $candidateZip = Join-Path $parent $zipName
    $candidateScript = Join-Path $parent $scriptName
    if (Test-Path -LiteralPath $candidateZip -PathType Leaf -ErrorAction SilentlyContinue) {
        $zipHits += $candidateZip
    }
    if (Test-Path -LiteralPath $candidateScript -PathType Leaf -ErrorAction SilentlyContinue) {
        $scriptHits += $candidateScript
    }
}
Write-Host 'R31_INVENTORY_SCOPE=RUNNER_ACCOUNT_STANDARD_FOLDERS_EXACT_NAMES_ONLY'
Write-Host 'R31_INVENTORY_NO_RECURSION_OR_PRIVATE_WORKDIR_TOUCH=PASS'

if ($zipHits.Count -gt 1 -or $scriptHits.Count -gt 1) {
    # Ambiguous copies must be reconciled by the Human outside public GitHub.
    Write-Host 'R31_PRIVATE_SOURCE=AMBIGUOUS_EXACT_LOCATION'
}
elseif ($zipHits.Count -eq 1) {
    $file = Get-Item -LiteralPath $zipHits[0] -ErrorAction Stop
    if ($file.Length -gt 20971520 -or $file.Length -eq 0) {
        Write-Host 'R31_PRIVATE_ZIP=UNEXPECTED_ARCHIVE_SIZE_NOT_OPENED'
    }
    else {
        try {
            Add-Type -AssemblyName System.IO.Compression
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $archive = [IO.Compression.ZipFile]::OpenRead($zipHits[0])
            try {
                # Central-directory entry names ONLY; no entry body read.
                $leafNames = @($archive.Entries | ForEach-Object {
                    ([string]$_.FullName).Replace('\','/').Split('/')[-1]
                })
                $required = @('full_srt_trial_r3.py','apply_r3_1.ps1','test_r3_1.py')
                $hasExpected = @($required | Where-Object { $leafNames -ccontains $_ }).Count -eq $required.Count
                $hasMedia = @($leafNames | Where-Object {
                    $_ -match '(?i)\.(srt|vtt|mkv|mp4|torrent)$'
                }).Count -gt 0
                if ($hasMedia) {
                    Write-Host 'R31_PRIVATE_ZIP=CONTAINS_MEDIA_NAMES_NO_CONTENT_READ'
                }
                elseif ($hasExpected) {
                    Write-Host 'R31_PRIVATE_ZIP=EXPECTED_R31_CODE_NAMES_PRESENT_NO_CONTENT_READ'
                }
                else {
                    Write-Host 'R31_PRIVATE_ZIP=ARCHIVE_PRESENT_EXPECTED_CODE_NAMES_MISSING'
                }
            }
            finally { $archive.Dispose() }
        }
        catch {
            # Do not print exception detail, which may embed a local path.
            Write-Host 'R31_PRIVATE_ZIP=OPEN_METADATA_FAILED'
        }
    }
}
elseif ($scriptHits.Count -eq 1) {
    Write-Host 'R31_PRIVATE_SCRIPT=EXACT_FILENAME_PRESENT_NOT_CONTENT_VERIFIED'
}
else {
    Write-Host 'R31_PRIVATE_SOURCE=NOT_FOUND_IN_CHECKED_LOCATIONS'
}
# Deliberately cannot infer user-wide absence from three limited locations.
Write-Host 'R31_PRIVATE_SOURCE_SHA=NOT_VERIFIED'
Write-Host 'R31_WORK_OWNER_OS_LOCK=NOT_OPENED'
Write-Host 'R31_CHECKPOINTS_AND_TRANSLATED_SRT=NOT_READ_OR_CHANGED'
Write-Host 'R31_PRIVATE_R32_INTEGRATION=NOT_RUN'
Write-Host 'R31_GEMINI_CALLS=ZERO'
Write-Host 'R31_RELEASE_APK_AND_REDMITV=NOT_TOUCHED'
Write-Host 'R31_READONLY_DISCOVERY_COMPLETE_NOT_INTEGRATION_PASS'
