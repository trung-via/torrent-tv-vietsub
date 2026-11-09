# G4 source-only preflight for accepted G1 Production + P2 + Font v3 on exact OMP.
# Dedicated owner-command read-only evidence; no Release build/sign/install.
# Creates and deletes an isolated OMP clone under RUNNER_TEMP. No Gradle Release build,
# signing-key bypass, APK publish/install, ADB, TorrServer, firewall or AIOS action.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = 'trung-via/torrent-tv-vietsub'
$ompCommit = '52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f'
$subCommit = '6ba6edd39f5d986ddfae29b5425b8ac0b319844e'
$gradleBlob = 'd0c7a13bf8ad5108e4b82d5bbac8ffd7d522b429'
Write-Host 'G4V3_COMPOSITION_PREFLIGHT_BEGIN'
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne $repo -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_EVENT_NAME -cne 'issue_comment') {
    throw 'G4_STOP_BAD_RUNNER_OR_EVENT'
}
$root = [IO.Path]::GetFullPath('C:\TOOL\TorrentTV-Runner\_work').TrimEnd('\') + '\'
foreach ($name in @('GITHUB_WORKSPACE','RUNNER_TEMP','GITHUB_RUN_ID','GITHUB_RUN_ATTEMPT')) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) { throw 'G4_STOP_MISSING_RUNNER_METADATA' }
    if ($name -in @('GITHUB_WORKSPACE','RUNNER_TEMP')) {
        $path = [IO.Path]::GetFullPath($value).TrimEnd('\') + '\'
        if (-not $path.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) {
            throw 'G4_STOP_PATH_OUTSIDE_DEDICATED_RUNNER'
        }
    }
}
$repoRoot = (Resolve-Path -LiteralPath $env:GITHUB_WORKSPACE).Path
$sourceHash = (& git -C $repoRoot rev-parse HEAD | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $sourceHash -notmatch '^[a-f0-9]{40}$') {
    throw 'G4_STOP_SOURCE_NOT_PINNED'
}
$dirty = @(& git -C $repoRoot status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'G4_STOP_SOURCE_DIRTY' }
foreach ($relative in @(
    'poc\g1-prod\apply.ps1',
    'poc\g1-prod\verify.ps1',
    'poc\g1-prod\P1ProductionSubtitles.kt',
    'poc\g1-prod\P1ProductionSubtitlesTest.kt',
    'poc\p2-source\omp-ui\apply.mjs',
    'poc\p2-source\omp-ui\tvCandidateCheck.ts',
    'poc\vi-font\apply.mjs',
    'poc\vi-font\apply.test.mjs',
    'poc\vi-font\verify.mjs'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relative) -PathType Leaf)) {
        throw 'G4_STOP_G1_OR_P2_SOURCE_MISSING'
    }
}
$helper = Get-Content -LiteralPath (Join-Path $repoRoot 'poc\g1-prod\P1ProductionSubtitles.kt') -Raw
if (-not $helper.Contains('internal object P1ProductionSubtitles') -or
    -not $helper.Contains('fun importSelected') -or
    -not $helper.Contains('fun prepare') -or
    $helper.Contains('P1G1CSubtitleRegistry') -or
    $helper.Contains('P1G0SubtitleProbe')) {
    throw 'G4_STOP_PRODUCTION_HELPER_INVALID'
}
Write-Host 'G4_CURRENT_SOURCE_HELPER_PASS'

$node = 'C:\Program Files\nodejs\node.exe'
if (-not (Test-Path -LiteralPath $node -PathType Leaf)) { throw 'G4_STOP_NODE_NOT_INSTALLED' }
& $node --check (Join-Path $repoRoot 'poc\p2-source\omp-ui\apply.mjs')
if ($LASTEXITCODE -ne 0) { throw 'G4_STOP_P2_APPLY_SYNTAX' }

