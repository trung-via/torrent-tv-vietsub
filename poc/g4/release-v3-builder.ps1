# G4-B1: manual-only signed Release, strictly separate Human authorization required.
# No APK publication, ADB, TV install, TorrServer, services, firewall or AIOS.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$AppRepoRoot,
      [Parameter(Mandatory=$true)][string]$SourceCommit)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = 'trung-via/torrent-tv-vietsub'
$wf = "$repo/.github/workflows/g4-v3-signed-release-manual.yml@refs/heads/main"
$ompPin = '52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f'
$subPin = '6ba6edd39f5d986ddfae29b5425b8ac0b319844e'
$gradlePin = 'd0c7a13bf8ad5108e4b82d5bbac8ffd7d522b429'
$debugCert = '8BF6937801524FD7C264B55855BB35A213C242114FB66B5FA9F1907E334FD84'
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or
    $env:GITHUB_REPOSITORY -cne $repo -or $env:GITHUB_WORKFLOW_REF -cne $wf -or
    $env:GITHUB_REF -cne 'refs/heads/main' -or $env:GITHUB_ACTOR -cne 'trung-via' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or $env:RUNNER_OS -cne 'Windows' -or
    $env:G4_CONFIRMATION -cne 'SIGN_G4_V3_RELEASE_ONCE' -or
    $SourceCommit -notmatch '^[0-9a-f]{40}$' -or $SourceCommit -cne $env:GITHUB_SHA) {
    throw 'G4B1_STOP_UNAPPROVED_RUNNER_WORKFLOW_OR_SOURCE'
}
$root = [IO.Path]::GetFullPath('C:\TOOL\TorrentTV-Runner\_work').TrimEnd('\') + '\'
foreach ($name in @('GITHUB_WORKSPACE','RUNNER_TEMP','RUNNER_WORKSPACE','GITHUB_RUN_ID','GITHUB_RUN_ATTEMPT')) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) { throw 'G4B1_STOP_RUNNER_METADATA' }
    if ($name -in @('GITHUB_WORKSPACE','RUNNER_TEMP','RUNNER_WORKSPACE')) {
        if (-not ([IO.Path]::GetFullPath($value).TrimEnd('\') + '\').StartsWith(
            $root,[StringComparison]::OrdinalIgnoreCase)) { throw 'G4B1_STOP_OUTSIDE_RUNNER' }
    }
}
$AppRepoRoot = (Resolve-Path -LiteralPath $AppRepoRoot).Path
if (-not $AppRepoRoot.Equals((Resolve-Path -LiteralPath $env:GITHUB_WORKSPACE).Path,
    [StringComparison]::OrdinalIgnoreCase)) { throw 'G4B1_STOP_WRONG_CHECKOUT' }
$head = (& git -C $AppRepoRoot rev-parse HEAD | Out-String).Trim()
$dirty = @(& git -C $AppRepoRoot status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $head -cne $SourceCommit -or $dirty.Count -ne 0) {
    throw 'G4B1_STOP_DIRTY_OR_UNPINNED_CHECKOUT'
}
$font = @{
    'poc/vi-font/apply.mjs' = '0159dc864948240a27a35c9ac447c658a66405d9'
    'poc/vi-font/apply.test.mjs' = '2925f8221329957c26d6d574304bf0aa235ae43e'
    'poc/vi-font/verify.mjs' = 'f54dfdef8a73937a2d9efc3a0b07dea66678892b'
}
foreach ($item in $font.GetEnumerator()) {
    $blob = (& git -C $AppRepoRoot rev-parse "HEAD:$($item.Key)" | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $blob -cne $item.Value) {
        throw 'G4B1_STOP_V3_TESTED_BLOB_DRIFT'
    }
}
Write-Host 'G4B1_TRUSTED_SOURCE_PASS'

# No creation of signing keys; no secrets in repository, log, npm or source checkout.
$names = @('G4_RELEASE_KEYSTORE_FILE','G4_RELEASE_KEYSTORE_PASSWORD',
           'G4_RELEASE_KEY_ALIAS','G4_RELEASE_KEY_PASSWORD','G4_RELEASE_CERT_SHA256')
