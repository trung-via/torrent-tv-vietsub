# Human-approved single diagnostic Debug font candidate build, never install on TV.
# Derived from the proven G1+P2 combined builder at reviewed main.
# HostOps owner-only branch SHA pin is verified by the default-branch workflow.
[CmdletBinding()]
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo='trung-via/torrent-tv-vietsub'
$branch='refs/heads/main'
$runnerRoot='C:\TOOL\TorrentTV-Runner\_work'
$ompPin='52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f'
$playerPin='6ba6edd39f5d986ddfae29b5425b8ac0b319844e'
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_EVENT_NAME -cne 'issue_comment' -or
    $env:GITHUB_REPOSITORY -cne $repo -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_WORKFLOW_REF -cne ($repo + '/.github/workflows/torrent-tv-hostops.yml@refs/heads/main')) {
    throw 'VI_FONT_BUILD_STOP_UNEXPECTED_HOSTOPS_CONTEXT'
}
$AppRepoRoot=$env:GITHUB_WORKSPACE
if([string]::IsNullOrWhiteSpace($AppRepoRoot)){throw 'VI_FONT_BUILD_STOP_WORKSPACE_MISSING'}
$SourceCommit=(& git -C $AppRepoRoot rev-parse HEAD | Out-String).Trim()
Write-Host 'VI_FONT_BUILD_BEGIN'
if ($SourceCommit -notmatch '^[a-f0-9]{40}$') { throw 'STOP: unpinned app source' }
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
$dirty = @(& git -C $AppRepoRoot status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) {
    throw 'STOP: app source checkout must be clean'
}
foreach ($name in @('apply.ps1','verify.ps1','P1ProductionSubtitles.kt','P1ProductionSubtitlesTest.kt')) {
    $file = Join-Path $AppRepoRoot ('poc\g1-prod\' + $name)
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw 'STOP: required G1 Production source missing'
    }
}
foreach ($file in @('apply.ps1','verify.ps1','build-on-runner.ps1')) {
    $target = Join-Path $AppRepoRoot ('poc\g1-prod\' + $file)
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $target,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count -ne 0) { throw ('STOP: PowerShell parser failed for ' + $file) }
}
Write-Host 'G1PROD_RUNNER_AND_POWERSHELL_PARSE_GUARDS_PASS'
$fontCode=Join-Path $AppRepoRoot 'poc\vi-font'
foreach($required in @('apply.mjs','verify.mjs','apply.test.mjs','README.md')){
    if(-not (Test-Path -LiteralPath (Join-Path $fontCode $required) -PathType Leaf)){
        throw 'VI_FONT_BUILD_STOP_TEST_OR_PATCH_SOURCE_MISSING'
    }
}
$nodeExe='C:\Program Files\nodejs\node.exe'
if(-not (Test-Path -LiteralPath $nodeExe -PathType Leaf)){
    throw 'VI_FONT_BUILD_STOP_NODE_NOT_FOUND'
}
& $nodeExe --check (Join-Path $fontCode 'apply.mjs')
if($LASTEXITCODE -ne 0){throw 'VI_FONT_BUILD_STOP_SOURCE_SYNTAX'}
& $nodeExe --test (Join-Path $fontCode 'apply.test.mjs')
if($LASTEXITCODE -ne 0){throw 'VI_FONT_BUILD_STOP_UNIT_TEST_FAILED'}
Write-Host 'VI_FONT_NODE_PATCH_TESTS_PASS'


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
Write-Host 'G1PROD_GUARDED_SOURCE_PATCH_PASS'
# P2 has no Android native changes. Overlay the actual OMP TV search AddScreen
# only after the proven G1 source patch. Overlay rejects unexpected dirty files.
$p2 = Join-Path $AppRepoRoot 'poc\p2-source\omp-ui'
foreach ($name in @('apply.mjs','tvCandidateCheck.ts','tvCandidateCheck.test.ts')) {
    if (-not (Test-Path -LiteralPath (Join-Path $p2 $name) -PathType Leaf)) {
        throw ('STOP: missing reviewed P2 source: ' + $name)
    }
}
& (Join-Path $node 'node.exe') --check (Join-Path $p2 'apply.mjs')
if ($LASTEXITCODE -ne 0) { throw 'STOP: P2 overlay script syntax invalid' }
& (Join-Path $node 'node.exe') (Join-Path $p2 'apply.mjs') $omp
if ($LASTEXITCODE -ne 0) { throw 'STOP: pinned P2 overlay failed' }
foreach ($check in @('src\sources\tvCandidateCheck.ts',
                     'tests\sources\tvCandidateCheck.test.ts')) {
    if (-not (Test-Path -LiteralPath (Join-Path $omp $check) -PathType Leaf)) {
        throw ('STOP: P2 source/test missing from OMP checkout: ' + $check)
    }
}
Write-Host 'G1P2_COMPOSED_SOURCE_GUARDS_PASS'
& $nodeExe (Join-Path $fontCode 'apply.mjs') $omp
if ($LASTEXITCODE -ne 0) { throw 'VI_FONT_BUILD_STOP_VLC_STYLE_APPLY' }
& $nodeExe (Join-Path $fontCode 'verify.mjs') $omp
if ($LASTEXITCODE -ne 0) { throw 'VI_FONT_BUILD_STOP_VLC_STYLE_VERIFY' }
& git -C $omp diff --check
if ($LASTEXITCODE -ne 0) { throw 'VI_FONT_BUILD_STOP_DIFF_CHECK' }
Write-Host 'VI_FONT_G1P2_VLC3_SOURCE_COMPOSITION_PASS'
if (-not ((Get-Content -LiteralPath (Join-Path $omp 'android\app\src\main\java\com\spacesarmat\omp\player\VlcRuntime.kt') -Raw) -match '(?s)--freetype-rel-fontsize=13.*--freetype-outline-thickness=1')) { throw 'VI_FONT_V2_MISSING_VERIFIED_FLAGS' }
Write-Host 'VI_FONT_V2_FONT_FLAGS_PINNED_PASS'


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
    & npx.cmd vitest run tests/sources/tvCandidateCheck.test.ts
    if ($LASTEXITCODE -ne 0) { throw 'BLOCKED: P2 UI test failed' }
    Write-Host 'G1P2_P2_VITEST_PASS'
    & npm.cmd run android:sync
    if ($LASTEXITCODE -ne 0) { throw 'BLOCKED: npm android:sync failed' }
} finally { Pop-Location }
Push-Location (Join-Path $omp 'android')
try {
    & .\gradlew.bat assembleDebug testDebugUnitTest --no-daemon --console plain
    if ($LASTEXITCODE -ne 0) { throw 'BLOCKED: Gradle assembleDebug/testDebugUnitTest failed' }
} finally { Pop-Location }
Write-Host 'G1PROD_DEBUG_BUILD_AND_UNIT_TEST_PASS_NOT_REAL_TV_PASS'

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
}
$hashes | Out-File -LiteralPath (Join-Path $dir 'SHA256SUMS-G1P2.txt') -Encoding ascii
@(
    'G1P2_COMBINED_DEBUG_BUILD_AND_UNIT_TEST_PASS',
    'NOT_REAL_TV_PASS_OR_RELEASE_PASS',
    'p2_ui=opt_in_reported_metadata_only',
    'p2_tests=vitest_eight_cases',
    'p2_overlay=guarded_pinned_upstream_add_screen',
    "app_commit=$SourceCommit",
    "omp_commit=$upstream",
    "submodule_commit=$submodule",
    "runner=$env:RUNNER_NAME",
    "run_id=$env:GITHUB_RUN_ID",
    'signing=debug_variant_only',
    'source_set=main',
    'no_adb_or_tv_install=yes',
    'G1PROD_ANDROID_PICKER_REAL_TV_UNVERIFIED',
    'G1PROD_RELEASE_BINARY_UNVERIFIED'
) | Out-File -LiteralPath (Join-Path $dir 'G1P2-BUILD-EVIDENCE.txt') -Encoding utf8
$global:LASTEXITCODE = 0
Write-Host 'G1PROD_DEBUG_APK_HASH_AND_ASSET_GUARDS_PASS'
Write-Host 'G1P2_COMBINED_DEBUG_ARTIFACT_READY_NOT_TV_OR_RELEASE_APPROVED'