# Exact tested-v3 Git blobs from merged PR #99; detect any content drift.
$fontBlobs = @{
    'poc/vi-font/apply.mjs' = '0159dc864948240a27a35c9ac447c658a66405d9'
    'poc/vi-font/apply.test.mjs' = '2925f8221329957c26d6d574304bf0aa235ae43e'
    'poc/vi-font/verify.mjs' = 'f54dfdef8a73937a2d9efc3a0b07dea66678892b'
}
foreach ($item in $fontBlobs.GetEnumerator()) {
    $actual = (& git -C $repoRoot rev-parse "HEAD:$($item.Key)" | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $actual -cne $item.Value) { throw 'G4V3_STOP_FONT_BLOB_DRIFT' }
}
Write-Host 'G4V3_EXACT_ACCEPTED_FONT_BLOBS_PASS'
& $node --test (Join-Path $repoRoot 'poc\vi-font\apply.test.mjs')
if ($LASTEXITCODE -ne 0) { throw 'G4V3_STOP_FONT_UNIT_TEST_FAILED' }
Write-Host 'G4V3_FONT_NODE_TESTS_PASS'
$work = Join-Path $env:RUNNER_TEMP ("p1-g1-prod-g4v3preflight-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT")
if (Test-Path -LiteralPath $work) { throw 'G4_STOP_DISPOSABLE_WORK_ALREADY_EXISTS' }
$created = $false
try {
    & git -c core.longpaths=true clone --no-checkout https://github.com/spacesarmat/omp.git $work
    if ($LASTEXITCODE -ne 0) { throw 'G4_BLOCKED_OMP_CLONE' }
    $created = $true
    & git -C $work checkout --detach $ompCommit
    if ($LASTEXITCODE -ne 0) { throw 'G4_BLOCKED_OMP_CHECKOUT' }
    & git -C $work -c core.longpaths=true submodule update --init --recursive
    if ($LASTEXITCODE -ne 0) { throw 'G4_BLOCKED_2160_SUBMODULE' }
    $head = (& git -C $work rev-parse HEAD | Out-String).Trim()
    $sub = (& git -C (Join-Path $work 'android\vendor\2160player') rev-parse HEAD | Out-String).Trim()
    if ($head -cne $ompCommit -or $sub -cne $subCommit) {
        throw 'G4_STOP_OMP_PIN_MISMATCH'
    }
    Write-Host 'G4_CURRENT_OMP_SUBMODULE_PINS_PASS'

    & (Join-Path $repoRoot 'poc\g1-prod\apply.ps1') -OmpRoot $work -AppRepoRoot $repoRoot
    if (-not $?) { throw 'G4_STOP_G1_APPLY_FAILED' }
    & (Join-Path $repoRoot 'poc\g1-prod\verify.ps1') -OmpRoot $work
    if (-not $?) { throw 'G4_STOP_G1_VERIFY_FAILED' }
    Write-Host 'G4_CURRENT_G1_PRODUCTION_SOURCE_GUARDS_PASS'

    & $node (Join-Path $repoRoot 'poc\p2-source\omp-ui\apply.mjs') $work
    if ($LASTEXITCODE -ne 0) { throw 'G4_STOP_P2_COMPOSITION_FAILED' }
    Write-Host 'G4_CURRENT_G1P2_COMPOSED_SOURCES_PASS'

    # Final, merged PR #99 Font v3 overlay applies only after G1 Production then P2.
    & $node (Join-Path $repoRoot 'poc\vi-font\apply.mjs') $work
    if ($LASTEXITCODE -ne 0) { throw 'G4V3_STOP_FONT_PATCH_FAILED' }
    & $node (Join-Path $repoRoot 'poc\vi-font\verify.mjs') $work
    if ($LASTEXITCODE -ne 0) { throw 'G4V3_STOP_FONT_COMPOSED_VERIFY_FAILED' }
    Write-Host 'G4V3_COMPOSED_G1_P2_FONT_V3_SOURCE_PASS'

    $mainHelper = Join-Path $work 'android\app\src\main\java\com\spacesarmat\omp\player\P1ProductionSubtitles.kt'
    $testHelper = Join-Path $work 'android\app\src\test\java\com\spacesarmat\omp\player\P1ProductionSubtitlesTest.kt'
    if (-not (Test-Path -LiteralPath $mainHelper -PathType Leaf) -or
        -not (Test-Path -LiteralPath $testHelper -PathType Leaf)) {
        throw 'G4_STOP_MAIN_HELPER_OR_TEST_MISSING'
    }
    foreach ($variant in @('debug','release')) {
        $wrong = Join-Path $work ("android\app\src\$variant\java\com\spacesarmat\omp\player\P1ProductionSubtitles.kt")
        if (Test-Path -LiteralPath $wrong) { throw 'G4_STOP_HELPER_IN_WRONG_VARIANT' }
    }
    foreach ($asset in @('p1-g1-external.vi.srt','p1-vietsub-utf8.srt')) {
        foreach ($variant in @('main','debug','release')) {
            $wrong = Join-Path $work ("android\app\src\$variant\assets\$asset")
            if (Test-Path -LiteralPath $wrong) { throw 'G4_STOP_TEST_ASSET_IN_SOURCE_SET' }
        }
    }
    Write-Host 'G4_CURRENT_MAIN_SOURCE_AND_NO_DEBUG_FIXTURE_PASS'

    $gradleFile = Join-Path $work 'android\app\build.gradle'
    $blob = (& git -C $work hash-object -- 'android/app/build.gradle' | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $blob -cne $gradleBlob) {
        throw 'G4_STOP_GRADLE_SIGNING_BASELINE_DRIFT'
    }
    $gradleText = Get-Content -LiteralPath $gradleFile -Raw
    if (-not $gradleText.Contains('signingConfig signingConfigs.release') -or
        -not $gradleText.Contains('gradle.taskGraph.whenReady')) {
        throw 'G4_STOP_RELEASE_SIGNING_GUARD_MISSING'
    }
    Write-Host 'G4_RELEASE_SIGNING_GUARD_INTACT_PASS'
    # Check configuration presence only: no secret values, key names/paths, APK or key bytes are printed.
    $signingNames = @('ANDROID_KEYSTORE_FILE','ANDROID_KEYSTORE_PASSWORD','ANDROID_KEY_ALIAS','ANDROID_KEY_PASSWORD')
    $signingReady = $true
    foreach ($name in $signingNames) {
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) { $signingReady = $false }
    }
    if ($signingReady) { Write-Host 'G4V3_SIGNING_ENV=FOUR_FIELDS_PRESENT_NOT_KEY_VERIFIED' }
    else { Write-Host 'G4V3_SIGNING_ENV=INCOMPLETE_OR_NOT_IN_THIS_JOB' }
    Write-Host 'G4_UNSIGNED_SIGNING_BYPASS=NOT_USED'
    Write-Host 'G4_RELEASE_APK_BUILT=NO'
    Write-Host 'G4_RELEASE_SIGNED_APK_VERIFIED=NO'
    Write-Host 'G4_REAL_TV_RELEASE_TEST=NOT_RUN'
    Write-Host 'G4V3_SOURCE_COMPOSITION=PASS_NOT_BINARY_OR_RELEASE_PASS'
} finally {
    if ($created -and (Test-Path -LiteralPath $work)) {
        # Delete only the uniquely named disposable source clone, never shared caches.
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host 'G4_DISPOSABLE_CLONE_CLEANUP_ATTEMPTED'
    }
}
Write-Host 'G4V3_COMPOSITION_PREFLIGHT_END'
