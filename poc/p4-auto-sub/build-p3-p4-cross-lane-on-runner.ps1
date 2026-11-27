# Explicit per-film Vietsub Android Debug build for historical PRs and the
# current FLAT/main integration lane, without a hardcoded FLAT PR number.
# No ADB, public artifact upload, TV install or release. Exact PR #120 source verification.
# Public-repository builds are allowed; CI must not publish debug APK artifacts from public runs.
# No ADB, TV changes, release/signing, network/firewall/service or AIOS dispatch.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$AppRepoRoot,
      [Parameter(Mandatory=$true)][string]$SourceCommit)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = 'trung-via/torrent-tv-vietsub'
$pr162 = $env:GITHUB_REF -ceq 'refs/pull/162/merge'
$pr168 = $env:GITHUB_REF -ceq 'refs/pull/168/merge'
$requestedPr = $null
if ($env:GITHUB_REF -cmatch '^refs/pull/([1-9][0-9]*)/merge$') {
    $requestedPr = [int]$Matches[1]
}
$flat = ($requestedPr -ne $null -and
    ($env:GITHUB_HEAD_REF -cmatch '^feature/r0-flat-[a-z0-9-]+$' -or
     ($requestedPr -eq 178 -and
      $env:GITHUB_HEAD_REF -ceq 'fix/full-flow-p2-p4-telemetry-20261121') -or
     ($requestedPr -eq 179 -and
      $env:GITHUB_HEAD_REF -ceq 'fix/p2-dual-candidates-20261122')) -and
    $env:GITHUB_BASE_REF -ceq 'main')
$g1Performance = ($requestedPr -eq 186 -and
    $env:GITHUB_HEAD_REF -ceq 'feature/p2-lean120-parallel-20261124' -and
    $env:GITHUB_BASE_REF -ceq 'feature/brain-en-inbox-temporary-20261123')
$g1Limits = ($requestedPr -eq 189 -and
    $env:GITHUB_HEAD_REF -ceq 'fix/g1-flat-subtitle-limits-20261127' -and
    $env:GITHUB_BASE_REF -ceq 'feature/g1-v13-owner-evidence-20261126')
$g2Flow = ($requestedPr -eq 195 -and
    $env:GITHUB_HEAD_REF -ceq 'feat/g2-owner-warm-session-20261127' -and
    $env:GITHUB_BASE_REF -ceq 'perf/g1-v135-acquisition-20261127')
