# P2-AISUB real completed VI SRT: read-only QA + tiny same-folder source candidates.
# Requires exact historical VI SHA. Never emits captions, file paths or model data.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:GITHUB_EVENT_NAME -cne 'issue_comment' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows') {
    throw 'R32_VI_QA_STOP_WRONG_HOST_OR_EVENT'
}
$runnerRoot = [IO.Path]::GetFullPath('C:\TOOL\TorrentTV-Runner\_work').TrimEnd('\') + '\'
if ([string]::IsNullOrWhiteSpace($env:GITHUB_WORKSPACE) -or
    -not ([IO.Path]::GetFullPath($env:GITHUB_WORKSPACE).TrimEnd('\') + '\').StartsWith(
        $runnerRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'R32_VI_QA_STOP_WRONG_WORKSPACE'
}
$repoRoot = (Resolve-Path -LiteralPath $env:GITHUB_WORKSPACE).Path
foreach ($pin in @(
    @('poc/p2-aisub/cue_pipeline.py','094ae47abb7a0ecafce372f2ba67a70e1092f7e6'),
    @('poc/p2-aisub/subtitle_quality.py','75e1ef223b72f646b35a6f7784faa1a2d5be69fe'),
    @('poc/p2-aisub/full_srt_pair_qa.py','45c7104585634ac834691542ebcd68a5e2c80a83')
)) {
    $blob = (& git -C $repoRoot hash-object -- $pin[0] | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $blob -cne $pin[1]) {
        throw 'R32_VI_QA_STOP_PINNED_CODE_DRIFT'
    }
}
Write-Host 'R32_VI_QA_TRUSTED_CODE_AND_RUNNER_PASS'

$profileRoot = [Environment]::GetFolderPath('UserProfile')
if ([string]::IsNullOrWhiteSpace($profileRoot)) {
    throw 'R32_VI_QA_STOP_PROFILE_UNAVAILABLE'
}
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
$seen = New-Object 'System.Collections.Generic.HashSet[string]'
$expectedVI = '3d9d4bf37fe31eb5de8a7af32d68c21fb5a342b87778f6f7925a7b43ad26c15b'
$expectedEN = '76b857688ed6ab1f279190d23c54e3d5697eb91870178637342fd0874996ea8a'
$viPaths = @()
foreach ($folder in $folders) {
    if (-not $seen.Add([IO.Path]::GetFullPath($folder))) { continue }
    if (-not (Test-Path -LiteralPath $folder -PathType Container -ErrorAction SilentlyContinue)) { continue }
    try {
        $dir = Get-Item -LiteralPath $folder -ErrorAction Stop
        if (($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        $entries = @(Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction Stop)
        if ($entries.Count -gt 250) { continue }
        foreach ($entry in $entries) {
            if ($entry.Length -ne 123768 -or
                $entry.Extension -notin @('.srt','.vtt') -or
                ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                continue
            }
            $sha = (Get-FileHash -LiteralPath $entry.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
            if ($sha -ceq $expectedVI) { $viPaths += $entry.FullName }
        }
    }
    catch {
        throw 'R32_VI_QA_STOP_SCOPED_READ_ERROR'
    }
}
Write-Host ('R32_VI_EXACT_SHA_FOUND=' + [int]($viPaths.Count -gt 0))
if ($viPaths.Count -eq 0) {
    Write-Host 'R32_VI_READONLY_QA=NOT_RUN_VI_NOT_FOUND'
    Write-Host 'R32_VI_SOURCE_SIBLING_PROBE=NOT_RUN'
}
else {
    $py = Get-Command python -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $py) {
        Write-Host 'R32_VI_READONLY_QA=PYTHON_UNAVAILABLE'
        Write-Host 'R32_VI_SOURCE_SIBLING_PROBE=NOT_RUN'
    }
    else {
        $env:PYTHONDONTWRITEBYTECODE = '1'
        $quality = Join-Path $repoRoot 'poc\p2-aisub\subtitle_quality.py'
        $qaRaw = @(& $py.Source -B $quality --input ($viPaths[0]) --profile adult 2>$null)
        $qaExit = $LASTEXITCODE
        try {
            $qa = ($qaRaw -join [Environment]::NewLine) | ConvertFrom-Json -ErrorAction Stop
            if ($qaExit -ne 0 -or $qa.total_cues -ne 1761 -or
                $qa.human_semantic_review -cne 'REQUIRED' -or
                $qa.flagged_cues -lt 0) {
                Write-Host 'R32_VI_READONLY_QA=INVALID_OR_COUNT_MISMATCH'
            }
            else {
                Write-Host 'R32_VI_READONLY_QA=STRUCTURAL_PASS_MEANING_UNVERIFIED'
                Write-Host 'R32_VI_REAL_CUE_COUNT=1761'
                Write-Host ('R32_VI_READABILITY_WARNING_COUNT=' + [int]$qa.flagged_cues)
                Write-Host 'R32_VI_SEMANTIC_ACCEPTANCE=NOT_RUN'
            }
        }
        catch {
            Write-Host 'R32_VI_READONLY_QA=SANITIZED_ERROR'
        }

        # Look only for plausible EN subtitle names immediately beside matched VI,
        # no recursion or unrelated personal-file traversal.
        $folder = Split-Path -Parent $viPaths[0]
        try {
            $siblings = @(Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction Stop)
        }
        catch {
            throw 'R32_VI_QA_STOP_SIBLING_FOLDER_NOT_READABLE'
        }
        $count = 0
        $structuralMatches = 0
        $exactIdentity = 0
        if ($siblings.Count -le 120) {
            $pairQA = Join-Path $repoRoot 'poc\p2-aisub\full_srt_pair_qa.py'
            foreach ($entry in $siblings) {
                if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                    $entry.Extension -notin @('.srt','.vtt') -or
                    $entry.Length -lt 80000 -or $entry.Length -gt 200000 -or
                    $entry.FullName -ceq $viPaths[0] -or
                    $entry.Name -notmatch '(?i)(thor|ragnarok|\.en\.|english|source)') {
                    continue
                }
                $count++
                if ($count -gt 12) { throw 'R32_VI_QA_STOP_TOO_MANY_NAMED_SIBLINGS' }
                $raw = @(& $py.Source -B $pairQA --source $entry.FullName --translated ($viPaths[0]) 2>$null)
                if ($LASTEXITCODE -ne 0) { continue }
                try {
                    $pair = ($raw -join [Environment]::NewLine) | ConvertFrom-Json -ErrorAction Stop
                    if ($pair.status -ceq 'STRUCTURE_PASS_TRANSLATION_UNVERIFIED' -and
                        $pair.cue_count -eq 1761 -and
                        $pair.cue_timestamp_parity -ceq 'PASS') {
                        $structuralMatches++
                        if ($pair.source_sha256 -ceq $expectedEN) { $exactIdentity++ }
                    }
                }
                catch {
                    # Exclude candidate without leaking exception or private content.
                }
            }
        }
        Write-Host 'R32_VI_SOURCE_SIBLING_PROBE=BOUNDED_EXACT_PARENT_ONLY'
        Write-Host ('R32_VI_SOURCE_SIBLING_CANDIDATES=' + $count)
        Write-Host ('R32_VI_SOURCE_SIBLING_STRUCTURAL_PARITY=' + $structuralMatches)
        Write-Host ('R32_VI_SOURCE_SIBLING_EXACT_EN_SHA=' + [int]($exactIdentity -gt 0))
    }
}
Write-Host 'R32_VI_QA_NO_PRIVATE_PATH_OR_DIALOGUE_PRINTED=TRUE'
Write-Host 'R32_VI_QA_NO_USER_FILE_WRITES_OR_CHECKPOINT_TOUCH=TRUE'
Write-Host 'R32_VI_QA_PROVIDER_CALLS=ZERO'
Write-Host 'R32_VI_QA_TV_APK_ACTIONS=NONE'
Write-Host 'R32_VI_READONLY_REVIEW_DONE_NOT_EN_VI_OR_SEMANTIC_CERTIFICATION'
