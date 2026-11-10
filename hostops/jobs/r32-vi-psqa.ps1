# Torrent TV P2-AISUB: PowerShell-only read-only real VI SRT timeline audit.
# Avoid Python in runner account PATH, no cloud/model, file writes or private text output.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:GITHUB_EVENT_NAME -cne 'issue_comment' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows') {
    throw 'R32_VI_PS_STOP_WRONG_HOST_OR_EVENT'
}
$allowedRoot = [IO.Path]::GetFullPath('C:\TOOL\TorrentTV-Runner\_work').TrimEnd('\') + '\'
if ([string]::IsNullOrWhiteSpace($env:GITHUB_WORKSPACE) -or
    -not ([IO.Path]::GetFullPath($env:GITHUB_WORKSPACE).TrimEnd('\') + '\').StartsWith(
        $allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'R32_VI_PS_STOP_WRONG_WORKSPACE'
}
$repoRoot = (Resolve-Path -LiteralPath $env:GITHUB_WORKSPACE).Path
$head = (& git -C $repoRoot rev-parse HEAD | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $head -notmatch '^[0-9a-f]{40}$') {
    throw 'R32_VI_PS_STOP_GIT_NOT_PINNED'
}
Write-Host 'R32_VI_PS_DEDICATED_RUNNER_AND_GIT_PASS'

function TimestampMs([string]$hh, [string]$mm, [string]$ss, [string]$ms) {
    $h = [int]$hh
    $m = [int]$mm
    $s = [int]$ss
    if ($m -gt 59 -or $s -gt 59) { throw 'R32_VI_PS_INVALID_TIME_RANGE' }
    return ((($h * 60 + $m) * 60 + $s) * 1000 + [int]$ms)
}
function InspectSrt([string]$path) {
    # Reads only caller-selected private .srt, never logs text/path/filename.
    $info = Get-Item -LiteralPath $path -ErrorAction Stop
    if ($info.Extension -ne '.srt' -or $info.Length -gt 200000 -or
        $info.Length -lt 80000 -or
        ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'R32_VI_PS_INPUT_NOT_SCOPED_SRT'
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $content = $utf8.GetString([IO.File]::ReadAllBytes($path))
    if ($content.Length -gt 0 -and $content[0] -eq [char]0xFEFF) {
        $content = $content.Substring(1)
    }
    $cr = [string][char]13
    $nl = [string][char]10
    $content = $content.Replace($cr+$nl,$nl).Replace($cr,$nl).Trim([char]10)
    $blocks = @([regex]::Split($content, '\n[ \t]*\n+'))
    if ($blocks.Count -lt 1 -or $blocks.Count -gt 2000) {
        throw 'R32_VI_PS_INVALID_BLOCK_COUNT'
    }
    $starts = New-Object 'System.Collections.Generic.List[long]'
    $ends = New-Object 'System.Collections.Generic.List[long]'
    $before = [long]-1
    $index = 0
    $timePattern = '^(\d{2}):(\d{2}):(\d{2}),(\d{3}) --> (\d{2}):(\d{2}):(\d{2}),(\d{3})$'
    foreach ($block in $blocks) {
        $index++
        $lines = @([regex]::Split($block,'\n'))
        if ($lines.Count -lt 3 -or $lines[0] -cne [string]$index) {
            throw 'R32_VI_PS_CUE_SEQUENCE_INVALID'
        }
        $m = [regex]::Match($lines[1],$timePattern)
        if (-not $m.Success) { throw 'R32_VI_PS_CUE_TIMING_MALFORMED' }
        $start = TimestampMs $m.Groups[1].Value $m.Groups[2].Value $m.Groups[3].Value $m.Groups[4].Value
        $end = TimestampMs $m.Groups[5].Value $m.Groups[6].Value $m.Groups[7].Value $m.Groups[8].Value
        if ($end -le $start -or $start -lt $before) {
            throw 'R32_VI_PS_CUE_TIME_ORDER_INVALID'
        }
        if ([string]::IsNullOrWhiteSpace(($lines[2..($lines.Count-1)] -join $nl))) {
            throw 'R32_VI_PS_EMPTY_CUE'
        }
        $starts.Add([long]$start)
        $ends.Add([long]$end)
        $before = [long]$start
    }
    return @{
        Count = $index
        Starts = $starts.ToArray()
        Ends = $ends.ToArray()
        NFC = [string]::Equals($content,$content.Normalize([Text.NormalizationForm]::FormC),[StringComparison]::Ordinal)
        ReplacementCharCount = [regex]::Matches($content,[string][char]0xFFFD).Count
    }
}

$profileRoot = [Environment]::GetFolderPath('UserProfile')
if ([string]::IsNullOrWhiteSpace($profileRoot)) { throw 'R32_VI_PS_PROFILE_NOT_AVAILABLE' }
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
$expectedVI = '3d9d4bf37fe31eb5de8a7af32d68c21fb5a342b87778f6f7925a7b43ad26c15b'
$expectedEN = '76b857688ed6ab1f279190d23c54e3d5697eb91870178637342fd0874996ea8a'
$foundVI = @()
$seen = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($folder in $folders) {
    if (-not $seen.Add([IO.Path]::GetFullPath($folder))) { continue }
    if (-not (Test-Path -LiteralPath $folder -PathType Container -ErrorAction SilentlyContinue)) { continue }
    try {
        $info = Get-Item -LiteralPath $folder -ErrorAction Stop
        if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        $entries = @(Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction Stop)
        if ($entries.Count -gt 250) { continue }
        foreach ($entry in $entries) {
            if ($entry.Extension -ne '.srt' -or $entry.Length -ne 123768 -or
                ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            $sha = (Get-FileHash -LiteralPath $entry.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
            if ($sha -ceq $expectedVI) { $foundVI += $entry.FullName }
        }
    }
    catch {
        throw 'R32_VI_PS_SCOPED_SCAN_FAILED'
    }
}
Write-Host ('R32_VI_PS_KNOWN_VI_FILE_FOUND=' + [int]($foundVI.Count -gt 0))
if ($foundVI.Count -eq 0) {
    Write-Host 'R32_VI_PS_REAL_FILE_QA=NOT_RUN_MISSING_IN_SCOPE'
}
else {
    try { $vi = InspectSrt $foundVI[0] }
    catch { throw 'R32_VI_PS_REAL_FILE_STRUCTURE_FAILED' }
    if ($vi.Count -ne 1761 -or $vi.Starts[0] -ne 55640 -or
        $vi.Ends[$vi.Ends.Length-1] -ne 7814933) {
        throw 'R32_VI_PS_REAL_FILE_UNEXPECTED_TIMELINE'
    }
    Write-Host 'R32_VI_PS_REAL_FILE_QA=1761_CUES_TIMELINE_PASS'
    Write-Host ('R32_VI_PS_NFC_NORMALIZED=' + [int]$vi.NFC)
    Write-Host ('R32_VI_PS_REPLACEMENT_CHAR_COUNT=' + $vi.ReplacementCharCount)
    Write-Host 'R32_VI_PS_FULL_FILM_SEMANTIC_REVIEW=NOT_PERFORMED'

    $parent = Split-Path -Parent $foundVI[0]
    $siblings = @(Get-ChildItem -LiteralPath $parent -File -Force -ErrorAction Stop)
    $checked = 0
    $matchingTimeline = 0
    $matchingOriginalSha = 0
    if ($siblings.Count -le 120) {
        foreach ($entry in $siblings) {
            if ($entry.FullName -ceq $foundVI[0] -or
                $entry.Extension -ne '.srt' -or
                $entry.Length -lt 80000 -or $entry.Length -gt 200000 -or
                $entry.Name -notmatch '(?i)(thor|ragnarok|\.en\.|english|source)' -or
                ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            $checked++
            if ($checked -gt 12) { throw 'R32_VI_PS_SIBLING_CAP_REACHED' }
            try {
                $candidate = InspectSrt $entry.FullName
                if ($candidate.Count -ne $vi.Count) { continue }
                $same = $true
                for ($i = 0; $i -lt $vi.Count; $i++) {
                    if ($candidate.Starts[$i] -ne $vi.Starts[$i] -or
                        $candidate.Ends[$i] -ne $vi.Ends[$i]) {
                        $same = $false; break
                    }
                }
                if ($same) {
                    $matchingTimeline++
                    $sha = (Get-FileHash -LiteralPath $entry.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                    if ($sha -ceq $expectedEN) { $matchingOriginalSha++ }
                }
            }
            catch {
                # Ignore malformed sibling candidate; never log raw exception.
            }
        }
    }
    Write-Host 'R32_VI_PS_SIBLING_SEARCH=EXACT_VI_PARENT_ONLY_NONRECURSIVE'
    Write-Host ('R32_VI_PS_SIBLING_CANDIDATES=' + $checked)
    Write-Host ('R32_VI_PS_SIBLING_TIMELINE_MATCH=' + $matchingTimeline)
    Write-Host ('R32_VI_PS_SIBLING_ORIGINAL_EN_SHA_MATCH=' + [int]($matchingOriginalSha -gt 0))
}
Write-Host 'R32_VI_PS_NO_FILM_TEXT_OR_PATH_PRINTED=TRUE'
Write-Host 'R32_VI_PS_NO_CHECKPOINT_OR_USER_FILE_WRITE=TRUE'
Write-Host 'R32_VI_PS_MODEL_CALLS=ZERO'
Write-Host 'R32_VI_PS_TV_APK_ACTIONS=NONE'
Write-Host 'R32_VI_PS_READONLY_OBSERVATION_NOT_FULL_PAIR_OR_SEMANTIC_CERTIFICATION'