if (@(@($pr162,$pr168,$flat,$g1Performance,$g1Limits,$g2Flow) | Where-Object { $_ }).Count -ne 1) {
    throw 'STOP: expected exactly one approved build-only PR identity'
}
$branch = if ($pr162) { 'feature/p3-p4-cross-lane-tv-owner-compose-20261114' } elseif ($pr168) {
    'feature/p3p4-r0-r2-single-tap-20261116'
} else { $env:GITHUB_HEAD_REF }
$baseBranch = if ($pr168) { 'feature/p3-owner-v2-offline-activation-20261115' } elseif ($g1Performance) {
    'feature/brain-en-inbox-temporary-20261123'
} elseif ($g1Limits) { 'feature/g1-v13-owner-evidence-20261126' } elseif ($g2Flow) {
    'perf/g1-v135-acquisition-20261127'
} else { 'main' }
$allowedWorkflows = if ($pr162) {
    @('.github/workflows/tv-p3-p4-cross-lane-android-ci.yml')
} elseif ($pr168) {
    @('.github/workflows/tv-p3p4-one-tap-android-ci.yml')
} else {
    @('.github/workflows/tv-flat-integration-android-ci.yml')
}
$workflowRefValid = @($allowedWorkflows | Where-Object {
    $env:GITHUB_WORKFLOW_REF -and
        $env:GITHUB_WORKFLOW_REF.StartsWith(($repo + '/' + $_ + '@'),[StringComparison]::Ordinal)
}).Count -eq 1
$runnerRoot = 'C:\TOOL\TorrentTV-Runner\_work'
$ompPin = '52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f'
$playerPin = '6ba6edd39f5d986ddfae29b5425b8ac0b319844e'
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_EVENT_NAME -cne 'pull_request' -or
    $env:GITHUB_REPOSITORY -cne $repo -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_HEAD_REF -cne $branch -or
    $env:GITHUB_BASE_REF -cne $baseBranch -or
    -not $workflowRefValid) {
    throw 'STOP: event, branch, workflow or dedicated runner identity mismatch'
}
if ($pr162 -and ($env:GITHUB_REF -cne 'refs/pull/162/merge' -or
    $env:GITHUB_BASE_REF -cne 'main')) {
    throw 'STOP: PR #162 build-only GitHub identity mismatch'
}
if ($pr168 -and ($env:GITHUB_REF -cne 'refs/pull/168/merge' -or
    $env:GITHUB_BASE_REF -cne 'feature/p3-owner-v2-offline-activation-20261115')) {
    throw 'STOP: PR #168 build-only GitHub identity mismatch'
}
if ($flat -and ($env:GITHUB_REF -cne ('refs/pull/' + $requestedPr + '/merge') -or
    $env:GITHUB_BASE_REF -cne 'main')) {
    throw 'STOP: FLAT build-only PR event identity mismatch'
}
if ($SourceCommit -notmatch '^[a-f0-9]{40}$' -or $env:GITHUB_SHA -notmatch '^[a-f0-9]{40}$') {
    throw 'STOP: G2 source commit not pinned to dispatched GitHub SHA'
}
if (-not $env:GITHUB_EVENT_PATH -or -not (Test-Path -LiteralPath $env:GITHUB_EVENT_PATH -PathType Leaf)) {
    throw 'STOP: workflow event payload absent'
}
$eventData = Get-Content -LiteralPath $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json
if ($eventData.repository.full_name -cne $repo -or
    $eventData.pull_request.head.repo.full_name -cne $repo -or
    $eventData.pull_request.head.ref -cne $branch -or
    $eventData.pull_request.head.sha -cne $SourceCommit -or
    $eventData.pull_request.base.ref -cne $baseBranch -or
    $eventData.pull_request.user.login -cne 'trung-via' -or
    $eventData.action -notin @('opened','synchronize','reopened')) {
    throw 'STOP: unexpected owner PR identity or head SHA'
}
if ($pr162 -and [int]$eventData.number -ne 162) {
    throw 'STOP: PR #162 event number mismatch'
}
if ($pr168 -and [int]$eventData.number -ne 168) {
    throw 'STOP: PR #168 event number mismatch'
}
if (($flat -or $g1Performance -or $g1Limits -or $g2Flow) -and [int]$eventData.number -ne $requestedPr) {
    throw 'STOP: FLAT event number mismatch'
}
if ($eventData.repository.private -ne $true -and $eventData.repository.private -ne $false) {
    throw 'STOP: repository visibility missing in workflow dispatch payload'
}
if ($eventData.repository.private -eq $false) {
    Write-Host 'G2_PUBLIC_REPO_BUILD_ALLOWED_APK_UPLOAD_DISABLED'
}
foreach ($envKey in @('RUNNER_WORKSPACE','RUNNER_TEMP','GITHUB_WORKSPACE','GITHUB_RUN_ID','GITHUB_RUN_ATTEMPT')) {
    if (-not [Environment]::GetEnvironmentVariable($envKey)) {
        throw 'STOP: runner isolation metadata absent'
    }
}
$allowed = [IO.Path]::GetFullPath($runnerRoot).TrimEnd('\') + '\'
foreach ($loc in @($env:RUNNER_WORKSPACE,$env:RUNNER_TEMP,$env:GITHUB_WORKSPACE)) {
    if (-not ([IO.Path]::GetFullPath($loc).TrimEnd('\') + '\').StartsWith(
         $allowed,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'STOP: checkout/workspace outside dedicated TorrentTV runner'
    }
}
$AppRepoRoot = (Resolve-Path -LiteralPath $AppRepoRoot).Path
$repoHead = (& git -C $AppRepoRoot rev-parse HEAD | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $repoHead -cne $SourceCommit) {
    throw 'STOP: source checkout drift from approved commit'
}
# The dedicated checkout may contain unrelated runner-generated untracked
# files. They cannot change the exact tracked source pinned to SourceCommit.
# Guard tracked source drift only; build output goes to an isolated OMP clone.
$dirty = @(& git -C $AppRepoRoot status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) {
    throw 'STOP: tracked app source checkout must be clean'
}
foreach ($name in @('apply.ps1','verify.ps1','P1ProductionSubtitles.kt','P1ProductionSubtitlesTest.kt')) {
    $file = Join-Path $AppRepoRoot ('poc\g1-prod\' + $name)
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw 'STOP: required G1 Production source missing'
    }
}
foreach ($file in @('apply.ps1','verify.ps1')) {
    $target = Join-Path $AppRepoRoot ('poc\g1-prod\' + $file)
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $target,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count -ne 0) { throw ('STOP: PowerShell parser failed for ' + $file) }
}
foreach ($relative in @('poc\g2-refresh\apply.py','poc\g2-refresh\G2RefreshDecision.kt',
                        'poc\g2-refresh\G2RefreshInPlace.kt','poc\g2-refresh\test_apply.py',
                        'poc\g2-refresh\build-on-runner.ps1','poc\g2-refresh\G2RefreshRecovery.kt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $AppRepoRoot $relative) -PathType Leaf)) {
        throw ('STOP: required G2 file absent: ' + $relative)
    }
}
Write-Host 'G2_RUNNER_AND_SOURCE_GUARDS_PASS'

$node = 'C:\Program Files\nodejs'
$adoptium = 'C:\Program Files\Eclipse Adoptium'
$sdk = 'C:\TOOL\Android-SDK'
function Get-Jdk([string]$prefix) {
    Get-ChildItem -LiteralPath $adoptium -Directory -ErrorAction Stop |
        Where-Object { $_.Name -like "$prefix*" -and
            (Test-Path -LiteralPath (Join-Path $_.FullName 'bin\javac.exe') -PathType Leaf) } |
        Sort-Object Name -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
$j21 = Get-Jdk 'jdk-21'
$j17 = Get-Jdk 'jdk-17'
if (-not $j21 -or -not $j17) { throw 'BLOCKED: JDK 21 and/or JDK 17 missing' }
if (-not (Test-Path -LiteralPath (Join-Path $node 'node.exe') -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path $sdk 'platforms\android-37.0\android.jar') -PathType Leaf)) {
    throw 'BLOCKED: Node.js or Android API 37 missing'
}
$buildTools = Join-Path $sdk 'build-tools'
if (-not (Test-Path -LiteralPath $buildTools -PathType Container)) {
    throw 'BLOCKED: Android build-tools missing'
}
$aapt2 = @(Get-ChildItem -LiteralPath $buildTools -Directory -ErrorAction Stop |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'aapt2.exe') -PathType Leaf })
if ($aapt2.Count -eq 0) { throw 'BLOCKED: installed aapt2 missing' }
$env:JAVA_HOME = $j21
$env:JAVA_HOME_17_X64 = $j17
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:PATH = "$node;$(Join-Path $j21 'bin');$sdk\platform-tools;$env:PATH"
$cache = Join-Path $env:RUNNER_WORKSPACE '_omp-fast-cache'
$env:GRADLE_USER_HOME = Join-Path $cache 'gradle'
$env:NPM_CONFIG_CACHE = Join-Path $cache 'npm'
New-Item -ItemType Directory -Force -Path $env:GRADLE_USER_HOME,$env:NPM_CONFIG_CACHE | Out-Null
$omp = Join-Path $env:RUNNER_TEMP "p1-g1-prod-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT"
if (Test-Path -LiteralPath $omp) { throw 'STOP: disposable upstream clone already exists' }

& git -c core.longpaths=true clone --no-checkout https://github.com/spacesarmat/omp.git $omp
if ($LASTEXITCODE -ne 0) { throw 'BLOCKED: OMP clone failed' }
& git -C $omp checkout --detach $ompPin
if ($LASTEXITCODE -ne 0) { throw 'BLOCKED: pinned OMP checkout failed' }
& git -C $omp -c core.longpaths=true submodule update --init --recursive
if ($LASTEXITCODE -ne 0) { throw 'BLOCKED: 2160player submodule checkout failed' }
$upstream = (& git -C $omp rev-parse HEAD | Out-String).Trim()
$submodule = (& git -C (Join-Path $omp 'android\vendor\2160player') rev-parse HEAD | Out-String).Trim()
if ($upstream -cne $ompPin -or $submodule -cne $playerPin) {
    throw 'STOP: OMP or 2160player revision drift'
}
Write-Host 'G1PROD_PINNED_OMP_SUBMODULE_PASS'

& (Join-Path $AppRepoRoot 'poc\g1-prod\apply.ps1') -OmpRoot $omp -AppRepoRoot $AppRepoRoot
if (-not $?) { throw 'STOP: G1 Production patch failed' }
& (Join-Path $AppRepoRoot 'poc\g1-prod\verify.ps1') -OmpRoot $omp
if (-not $?) { throw 'STOP: G1 Production source verifier failed' }
Write-Host 'G2_G1_BASELINE_SOURCE_PATCH_PASS'
# HostOps read-only run 42937872150 proved this dedicated Windows installation.
# Do not use the Windows py launcher: it currently points to an AIOS runner tool cache.
$pythonExe = 'C:\Program Files\Python314\python.exe'
if (-not (Test-Path -LiteralPath $pythonExe -PathType Leaf)) {
    throw 'BLOCKED: dedicated system Python at expected path absent'
}
$pythonVersion = (& $pythonExe --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $pythonVersion -notmatch '^Python 3\.') {
    throw 'BLOCKED: dedicated Python interpreter is invalid'
}
Write-Host "G2_DEDICATED_SYSTEM_PYTHON_PASS $pythonVersion"
$g2 = Join-Path $AppRepoRoot 'poc\g2-refresh\apply.py'
Push-Location (Join-Path $AppRepoRoot 'poc\g2-refresh')
try {
    & $pythonExe -m unittest -v test_apply.py
    if ($LASTEXITCODE -ne 0) { throw 'STOP: G2 source patch unit tests failed' }
} finally { Pop-Location }
& $pythonExe $g2 --omp-root $omp
if ($LASTEXITCODE -ne 0) { throw 'STOP: G2 dry-run preflight failed' }
& $pythonExe $g2 --omp-root $omp --apply
if ($LASTEXITCODE -ne 0) { throw 'STOP: G2 source overlay failed' }
$playerDir = Join-Path $omp 'android\app\src\main\java\com\spacesarmat\omp\player'
foreach ($filename in @('G2RefreshDecision.kt','G2RefreshInPlace.kt','G2RefreshRecovery.kt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $playerDir $filename) -PathType Leaf)) {
        throw 'STOP: G2 integrated Kotlin source missing'
    }
}
$activity = Get-Content -LiteralPath (Join-Path $playerDir 'PlayerActivity.kt') -Raw
if (-not $activity.Contains('G2RefreshInPlace.prepare(applicationContext, current, idx)')) {
    throw 'STOP: G2 PlayerActivity integration anchor absent'
}
foreach ($anchor in @('val g2Before = G2RefreshRecovery.capture',
                      'if (rollbackG2Refresh()) return true',
                      'handler.postDelayed(g2RecoveryTimeout, 25_000L)',
                      'g2Recovery?.matchesCurrent(session.request, index())')) {
    if (-not $activity.Contains($anchor)) { throw ('STOP: G2-B2 integration anchor missing: ' + $anchor) }
}
& git -C $omp diff --check
if ($LASTEXITCODE -ne 0) { throw 'STOP: G2 patch diff validation failed' }
Write-Host 'G2_G1_PLUS_G2_PATCH_AND_SOURCE_TEST_PASS_NOT_ANDROID'


# P4 overlay only within this pinned disposable G1+G2 checkout.
$p4 = Join-Path $AppRepoRoot 'poc\p4-auto-sub\apply.py'
if (-not (Test-Path -LiteralPath $p4 -PathType Leaf)) { throw 'STOP: missing P4 source patch' }
& $pythonExe $p4 --omp-root $omp
if ($LASTEXITCODE -ne 0) { throw 'STOP: P4 dry-run preflight failed' }
& $pythonExe $p4 --omp-root $omp --apply
if ($LASTEXITCODE -ne 0) { throw 'STOP: P4 source compose failed' }
foreach ($fn in @('P4SignedReceiver.kt','P4LanClient.kt','P4AppliedLedger.kt','P4ActivationClient.kt','P4PairingStore.kt','P4OwnerBootstrap.kt','P1ProductionSubtitles.kt','PlayerActivity.kt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $playerDir $fn) -PathType Leaf)) {
        throw ('STOP: missing P4 composed source ' + $fn)
    }
}
$activityP4 = [IO.File]::ReadAllText((Join-Path $playerDir 'PlayerActivity.kt'))
$g1P4 = [IO.File]::ReadAllText((Join-Path $playerDir 'P1ProductionSubtitles.kt'))
foreach ($anchor in @('internal fun bindP4Session(', 'internal fun receiveP4Revision(',
                      'internal fun startP4LanSession(', 'internal fun stopP4LanSession()',
                      'P4OwnerBootstrap.consume(applicationContext)', 'private fun beginP4Activation()',
                      'P4ActivationClient.activate(', 'P4PairingStore(applicationContext).load(',
                      'P4AppliedLedger(applicationContext, sessionId, mediaKey, sourceSha256)',
                      'P4LanClient.pollOnce(', 'handler.removeCallbacks(p4LanPoll)',
                      'P1ProductionSubtitles.importAutomaticBytes(')) {
    if (-not $activityP4.Contains($anchor)) { throw ('STOP: P4 Activity hook missing ' + $anchor) }
}
if ($g1Performance -or $g1Limits -or $g2Flow) {
    foreach ($anchor in @('receiver.acknowledgeOverlayInstalled(', 'state.timeline.textAt(engine.positionMs)',
                          'P4_TV_OVERLAY_INSTALLED', 'timeline.extends(old.timeline)')) {
        if (-not $activityP4.Contains($anchor)) { throw ('STOP: Zero-reload Activity hook missing ' + $anchor) }
    }
    if ($activityP4.Contains('p4ExpectedRefresh = newRequest')) {
        throw 'STOP: obsolete automatic reload hook still present'
    }
} else {
    foreach ($anchor in @('p4ExpectedRefresh = newRequest', 'acknowledgeP4FirstFrame()')) {
        if (-not $activityP4.Contains($anchor)) { throw ('STOP: legacy P4 Activity hook missing ' + $anchor) }
    }
}
foreach ($anchor in @('internal fun importAutomaticBytes(', 'internal fun automaticChoice(')) {
    if (-not $g1P4.Contains($anchor)) { throw ('STOP: P4 G1 source hook missing ' + $anchor) }
}
& git -C $omp diff --check
if ($LASTEXITCODE -ne 0) { throw 'STOP: composed source git diff --check failed' }
Write-Host 'P4_G1_G2_COMPOSED_SOURCE_PINNED_PASS_NOT_ANDROID'

# P3 belongs ONLY to the approved P4 composition on disposable OMP source.
# This requires a new source pin and does not touch the installed Redmi APK.
$p3 = Join-Path $AppRepoRoot 'poc\p4-auto-sub\p3_activity_patch.py'
if (-not (Test-Path -LiteralPath $p3 -PathType Leaf)) {
    throw 'STOP: P3 source patch missing'
}
& $pythonExe $p3 --source-root $omp
if ($LASTEXITCODE -ne 0) { throw 'STOP: P3 dry-run source anchors invalid' }
& $pythonExe $p3 --source-root $omp --apply
if ($LASTEXITCODE -ne 0) { throw 'STOP: P3 source composition failed' }
$p3Publisher = Join-Path $playerDir 'P3SelectedMediaPublisher.kt'
if (-not (Test-Path -LiteralPath $p3Publisher -PathType Leaf)) {
    throw 'STOP: P3 native publisher missing from disposable OMP tree'
}
$activityP3 = [IO.File]::ReadAllText((Join-Path $playerDir 'PlayerActivity.kt'))
foreach ($anchorP3 in @(
    'P3SelectedMediaPublisher.accepted(',
    'P3SelectedMediaPublisher.closed(applicationContext)',
    'P3SelectedMediaPublisher.setEnabled(applicationContext, true)',
    'internal fun receiveP4Revision('
)) {
    if (-not $activityP3.Contains($anchorP3)) {
        throw ('STOP: P3 / P4 activity source anchor absent: ' + $anchorP3)
    }
}
if (([regex]::Matches($activityP3, [regex]::Escape('P3SelectedMediaPublisher.accepted('))).Count -ne 2) {
    throw 'STOP: P3 native accepted Play/Next signal count invalid'
}
& git -C $omp diff --check
if ($LASTEXITCODE -ne 0) { throw 'STOP: P3 source whitespace invalid' }
$sender = [IO.File]::ReadAllText($p3Publisher)
foreach ($stateAnchor in @(
    'TTV-P3-TV-STATE-V2',
    '.put("media_key", current.mediaKey)',
    'postJson(paired, "/p3/state", body)',
    'P1ProductionSubtitles.automaticChoice(',
    'private val bootId = randomHex()',
    'private val statusSequence = AtomicLong(0L)'
)) {
    if (-not $sender.Contains($stateAnchor)) {
        throw ('STOP: native P3 signed current-state source anchor absent: ' + $stateAnchor)
    }
}
foreach ($activityAnchor in @(
    'private val p3StatusTick =',
    'handler.postDelayed(this, 3_000L)',
    'P3SelectedMediaPublisher.sample('
)) {
    if (-not $activityP3.Contains($activityAnchor)) {
        throw ('STOP: native Redmi status sampling activity anchor missing: ' + $activityAnchor)
    }
}
$consentActivity = [IO.File]::ReadAllText((Join-Path $playerDir 'PlayerActivity.kt'))
$consentPublisher = [IO.File]::ReadAllText($p3Publisher)
foreach ($anchorConsent in @(
    'P3SelectedMediaPublisher.requestViewer(',
    'VIEWER_VIETSUB_REQUESTED',
    'private val p3ActivationTick =',
    'p3ActivationAttempts >= 120',
    'P3SelectedMediaPublisher.reaffirmViewer(',
    'P3SelectedMediaPublisher.cancelViewer('
)) {
    if (-not ($consentActivity.Contains($anchorConsent) -or $consentPublisher.Contains($anchorConsent))) {
        throw ('STOP: explicit viewer-only P3 activation anchor missing: ' + $anchorConsent)
    }
}
Write-Host 'P3_EXPLICIT_VIEWER_BEFORE_P4_SOURCE_READY_COMPOSED_SOURCE_PASS_NOT_ANDROID'
Write-Host 'P3_REDMi_NATIVE_SIGNED_CURRENT_STATE_SOURCE_PINNED_PASS_NOT_ANDROID'
Write-Host 'P3_G1_G2_P4_NATIVE_SOURCE_COMPOSED_PASS_NOT_ANDROID'

$props = Join-Path $env:GRADLE_USER_HOME 'gradle.properties'
$setting = 'org.gradle.java.installations.fromEnv=JAVA_HOME_17_X64'
$existing = @()
if (Test-Path -LiteralPath $props -PathType Leaf) {
    $existing = @(Get-Content -LiteralPath $props |
        Where-Object { $_ -match '^\s*org\.gradle\.java\.installations\.fromEnv\s*=' })
}
if ($existing.Count -gt 1 -or ($existing.Count -eq 1 -and $existing[0].Trim() -cne $setting)) {
    throw 'STOP: dedicated Gradle JDK setting conflict'
}
if ($existing.Count -eq 0) { Add-Content -LiteralPath $props -Value $setting -Encoding ascii }

Push-Location $omp
try {
    & npm.cmd ci --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw 'BLOCKED: npm ci failed' }
    & npm.cmd run android:sync
    if ($LASTEXITCODE -ne 0) { throw 'BLOCKED: npm android:sync failed' }
} finally { Pop-Location }
# Gradle daemon heap (upstream org.gradle.jvmargs=-Xmx4g) is not the forked JUnit test JVM heap.
# Run 42938311816: 665/666 succeeded, one OOM in InstallRunnerTest (LG fake installer).
# Apply a bounded, per-run test-only heap/fork policy without touching OMP upstream sources.
$initScript = Join-Path $env:RUNNER_TEMP "g2-test-memory-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT.init.gradle"
if (Test-Path -LiteralPath $initScript -PathType Leaf) {
    throw 'STOP: unexpected existing G2 Gradle test policy'
}
@'
gradle.projectsEvaluated {
    rootProject.allprojects { project ->
        project.tasks.withType(org.gradle.api.tasks.testing.Test).configureEach { testTask ->
            testTask.maxHeapSize = '1536m'
            testTask.maxParallelForks = 1
            testTask.forkEvery = 75
        }
    }
}
'@ | Set-Content -LiteralPath $initScript -Encoding Ascii
Write-Host 'G2_TEST_MEMORY_POLICY_TEST_JVM_1536M_MAX_FORKS_1_FORK_EVERY_75'

