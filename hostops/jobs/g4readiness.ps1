# G4 readiness for CURRENT G1 Production + P2 OMP composition, not old G1c.
# Creates and deletes an isolated OMP clone under RUNNER_TEMP. No Gradle Release build,
# signing-key bypass, APK publish/install, ADB, TorrServer, firewall or AIOS action.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = 'trung-via/torrent-tv-vietsub'
$ompCommit = '52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f'
$subCommit = '6ba6edd39f5d986ddfae29b5425b8ac0b319844e'
$gradleBlob = 'd0c7a13bf8ad5108e4b82d5bbac8ffd7d522b429'
Write-Host 'G4_CURRENT_COMPOSITION_READINESS_BEGIN'
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
    'poc\p2-source\omp-ui\tvCandidateCheck.ts'
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

$work = Join-Path $env:RUNNER_TEMP ("p1-g1-prod-g4readiness-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT")
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
    Write-Host 'G4_UNSIGNED_SIGNING_BYPASS=NOT_USED'
    Write-Host 'G4_RELEASE_APK_BUILT=NO'
    Write-Host 'G4_RELEASE_SIGNED_APK_VERIFIED=NO'
    Write-Host 'G4_REAL_TV_RELEASE_TEST=NOT_RUN'
    Write-Host 'G4_CURRENT_SOURCE_READINESS=PASS_NOT_BINARY_OR_RELEASE_PASS'
} finally {
    if ($created -and (Test-Path -LiteralPath $work)) {
        # Delete only the uniquely named disposable source clone, never shared caches.
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host 'G4_DISPOSABLE_CLONE_CLEANUP_ATTEMPTED'
    }
}
Write-Host 'G4_CURRENT_COMPOSITION_READINESS_END'
