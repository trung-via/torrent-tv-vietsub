# P1 G1b: HUMAN OPT-IN ONLY; no automatic Actions trigger, ADB or device mutation.
# P1 G1b — manual, gated build on dedicated Torrent TV GitHub Actions runner.
# No automatic workflow trigger, Windows machine settings, ADB, TV, SMB or AIOS modification.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$AppRepoRoot
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$target = 'trung-via/torrent-tv-vietsub'
$runner = 'torrent-tv-vietsub-win'
$workRoot = 'C:\TOOL\TorrentTV-Runner\_work'
$ompPin = '52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f'
$playerPin = '6ba6edd39f5d986ddfae29b5425b8ac0b319844e'
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne $target -or
    $env:RUNNER_NAME -cne $runner -or
    $env:RUNNER_OS -cne 'Windows') {
    throw 'STOP: this build only runs as an authorized action on the dedicated app runner'
}
foreach ($name in @('RUNNER_WORKSPACE', 'RUNNER_TEMP', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT')) {
    if (-not [Environment]::GetEnvironmentVariable($name)) {
        throw "STOP: missing GitHub Actions environment: $name"
    }
}
$expectedRoot = [IO.Path]::GetFullPath($workRoot).TrimEnd('\') + '\'
foreach ($root in @($env:RUNNER_WORKSPACE, $env:RUNNER_TEMP)) {
    $resolved = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($expectedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'STOP: runner workspace/temp path outside dedicated root'
    }
}
$AppRepoRoot = (Resolve-Path -LiteralPath $AppRepoRoot).Path
$repoLocation = [IO.Path]::GetFullPath($AppRepoRoot).TrimEnd('\') + '\'
$runnerLocation = [IO.Path]::GetFullPath($env:RUNNER_WORKSPACE).TrimEnd('\') + '\'
if (-not $repoLocation.StartsWith($runnerLocation, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'STOP: app repository checkout is not inside the dedicated runner workspace'
}
$gitRoot = (& git -C $AppRepoRoot rev-parse --show-toplevel)
if ($LASTEXITCODE -ne 0 -or
    [IO.Path]::GetFullPath($gitRoot).TrimEnd('\') -ne [IO.Path]::GetFullPath($AppRepoRoot).TrimEnd('\')) {
    throw 'STOP: app checkout root mismatch'
}
$repoSha = (& git -C $AppRepoRoot rev-parse HEAD)
if ($LASTEXITCODE -ne 0 -or -not $repoSha.Trim()) { throw 'STOP: cannot prove app repo commit' }
$repoDirty = @(& git -C $AppRepoRoot status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $repoDirty.Count -ne 0) {
    throw 'STOP: app checkout must be clean; never use an ambiguous source snapshot'
}
foreach ($file in @('poc\g1\apply.ps1', 'poc\g1\verify.ps1', 'poc\g1\P1G1SubtitleProbe.debug.kt', 'poc\g1\P1G1SubtitleProbe.release.kt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $AppRepoRoot $file) -PathType Leaf)) {
        throw "STOP: required app file missing: $file"
    }
}

# Reuse proven job-local Windows toolchain from omp-fast-build.yml.
$nodeDir = 'C:\Program Files\nodejs'
$adoptium = 'C:\Program Files\Eclipse Adoptium'
$sdk = 'C:\TOOL\Android-SDK'
if (-not (Test-Path -LiteralPath (Join-Path $nodeDir 'node.exe') -PathType Leaf)) {
    throw 'BLOCKED: Node.js not visible on runner'
}
function Find-Jdk([string]$prefix) {
    Get-ChildItem -LiteralPath $adoptium -Directory -ErrorAction Stop |
        Where-Object { $_.Name -like "$prefix*" -and
            (Test-Path -LiteralPath (Join-Path $_.FullName 'bin\javac.exe') -PathType Leaf) } |
        Sort-Object Name -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
$jdk21 = Find-Jdk 'jdk-21'
$jdk17 = Find-Jdk 'jdk-17'
if (-not $jdk21 -or -not $jdk17) { throw 'BLOCKED: JDK21/JDK17 absent' }
foreach ($f in @(
    "$sdk\platforms\android-37.0\android.jar",
    "$sdk\build-tools\36.0.0\aapt2.exe",
    "$sdk\platform-tools\adb.exe"
)) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) {
        throw "BLOCKED: Android SDK prerequisite missing: $f"
    }
}
$env:JAVA_HOME = $jdk21
$env:JAVA_HOME_17_X64 = $jdk17
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:PATH = "$nodeDir;$(Join-Path $jdk21 'bin');$sdk\platform-tools;$env:PATH"

# Isolated per-run directories only. No machine PATH, firewall, startup or service changes.
$cache = Join-Path $env:RUNNER_WORKSPACE '_omp-fast-cache'
$env:GRADLE_USER_HOME = Join-Path $cache 'gradle'
$env:NPM_CONFIG_CACHE = Join-Path $cache 'npm'
New-Item -ItemType Directory -Force -Path $env:GRADLE_USER_HOME, $env:NPM_CONFIG_CACHE | Out-Null
$ompRoot = Join-Path $env:RUNNER_TEMP "p1-g1-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT"
if (Test-Path -LiteralPath $ompRoot) { throw 'STOP: job worktree already exists; do not reuse' }

& git -c core.longpaths=true clone --no-checkout https://github.com/spacesarmat/omp.git $ompRoot
if ($LASTEXITCODE -ne 0) { throw 'BLOCKED: OMP clone failed' }
& git -C $ompRoot checkout --detach $ompPin
if ($LASTEXITCODE -ne 0) { throw 'BLOCKED: OMP checkout failed' }
& git -C $ompRoot -c core.longpaths=true submodule update --init --recursive
if ($LASTEXITCODE -ne 0) { throw 'BLOCKED: OMP submodule init failed' }
$actual = (& git -C $ompRoot rev-parse HEAD).Trim()
$actualPlayer = (& git -C (Join-Path $ompRoot 'android\vendor\2160player') rev-parse HEAD).Trim()
if ($actual -cne $ompPin -or $actualPlayer -cne $playerPin) {
    throw 'STOP: pinned OMP / 2160player source mismatch'
}

& (Join-Path $AppRepoRoot 'poc\g1\apply.ps1') -OmpRoot $ompRoot -AppRepoRoot $AppRepoRoot
if (-not $?) { throw 'STOP: G1B apply failed' }
& (Join-Path $AppRepoRoot 'poc\g1\verify.ps1') -OmpRoot $ompRoot
if (-not $?) { throw 'STOP: G1B static verification failed' }

$setting = 'org.gradle.java.installations.fromEnv=JAVA_HOME_17_X64'
$gradleProps = Join-Path $env:GRADLE_USER_HOME 'gradle.properties'
$existing = @()
if (Test-Path -LiteralPath $gradleProps) {
    $existing = @(Get-Content -LiteralPath $gradleProps |
        Where-Object { $_ -match '^\s*org\.gradle\.java\.installations\.fromEnv\s*=' })
}
if ($existing.Count -gt 1 -or ($existing.Count -eq 1 -and $existing[0].Trim() -cne $setting)) {
    throw 'STOP: conflicting Gradle JDK toolchain setting'
}
if ($existing.Count -eq 0) {
    Add-Content -LiteralPath $gradleProps -Encoding ascii -Value $setting
}

Push-Location $ompRoot
try {
    & npm.cmd ci --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw "BLOCKED: npm ci exit $LASTEXITCODE" }
    & npm.cmd run android:sync
    if ($LASTEXITCODE -ne 0) { throw "BLOCKED: npm android:sync exit $LASTEXITCODE" }
} finally { Pop-Location }
Push-Location (Join-Path $ompRoot 'android')
try {
    & .\gradlew.bat assembleDebug testDebugUnitTest --no-daemon --console plain
    if ($LASTEXITCODE -ne 0) { throw "BLOCKED: Gradle build/unit tests exit $LASTEXITCODE" }
} finally { Pop-Location }

$outDir = Join-Path $ompRoot 'android\app\build\outputs\apk\debug'
$apks = @(Get-ChildItem -LiteralPath $outDir -Filter '*.apk' -File -ErrorAction Stop)
if ($apks.Count -lt 1) { throw 'BLOCKED: expected debug APK missing' }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($apk in $apks) {
    $archive = [IO.Compression.ZipFile]::OpenRead($apk.FullName)
    try {
        $unexpected = @($archive.Entries | Where-Object {
            $_.FullName -eq 'assets/p1-g1-external.vi.srt' -or
            $_.FullName -eq 'assets/p1-vietsub-utf8.srt'
        })
        if ($unexpected.Count -ne 0) {
            throw "STOP: external G1 or legacy G0 fixture is bundled in debug APK $($apk.Name)"
        }
    } finally { $archive.Dispose() }
}

$shaFile = Join-Path $outDir 'SHA256SUMS.txt'
$hashLines = foreach ($apk in $apks) {
    $digest = (Get-FileHash -LiteralPath $apk.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$digest  $($apk.Name)"
}
$hashLines | Out-File -LiteralPath $shaFile -Encoding ascii
$proof = @(
    'P1-G1B_BUILD_COMPLETED (not G1b TV PASS)',
    "app_repo=$target",
    "app_commit=$($repoSha.Trim())",
    "omp_commit=$actual",
    "player_commit=$actualPlayer",
    "runner=$env:RUNNER_NAME",
    "run_id=$env:GITHUB_RUN_ID",
    'stage=compile+Android_unit+external_srt_asset_absence',
    'G1B_EXTERNAL_SRT_RENDER_UNVERIFIED',
    'EXTERNAL_SRT_E2E_UNVERIFIED',
    'G4_RELEASE_ISOLATION_ARTIFACT_UNVERIFIED'
)
$proofFile = Join-Path $outDir 'P1-G1B-BUILD-EVIDENCE.txt'
$proof | Out-File -LiteralPath $proofFile -Encoding utf8
Write-Host 'P1-G1B_BUILD_COMPLETED: app patch applied, Gradle build/unit and absence of external SRT assets in APK verified'
Write-Host "Artifacts staged privately: $outDir"
Write-Host 'No TV, external subtitle import, release artifact or AIOS canonical PASS implied.'