$signing = @{}
foreach ($name in $names) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) { throw 'G4B1_BLOCKED_SIGNING_NOT_PROVISIONED' }
    $signing[$name] = $value
}
foreach ($name in $names) { Remove-Item -Path ("Env:" + $name) -ErrorAction SilentlyContinue }
foreach ($name in @('ANDROID_KEYSTORE_FILE','ANDROID_KEYSTORE_PASSWORD',
                    'ANDROID_KEY_ALIAS','ANDROID_KEY_PASSWORD')) {
    Remove-Item -Path ("Env:" + $name) -ErrorAction SilentlyContinue
}
$fingerprint = ($signing['G4_RELEASE_CERT_SHA256'] -replace '[:\s]','').ToUpperInvariant()
if ($fingerprint -notmatch '^[A-F0-9]{64}$' -or $fingerprint -ceq $debugCert -or
    $signing['G4_RELEASE_KEY_ALIAS'] -ceq 'androiddebugkey') {
    throw 'G4B1_BLOCKED_RELEASE_SIGNER_NOT_APPROVED'
}
$key = $signing['G4_RELEASE_KEYSTORE_FILE']
if (-not [IO.Path]::IsPathRooted($key) -or -not (Test-Path -LiteralPath $key -PathType Leaf)) {
    throw 'G4B1_BLOCKED_KEYSTORE_UNAVAILABLE'
}
$key = (Resolve-Path -LiteralPath $key).Path
if ($key.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFileName($key).Equals('debug.keystore',[StringComparison]::OrdinalIgnoreCase)) {
    throw 'G4B1_BLOCKED_DEBUG_OR_WORKSPACE_KEYSTORE'
}
$node = 'C:\Program Files\nodejs'
$sdk = 'C:\TOOL\Android-SDK'
$javaRoot = 'C:\Program Files\Eclipse Adoptium'
function Get-Jdk([string]$prefix) {
    Get-ChildItem -LiteralPath $javaRoot -Directory |
        Where-Object { $_.Name -like "$prefix*" -and
            (Test-Path -LiteralPath (Join-Path $_.FullName 'bin\javac.exe') -PathType Leaf) } |
        Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
}
$j21 = Get-Jdk 'jdk-21'
$j17 = Get-Jdk 'jdk-17'
if (-not $j21 -or -not $j17 -or
    -not (Test-Path -LiteralPath (Join-Path $node 'node.exe') -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path $sdk 'platforms\android-37.0\android.jar') -PathType Leaf)) {
    throw 'G4B1_BLOCKED_TOOLCHAIN_MISSING'
}
$env:JAVA_HOME = $j21
$env:JAVA_HOME_17_X64 = $j17
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:PATH = "$node;$(Join-Path $j21 'bin');$sdk\platform-tools;$env:PATH"
$cache = Join-Path $env:RUNNER_WORKSPACE '_omp-fast-cache'
$env:GRADLE_USER_HOME = Join-Path $cache 'gradle'
$env:NPM_CONFIG_CACHE = Join-Path $cache 'npm'
New-Item -ItemType Directory -Force -Path $env:GRADLE_USER_HOME,$env:NPM_CONFIG_CACHE | Out-Null
$props = Join-Path $env:GRADLE_USER_HOME 'gradle.properties'
$setting = 'org.gradle.java.installations.fromEnv=JAVA_HOME_17_X64'
$prior = @()
if (Test-Path -LiteralPath $props -PathType Leaf) {
    $prior = @(Get-Content -LiteralPath $props | Where-Object { $_ -match '^\s*org\.gradle\.java\.installations\.fromEnv\s*=' })
}
if ($prior.Count -gt 1 -or ($prior.Count -eq 1 -and $prior[0].Trim() -cne $setting)) {
    throw 'G4B1_STOP_JDK_GRADLE_SETTING_CONFLICT'
}
if ($prior.Count -eq 0) { Add-Content -LiteralPath $props -Value $setting -Encoding ascii }
$work = Join-Path $env:RUNNER_TEMP ("p1-g1-prod-g4signed-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT")
if (Test-Path -LiteralPath $work) { throw 'G4B1_STOP_TEMP_CLONE_EXISTS' }
$created = $false
try {
    & git -c core.longpaths=true clone --no-checkout https://github.com/spacesarmat/omp.git $work
    $created = Test-Path -LiteralPath $work
    if ($LASTEXITCODE -ne 0) { throw 'G4B1_BLOCKED_CLONE' }
    & git -C $work checkout --detach $ompPin
    if ($LASTEXITCODE -ne 0) { throw 'G4B1_BLOCKED_OMP_CHECKOUT' }
    & git -C $work -c core.longpaths=true submodule update --init --recursive
    if ($LASTEXITCODE -ne 0) { throw 'G4B1_BLOCKED_2160_SUBMODULE' }
    $omp = (& git -C $work rev-parse HEAD | Out-String).Trim()
    $sub = (& git -C (Join-Path $work 'android\vendor\2160player') rev-parse HEAD | Out-String).Trim()
    $gradle = (& git -C $work hash-object -- 'android/app/build.gradle' | Out-String).Trim()
    if ($omp -cne '52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f' -or
        $sub -cne '6ba6edd39f5d986ddfae29b5425b8ac0b319844e' -or
        $gradle -cne 'd0c7a13bf8ad5108e4b82d5bbac8ffd7d522b429') {
        throw 'G4B1_STOP_UPSTREAM_OR_SIGNING_GUARD_DRIFT'
    }
    & (Join-Path $AppRepoRoot 'poc\g1-prod\apply.ps1') -OmpRoot $work -AppRepoRoot $AppRepoRoot
    if (-not $?) { throw 'G4B1_STOP_G1_SOURCE' }
    & (Join-Path $AppRepoRoot 'poc\g1-prod\verify.ps1') -OmpRoot $work
    if (-not $?) { throw 'G4B1_STOP_G1_VERIFY' }
    $nodeExe = Join-Path $node 'node.exe'
    & $nodeExe (Join-Path $AppRepoRoot 'poc\p2-source\omp-ui\apply.mjs') $work
    if ($LASTEXITCODE -ne 0) { throw 'G4B1_STOP_P2_SOURCE' }
    & $nodeExe --test (Join-Path $AppRepoRoot 'poc\vi-font\apply.test.mjs')
    if ($LASTEXITCODE -ne 0) { throw 'G4B1_STOP_V3_TEST' }
    & $nodeExe (Join-Path $AppRepoRoot 'poc\vi-font\apply.mjs') $work
    if ($LASTEXITCODE -ne 0) { throw 'G4B1_STOP_V3_SOURCE' }
    & $nodeExe (Join-Path $AppRepoRoot 'poc\vi-font\verify.mjs') $work
    if ($LASTEXITCODE -ne 0) { throw 'G4B1_STOP_V3_VERIFY' }
    Write-Host 'G4B1_COMPOSED_G1_P2_FONT_V3_SOURCE_PASS'
    Push-Location $work
    try {
        & npm.cmd ci --no-audit --no-fund
        if ($LASTEXITCODE -ne 0) { throw 'G4B1_BLOCKED_NPM' }
        & npx.cmd vitest run tests/sources/tvCandidateCheck.test.ts
        if ($LASTEXITCODE -ne 0) { throw 'G4B1_BLOCKED_P2_TEST' }
        & npm.cmd run android:sync
        if ($LASTEXITCODE -ne 0) { throw 'G4B1_BLOCKED_CAPACITOR_SYNC' }
    } finally { Pop-Location }
    Push-Location (Join-Path $work 'android')
    try {
        & .\gradlew.bat testDebugUnitTest --no-daemon --console plain
        if ($LASTEXITCODE -ne 0) { throw 'G4B1_BLOCKED_GRADLE_UNIT' }
        $env:ANDROID_KEYSTORE_FILE = $key
        $env:ANDROID_KEYSTORE_PASSWORD = $signing['G4_RELEASE_KEYSTORE_PASSWORD']
        $env:ANDROID_KEY_ALIAS = $signing['G4_RELEASE_KEY_ALIAS']
        $env:ANDROID_KEY_PASSWORD = $signing['G4_RELEASE_KEY_PASSWORD']
        try {
            & .\gradlew.bat assembleRelease --no-daemon --console plain
            if ($LASTEXITCODE -ne 0) { throw 'G4B1_BLOCKED_ASSEMBLE_RELEASE' }
        } finally {
            foreach ($name in @('ANDROID_KEYSTORE_FILE','ANDROID_KEYSTORE_PASSWORD','ANDROID_KEY_ALIAS','ANDROID_KEY_PASSWORD')) {
                Remove-Item -Path ("Env:" + $name) -ErrorAction SilentlyContinue
            }
        }
    } finally { Pop-Location }
    $apkDir = Join-Path $work 'android\app\build\outputs\apk\release'
    $auditArgs = @{ ApkDirectory = $apkDir; ExpectedCertSha256 = $fingerprint; AndroidSdk = $sdk }
    $out = @(& (Join-Path $AppRepoRoot 'poc\g4\audit-v3-apk.ps1') @auditArgs)
    if (-not $?) { throw 'G4B2_BLOCKED_BINARY_AUDIT' }
    $hashes = @($out | Where-Object { $_ -match '^SHA256=[a-f0-9]{64}$' })
    if ($hashes.Count -lt 2) { throw 'G4B2_STOP_RELEASE_CHECKSUMS_NOT_PRODUCED' }
    @(
        '## Private G4 Signed Release binary audit',
        'Status: G4B2_SIGNED_RELEASE_BINARY_VERIFIED_NOT_TV_PASS',
        "Source: $SourceCommit",
        "OMP: $ompPin",
        "2160player: $subPin",
        "Run: $env:GITHUB_RUN_ID",
        'APK private and ephemeral; deleted with disposable clone',
        'Signer certificate matched approved fingerprint (not printed)'
    ) + $hashes | Out-File -LiteralPath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    Write-Host 'G4B2_SIGNED_RELEASE_BINARY_VERIFIED_NOT_TV_PASS'
} finally {
    foreach ($name in @('ANDROID_KEYSTORE_FILE','ANDROID_KEYSTORE_PASSWORD','ANDROID_KEY_ALIAS','ANDROID_KEY_PASSWORD')) {
        Remove-Item -Path ("Env:" + $name) -ErrorAction SilentlyContinue
    }
    if ($created -and (Test-Path -LiteralPath $work)) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host 'G4B1_PRIVATE_APK_AND_TEMP_SOURCE_CLEANUP_ATTEMPTED'
    }
}