Push-Location (Join-Path $omp 'android')
try {
    # Check the precise previously failing LG fake install case, before any full-suite result.
    & .\gradlew.bat :app:testDebugUnitTest --tests com.spacesarmat.omp.install.InstallRunnerTest.lgInstallsOmpAndHomebrewChannel -I $initScript --no-daemon --console plain
    if ($LASTEXITCODE -ne 0) { throw 'BLOCKED: targeted LG install test did not recover under isolated JVM policy' }
    Write-Host 'G2_TARGETED_LG_INSTALL_TEST_PASS'
    & .\gradlew.bat assembleDebug testDebugUnitTest -I $initScript --no-daemon --console plain
    if ($LASTEXITCODE -ne 0) { throw 'BLOCKED: full Gradle assembleDebug/testDebugUnitTest failed' }
} finally { Pop-Location }
Write-Host 'P3_P4_COMPOSED_ANDROID_DEBUG_BUILD_AND_UNIT_TEST_PASS_NOT_REAL_TV_PASS'

$dir = Join-Path $omp 'android\app\build\outputs\apk\debug'
$apks = @(Get-ChildItem -LiteralPath $dir -File -Filter '*.apk' -ErrorAction Stop)
if ($apks.Count -lt 1 -or $apks.Count -gt 6) { throw 'STOP: unexpected debug APK count' }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$hashes = @()
foreach ($apk in $apks) {
    $zip = [IO.Compression.ZipFile]::OpenRead($apk.FullName)
    try {
        $unexpected = @($zip.Entries | Where-Object {
            $_.FullName -in @('assets/p1-g1-external.vi.srt','assets/p1-vietsub-utf8.srt') -or
            $_.FullName -match '(?i)p1-g1c\.register|p1-g1-external\.vi\.srt'
        })
        if ($unexpected.Count -gt 0) { throw 'STOP: G1c/G0 debug fixture packaged in G1 Production APK' }
    } finally { $zip.Dispose() }
    $sum = (Get-FileHash -LiteralPath $apk.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $hashes += "$sum  $($apk.Name)"
    Write-Host "P4_DEBUG_APK_SHA256 $($apk.Name) $sum"
}
$hashes | Out-File -LiteralPath (Join-Path $dir 'SHA256SUMS-P4-COMPOSED.txt') -Encoding ascii
@(
    'P4_COMPOSED_ANDROID_DEBUG_BUILD_AND_UNIT_TEST_PASS',
    'NOT_REAL_TV_PASS_OR_RELEASE_PASS',
    "app_commit=$SourceCommit",
    "omp_commit=$upstream",
    "submodule_commit=$submodule",
    "runner=$env:RUNNER_NAME",
    "run_id=$env:GITHUB_RUN_ID",
    'signing=debug_variant_only',
    "source_set=$branch",
    'no_adb_or_tv_install=yes',
    'P4_AUTO_REFRESH_REAL_TV_UNVERIFIED',
    'P4_RELEASE_BINARY_UNVERIFIED'
) | Out-File -LiteralPath (Join-Path $dir 'P4-COMPOSED-BUILD-EVIDENCE.txt') -Encoding utf8
# Preserve the exact Debug APK privately for separate owner-authorized Redmi
# acceptance. Prior CI left it only in RUNNER_TEMP, which the runner cleaned
# before the next job. This copy is NEVER a device install or public artifact.
$arm32 = @($apks | Where-Object { $_.Name -ceq 'app-armeabi-v7a-debug.apk' })
if ($arm32.Count -ne 1) { throw 'P4_STAGE_EXPECTED_SINGLE_ARM32_APK' }
$stagePrefix = if ($pr162) { 'p4-pr162-staged\' } elseif ($pr168) {
    'p4-pr168-staged\'
} else { 'p4-flat-staged\' }
$staged = Join-Path $cache ($stagePrefix + $SourceCommit)
if (Test-Path -LiteralPath $staged -PathType Leaf) {
    throw 'P4_STAGE_TARGET_NOT_DIRECTORY'
}
New-Item -ItemType Directory -Path $staged -Force | Out-Null
$target = Join-Path $staged 'app-armeabi-v7a-debug.apk'
$srcHash = (Get-FileHash -LiteralPath $arm32[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant()
if (Test-Path -LiteralPath $target -PathType Leaf) {
    $previous = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($previous -cne $srcHash) {
        throw 'P4_STAGE_EXISTING_SOURCE_SHA_HAS_DIFFERENT_APK'
    }
} else {
    Copy-Item -LiteralPath $arm32[0].FullName -Destination $target -ErrorAction Stop
}
$copied = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
if ($copied -cne $srcHash) { throw 'P4_STAGE_COPIED_APK_SHA256_MISMATCH' }
$stageSchema = if ($pr162) { 'schema=TTV-P4-PR162-APK-STAGE-V1' } elseif ($pr168) {
    'schema=TTV-P4-PR168-APK-STAGE-V1'
} else { 'schema=TTV-P4-FLAT-APK-STAGE-V1' }
@(
    $stageSchema,
    "app_commit=$SourceCommit",
    "omp_commit=$upstream",
    "submodule_commit=$submodule",
    'variant=app-armeabi-v7a-debug.apk',
    "sha256=$copied",
    'artifact_placement=dedicated_windows_runner_private_cache',
    'device_installed=no',
    'real_lan_tested=no'
) | Set-Content -LiteralPath (Join-Path $staged 'stage-receipt.txt') -Encoding Ascii -ErrorAction Stop
Write-Host "P4_APPROVED_PR_DEBUG_ARM32_STAGED_PRIVATELY_EXACT_SHA_PASS_NOT_INSTALLED branch=$branch"

$global:LASTEXITCODE = 0
Write-Host 'G2_DEBUG_APK_HASH_AND_ASSET_GUARDS_PASS'
Write-Host 'P3_P4_COMPOSED_ANDROID_DEBUG_BUILD_READY_NOT_TV_APPROVED'
