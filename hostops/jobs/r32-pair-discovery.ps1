# Torrent TV Vietsub R3.2: exact-identity READ-ONLY EN+VI pair discovery on dedicated Windows.
# No recursion, whole-drive search, user-text printing, checkpoint write, model call or TV action.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:GITHUB_EVENT_NAME -cne 'issue_comment' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows') {
    throw 'R32_PAIR_STOP_WRONG_REPO_RUNNER_OR_EVENT'
}
$runnerRoot = [IO.Path]::GetFullPath('C:\TOOL\TorrentTV-Runner\_work').TrimEnd('\') + '\'
if ([string]::IsNullOrWhiteSpace($env:GITHUB_WORKSPACE)) {
    throw 'R32_PAIR_STOP_WORKSPACE_UNSET'
}
$workspace = [IO.Path]::GetFullPath($env:GITHUB_WORKSPACE).TrimEnd('\') + '\'
if (-not $workspace.StartsWith($runnerRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'R32_PAIR_STOP_WRONG_WORKSPACE'
}
$repoRoot = (Resolve-Path -LiteralPath $env:GITHUB_WORKSPACE).Path
$gitHead = (& git -C $repoRoot rev-parse HEAD | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $gitHead -notmatch '^[0-9a-f]{40}$') {
    throw 'R32_PAIR_STOP_GIT_NOT_PINNED'
}
# Confirm the source consumer and canonical cue parser match accepted main blobs.
foreach ($pin in @(
    @('poc/p2-aisub/r32_existing_vi_rehydrate.py', '0f8831560a9649ea6c146100e487e620b6d6f777'),
    @('poc/p2-aisub/cue_pipeline.py', '094ae47abb7a0ecafce372f2ba67a70e1092f7e6')
)) {
    $actualBlob = (& git -C $repoRoot hash-object -- $pin[0] | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $actualBlob -cne $pin[1]) {
        throw 'R32_PAIR_STOP_SOURCE_CONSUMER_BLOB_DRIFT'
    }
}
Write-Host 'R32_PAIR_TRUSTED_RUNNER_PINNED_CODE_PASS'

$profileRoot = [Environment]::GetFolderPath('UserProfile')
if ([string]::IsNullOrWhiteSpace($profileRoot)) {
    throw 'R32_PAIR_STOP_RUNNER_PROFILE_UNAVAILABLE'
}
# Only these bounded, known locations. No recursion, no broad drive scans.
$folders = @(
    (Join-Path $repoRoot 'subtitle-artifacts'),
    'C:\TOOL\TorrentTV-Runner\subtitle-artifacts',
    (Join-Path $profileRoot 'Downloads'),
    (Join-Path $profileRoot 'Documents'),
    (Join-Path $profileRoot 'Desktop'),
    (Join-Path $profileRoot 'Downloads\subtitle-artifacts'),
    (Join-Path $profileRoot 'Documents\Torrent TV Vietsub'),
    (Join-Path $profileRoot 'Downloads\Torrent TV Vietsub'),
    (Join-Path $profileRoot 'Desktop\Torrent TV Vietsub')
)
# Anchors were already documented in GitHub Issue #88 (EN) / #96 (VI).
$expectedSource = '76b857688ed6ab1f279190d23c54e3d5697eb91870178637342fd0874996ea8a'
$expectedVI = '3d9d4bf37fe31eb5de8a7af32d68c21fb5a342b87778f6f7925a7b43ad26c15b'
$matches = @{ EN = @(); VI = @() }
$sizeCandidates = 0
$presentFolders = 0
$seen = New-Object 'System.Collections.Generic.HashSet[string]'

foreach ($folder in $folders) {
    if (-not $seen.Add([IO.Path]::GetFullPath($folder))) { continue }
    if (-not (Test-Path -LiteralPath $folder -PathType Container -ErrorAction SilentlyContinue)) { continue }
    $dir = Get-Item -LiteralPath $folder -ErrorAction Stop
    if (($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
    $presentFolders++
    try {
        $entries = @(Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction Stop)
    }
    catch {
        throw 'R32_PAIR_STOP_SCOPED_FOLDER_NOT_READABLE'
    }
    if ($entries.Count -gt 250) {
        Write-Host 'R32_PAIR_FOLDER_ENTRY_CAP_REACHED'
        continue
    }
    foreach ($entry in $entries) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        $kind = ''
        if ($entry.Length -eq 120111) { $kind = 'EN' }
        elseif ($entry.Length -eq 123768) { $kind = 'VI' }
        else { continue }
        if ($entry.Extension -notin @('.srt', '.vtt')) { continue }
        $sizeCandidates++
        if ($sizeCandidates -gt 30) { throw 'R32_PAIR_STOP_TOO_MANY_SAME_SIZE_CANDIDATES' }
        try {
            $sha = (Get-FileHash -LiteralPath $entry.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        }
        catch {
            throw 'R32_PAIR_STOP_CANNOT_HASH_CANDIDATE'
        }
        if ($kind -eq 'EN' -and $sha -ceq $expectedSource) { $matches.EN += $entry.FullName }
        if ($kind -eq 'VI' -and $sha -ceq $expectedVI) { $matches.VI += $entry.FullName }
    }
}
Write-Host 'R32_PAIR_SEARCH_SCOPE=DEDICATED_RUNNER_ACCOUNT_NINE_NAMED_FOLDERS_NONRECURSIVE'
Write-Host ('R32_PAIR_SCOPED_FOLDERS_PRESENT=' + $presentFolders)
Write-Host ('R32_PAIR_SIZE_CANDIDATES=' + $sizeCandidates)
Write-Host ('R32_PAIR_EN_EXACT_SHA_MATCH=' + [int]($matches.EN.Count -gt 0))
Write-Host ('R32_PAIR_VI_EXACT_SHA_MATCH=' + [int]($matches.VI.Count -gt 0))
Write-Host 'R32_PAIR_NO_PRIVATE_FILENAMES_OR_DIALOGUE_PRINTED=TRUE'

if ($matches.EN.Count -gt 0 -and $matches.VI.Count -gt 0) {
    $python = Get-Command python -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $python) {
        Write-Host 'R32_PAIR_REAL_QA=PYTHON_UNAVAILABLE'
    }
    else {
        $consumer = Join-Path $repoRoot 'poc\p2-aisub\r32_existing_vi_rehydrate.py'
        $env:PYTHONDONTWRITEBYTECODE = '1'
        $resultRaw = @(& $python.Source -B $consumer --source ($matches.EN[0]) --translated ($matches.VI[0]) 2>$null)
        $exitCode = $LASTEXITCODE
        try {
            $data = ($resultRaw -join [Environment]::NewLine) | ConvertFrom-Json -ErrorAction Stop
            if ($exitCode -eq 0 -and
                $data.status -ceq 'EXISTING_VI_TIMING_PARITY_PASS_MEANING_UNVERIFIED' -and
                $data.cue_count -eq 1761 -and
                $data.batch_count -eq 20 -and
                $data.timecode_parity -ceq 'PASS' -and
                $data.source_sha256 -ceq $expectedSource -and
                $data.existing_vi_sha256 -ceq $expectedVI -and
                $data.provider_calls -eq 0) {
                Write-Host 'R32_PAIR_REAL_QA=STRUCTURAL_PASS_MEANING_NOT_REVIEWED'
                Write-Host 'R32_PAIR_REAL_CUE_COUNT=1761'
                Write-Host 'R32_PAIR_NEW_CACHE=NOT_CREATED'
            }
            else {
                Write-Host 'R32_PAIR_REAL_QA=FAIL_OR_DIFFERENT_SUBTITLE_FORMAT'
            }
        }
        catch {
            Write-Host 'R32_PAIR_REAL_QA=SANITIZED_RESPONSE_OR_EXECUTION_ERROR'
        }
    }
}
else {
    Write-Host 'R32_PAIR_REAL_QA=NOT_RUN_EXACT_PAIR_NOT_FOUND_IN_SCOPE'
}
Write-Host 'R32_PAIR_MISSING_IN_SCOPE_DOES_NOT_PROVE_ABSENT_ON_WINDOWS=TRUE'
Write-Host 'R32_PAIR_LEGACY_CHECKPOINTS=NOT_READ_OR_CHANGED'
Write-Host 'R32_PAIR_GEMINI_CALLS=ZERO'
Write-Host 'R32_PAIR_WIN_FILE_WRITES=NONE_FROM_THIS_SCRIPT'
Write-Host 'R32_PAIR_TV_RELEASE_ACTIONS=NONE'
Write-Host 'R32_PAIR_READONLY_DISCOVERY_COMPLETE_NOT_FULL_SEMANTIC_PASS'