# Candidate artifact private retention; do not upload APK to PUBLIC GitHub.
$parent='C:\TOOL\TorrentTV-Runner\private-artifacts\G1P2'
if(-not (Test-Path -LiteralPath $parent -PathType Container)){
    throw 'VI_FONT_BUILD_PRIVATE_VAULT_UNAVAILABLE'
}
$directory=New-Object IO.DirectoryInfo($parent)
if(($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw 'VI_FONT_BUILD_VAULT_REPARSE_DENIED'
}
$acl=$directory.GetAccessControl([Security.AccessControl.AccessControlSections]::Access)
if(-not $acl.AreAccessRulesProtected){throw 'VI_FONT_BUILD_VAULT_DACL_NOT_PROTECTED'}
$owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$allowed=@($owner,'S-1-5-18','S-1-5-32-544') | Select-Object -Unique
foreach($ace in @($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))){
    if($ace.IsInherited -or $ace.IdentityReference.Value -notin $allowed -or
        $ace.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow){
        throw 'VI_FONT_BUILD_VAULT_PERMISSIONS_NOT_EXCLUSIVE'
    }
}
$arm=Join-Path $dir 'app-armeabi-v7a-debug.apk'
if(-not (Test-Path -LiteralPath $arm -PathType Leaf)){throw 'VI_FONT_BUILD_ARM32_APK_MISSING'}
$sha=(Get-FileHash -LiteralPath $arm -Algorithm SHA256).Hash.ToLowerInvariant()
$save=Join-Path $parent ('FONT-CANDIDATE-'+$env:GITHUB_RUN_ID+'-'+$env:GITHUB_RUN_ATTEMPT)
if(Test-Path -LiteralPath $save){throw 'VI_FONT_BUILD_RETENTION_COLLISION'}
New-Item -ItemType Directory -Path $save -ErrorAction Stop | Out-Null
$stored=Join-Path $save 'app-armeabi-v7a-debug.apk'
Copy-Item -LiteralPath $arm -Destination $stored -ErrorAction Stop
if((Get-FileHash -LiteralPath $stored -Algorithm SHA256).Hash.ToLowerInvariant() -cne $sha){
    throw 'VI_FONT_BUILD_RETAINED_SHA_MISMATCH'
}
@('candidate=p1-vi-font-v2-vlc3','status=DEBUG_ONLY_NOT_TV_VERIFIED',
    ('source_commit='+$SourceCommit),('apk_sha256='+$sha),
    'libvlc=3.7.7','font=Noto Sans','font_rel_denominator=13',
    'forced_bold=false','outline_thickness=1',
    'no_device_install=true','no_public_apk=true') |
  Out-File -LiteralPath (Join-Path $save 'VI-FONT-EVIDENCE.txt') -Encoding utf8
Write-Host ('VI_FONT_PRIVATE_ARM32_DEBUG_APK_RETAINED_SHA256='+$sha)
Write-Host 'VI_FONT_NO_TV_INSTALL_NO_RELEASE_NO_PUBLIC_APK=TRUE'
$global:LASTEXITCODE=0
