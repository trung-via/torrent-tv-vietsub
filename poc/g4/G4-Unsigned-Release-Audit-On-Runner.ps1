# Manual G4 forensic build. Unsigned APK; never install, sign or publish.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$AppRepoRoot,
      [Parameter(Mandatory=$true)][string]$SourceCommit)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = 'trung-via/torrent-tv-vietsub'
$branch = 'refs/heads/poc/p1a-g4-unsigned-release-audit-20261027'
$path = '.github/workflows/p1-g1d-ux-pr29-manual.yml'
$ompPin = '52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f'
$playerPin = '6ba6edd39f5d986ddfae29b5425b8ac0b319844e'
$gradleBlob = 'd0c7a13bf8ad5108e4b82d5bbac8ffd7d522b429'
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or
    $env:GITHUB_REPOSITORY -cne $repo -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $env:GITHUB_REF -cne $branch -or
    $env:GITHUB_WORKFLOW_REF -cne ($repo + '/' + $path + '@' + $branch)) {
    throw 'STOP: incorrect runner, repository, branch or workflow'
}
foreach ($key in @('ANDROID_KEYSTORE_FILE','ANDROID_KEYSTORE_PASSWORD','ANDROID_KEY_ALIAS','ANDROID_KEY_PASSWORD')) {
    if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($key))) {
        throw 'STOP: signing environment must be empty for forensic audit'
    }
}
foreach ($key in @('GITHUB_WORKSPACE','RUNNER_WORKSPACE','RUNNER_TEMP','GITHUB_RUN_ID','GITHUB_RUN_ATTEMPT')) {
    if (-not [Environment]::GetEnvironmentVariable($key)) { throw 'STOP: missing runner metadata' }
}
$base = [IO.Path]::GetFullPath('C:\TOOL\TorrentTV-Runner\_work').TrimEnd('\') + '\'
foreach ($dir in @($env:GITHUB_WORKSPACE,$env:RUNNER_WORKSPACE,$env:RUNNER_TEMP)) {
    if (-not ([IO.Path]::GetFullPath($dir).TrimEnd('\') + '\').StartsWith(
        $base,[StringComparison]::OrdinalIgnoreCase)) { throw 'STOP: workspace is not isolated' }
}
$AppRepoRoot = (Resolve-Path -LiteralPath $AppRepoRoot).Path
$head = (& git -C $AppRepoRoot rev-parse HEAD | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $SourceCommit -notmatch '^[0-9a-f]{40}$' -or
    $head -cne $SourceCommit) { throw 'STOP: audited app source commit mismatch' }
$dirty = @(& git -C $AppRepoRoot status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'STOP: audited app source dirty' }
foreach ($p in @(
    @('poc/g1c/P1G1CSubtitleRegistry.debug.kt','39a0e5b552a73840d0fb67d998a86b28b76a66cd'),
    @('poc/g1c/P1G1CSubtitleRegistry.release.kt','3215c2b6c53bf2b6d77090cdcd03b62fbbf020fd'),
    @('poc/g1c/apply.ps1','15ec09812ef3d3153ccf4c936655ab1ecff020aa'),
    @('poc/g1c/verify.ps1','2bebdcc1d4b00bd5fe66a692e4712cbd802b01be')
)) {
    $blob = (& git -C $AppRepoRoot hash-object -- $p[0] | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $blob -cne $p[1]) { throw 'STOP: pinned PR29 input drift' }
}
Write-Host 'G4_PR29_SOURCE_BLOBS_PASS'
$node = 'C:\Program Files\nodejs'
$sdk = 'C:\TOOL\Android-SDK'
$adoptium = 'C:\Program Files\Eclipse Adoptium'
function Find-Jdk([string]$prefix) {
    Get-ChildItem -LiteralPath $adoptium -Directory | Where-Object {
        $_.Name -like "$prefix*" -and (Test-Path (Join-Path $_.FullName 'bin\javac.exe')) } |
        Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
}
$j21 = Find-Jdk 'jdk-21'
$j17 = Find-Jdk 'jdk-17'
$analyzer = "$sdk\cmdline-tools\latest\bin\apkanalyzer.bat"
$buildToolsRoot = Join-Path $sdk 'build-tools'
if (-not (Test-Path -LiteralPath $buildToolsRoot -PathType Container)) {
    throw 'BLOCKED: Android SDK build-tools directory missing'
}
$signerCandidates = @(Get-ChildItem -LiteralPath $buildToolsRoot -Directory -ErrorAction Stop |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat') -PathType Leaf } |
    Sort-Object Name -Descending)
if ($signerCandidates.Count -lt 1) {
    throw 'BLOCKED: apksigner.bat missing from installed Android SDK build-tools'
}
$signer = Join-Path $signerCandidates[0].FullName 'apksigner.bat'
$checks = @(
    @{ Name='NODE'; Path=(Join-Path $node 'node.exe'); Kind='Leaf' },
    @{ Name='JDK21'; Path=$j21; Kind='Container' },
    @{ Name='JDK17'; Path=$j17; Kind='Container' },
    @{ Name='APK_ANALYZER'; Path=$analyzer; Kind='Leaf' },
    @{ Name='APK_SIGNER'; Path=$signer; Kind='Leaf' },
    @{ Name='ANDROID_37_JAR'; Path=(Join-Path $sdk 'platforms\android-37.0\android.jar'); Kind='Leaf' }
)
foreach ($item in $checks) {
    if (-not $item.Path -or -not (Test-Path -LiteralPath $item.Path -PathType $item.Kind)) {
        throw ('BLOCKED: G4 prerequisite ' + $item.Name + ' missing or wrong file type')
    }
    Write-Host ('G4_PREREQ_' + $item.Name + '_PASS')
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
$omp = Join-Path $env:RUNNER_TEMP "p1-g1c-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT"
if (Test-Path -LiteralPath $omp) { throw 'STOP: test worktree already exists' }
& git -c core.longpaths=true clone --no-checkout https://github.com/spacesarmat/omp.git $omp
if ($LASTEXITCODE -ne 0) { throw 'BLOCKED: clone failed' }
& git -C $omp checkout --detach $ompPin
if ($LASTEXITCODE -ne 0) { throw 'BLOCKED: OMP checkout failed' }
& git -C $omp -c core.longpaths=true submodule update --init --recursive
if ($LASTEXITCODE -ne 0) { throw 'BLOCKED: submodule checkout failed' }
if ((& git -C $omp rev-parse HEAD | Out-String).Trim() -cne $ompPin -or
    (& git -C (Join-Path $omp 'android\vendor\2160player') rev-parse HEAD | Out-String).Trim() -cne $playerPin) {
    throw 'STOP: upstream/source commit drift'
}
& (Join-Path $AppRepoRoot 'poc\g1c\apply.ps1') -OmpRoot $omp -AppRepoRoot $AppRepoRoot
if (-not $?) { throw 'STOP: G1d source apply failed' }
& (Join-Path $AppRepoRoot 'poc\g1c\verify.ps1') -OmpRoot $omp
if (-not $?) { throw 'STOP: G1d source verify failed' }
$props = Join-Path $env:GRADLE_USER_HOME 'gradle.properties'
$setting = 'org.gradle.java.installations.fromEnv=JAVA_HOME_17_X64'
$existing = @()
if (Test-Path -LiteralPath $props -PathType Leaf) {
    $existing = @(Get-Content -LiteralPath $props |
        Where-Object { $_ -match '^\s*org\.gradle\.java\.installations\.fromEnv\s*=' })
}
if ($existing.Count -gt 1 -or ($existing.Count -eq 1 -and $existing[0].Trim() -cne $setting)) {
    throw 'STOP: dedicated Gradle JDK config conflict'
}
if ($existing.Count -eq 0) { Add-Content -LiteralPath $props -Value $setting -Encoding ascii }
Push-Location $omp
try {
    & npm.cmd ci --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw 'BLOCKED: npm ci failed' }
    & npm.cmd run android:sync
    if ($LASTEXITCODE -ne 0) { throw 'BLOCKED: android:sync failed' }
} finally { Pop-Location }
# The ONE approved deviation: omit the pinned release-task signing-key
# throw, without substituting a key or touching variant source sets.
$gradleFile = Join-Path $omp 'android\app\build.gradle'
$blob = (& git -C $omp hash-object -- 'android/app/build.gradle' | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $blob -cne $gradleBlob) {
    throw 'STOP: Gradle signing policy baseline SHA mismatch'
}
$src = [IO.File]::ReadAllText($gradleFile)
$regex = '(?m)^            \} else \{\r?\n                gradle\.taskGraph\.whenReady \{ graph ->\r?\n                    if \(graph\.allTasks\.any \{ it\.name\.toLowerCase\(\)\.contains\(''release''\) && it\.project == project \}\) \{\r?\n                        throw new GradleException\(''[^\r\n]*''\)\r?\n                    \}\r?\n                \}\r?\n            \}'
$hits = [regex]::Matches($src,$regex)
if ($hits.Count -ne 1 -or -not $src.Contains('signingConfig signingConfigs.release')) {
    throw 'STOP: release signing guard anchor not unique'
}
$replacement = "            } else { // G4_UNSIGNED_AUDIT_EXCEPTION_ONLY" + [Environment]::NewLine + "            }"
$edited = $src.Replace($hits[0].Value,$replacement)
if ($edited -ceq $src -or $edited.Contains('gradle.taskGraph.whenReady')) {
    throw 'STOP: unsigned build exception failed'
}
[IO.File]::WriteAllText($gradleFile,$edited,([Text.UTF8Encoding]::new($false)))
& git -C $omp diff --check
if ($LASTEXITCODE -ne 0) { throw 'STOP: diff whitespace check failed' }
$diff = @(& git -C $omp diff -- 'android/app/build.gradle')
$additions = @($diff | Where-Object { $_ -match '^\+[^+]' })
if ($LASTEXITCODE -ne 0 -or $additions.Count -ne 1 -or
    $additions[0] -notmatch 'G4_UNSIGNED_AUDIT_EXCEPTION_ONLY') {
    throw 'STOP: exception changed more than one Gradle line'
}
Write-Host 'G4_ONE_DISPOSABLE_SIGNING_GUARD_EXCEPTION_PASS'
Push-Location (Join-Path $omp 'android')
try {
    & .\gradlew.bat assembleRelease --no-daemon --console plain
    if ($LASTEXITCODE -ne 0) { throw 'BLOCKED: unsigned assembleRelease failed' }
} finally { Pop-Location }
Write-Host 'G4_ASSEMBLE_RELEASE_UNSIGNED_PASS_NOT_G4_BINARY_PASS'
$out = Join-Path $omp 'android\app\build\outputs\apk\release'
$apks = @(Get-ChildItem -LiteralPath $out -Filter '*.apk' -File -ErrorAction Stop)
if ($apks.Count -lt 1 -or $apks.Count -gt 4) { throw 'STOP: release APK count unexpected' }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Run-Tool([string]$exe,[string[]]$arguments) {
    $old = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $lines = @(& $exe @arguments 2>&1)
        $status = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    return @{ Status=$status; Output=($lines | Out-String).Trim() }
}
$forbidden = @('p1-g1-external.vi.srt','p1-vietsub-utf8.srt','p1-g1c.register',
    'p1-g1c-subtitles','P1 G1c - Saved SRT')
$hashLines = @()
$report = @('G4_UNSIGNED_AUDIT_NOT_PRODUCTION_RELEASE',
    "source_sha=$SourceCommit","omp_sha=$ompPin","submodule_sha=$playerPin",
    "run_id=$env:GITHUB_RUN_ID","runner=$env:RUNNER_NAME",
    'signing_guard_exception=only_in_disposable_clone')
foreach ($apk in $apks) {
    $sha = (Get-FileHash -LiteralPath $apk.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $hashLines += "$sha  $($apk.Name)"
    $zip = [IO.Compression.ZipFile]::OpenRead($apk.FullName)
    try {
        $dexCount = 0
        foreach ($e in $zip.Entries) {
            if ($e.FullName -match '(?i)^assets/.*(p1-g1|p1-vietsub|g1c)' -or
                $e.FullName -match '(?i)^META-INF/.*\.(RSA|DSA|EC)$') {
                throw 'STOP: debug asset or legacy signing material in release APK'
            }
            if ($e.FullName -match '^classes\d*\.dex$') {
                $dexCount++
                $stream = $e.Open()
                $memory = New-Object IO.MemoryStream
                try {
                    $stream.CopyTo($memory)
                    $dex = [Text.Encoding]::UTF8.GetString($memory.ToArray())
                    foreach ($word in $forbidden) {
                        if ($dex.Contains($word)) {
                            throw 'STOP: debug-only registry/label/file string in release DEX'
                        }
                    }
                } finally { $memory.Dispose(); $stream.Dispose() }
            }
        }
        if ($dexCount -eq 0) { throw 'STOP: release APK contains no DEX' }
    } finally { $zip.Dispose() }
    $debug = Run-Tool $analyzer @('manifest','debuggable',$apk.FullName)
    $app = Run-Tool $analyzer @('manifest','application-id',$apk.FullName)
    if ($debug.Status -ne 0 -or $debug.Output -cne 'false' -or
        $app.Status -ne 0 -or $app.Output -cne 'com.spacesarmat.omp') {
        throw 'STOP: wrong release package or debuggable flag'
    }
    $bytecode = Run-Tool $analyzer @('dex','code','--class',
        'com.spacesarmat.omp.player.P1G1CSubtitleRegistry',$apk.FullName)
    if ($bytecode.Status -ne 0 -or $bytecode.Output -notmatch 'prepare' -or
        $bytecode.Output -notmatch 'noteTrackChoice' -or
        $bytecode.Output -match 'getSharedPreferences|getFilesDir|java/io/File|FileInputStream') {
        throw 'STOP: cannot prove compiled release helper is no-op'
    }
    $sig = Run-Tool $signer @('verify','--verbose',$apk.FullName)
    if ($sig.Status -eq 0 -or
        $sig.Output -notmatch '(?i)does not verify|not signed|no signature|no certificates') {
        throw 'STOP: audit artifact not provably unsigned'
    }
    $report += "apk=$($apk.Name);sha256=$sha;release_binary_no_debug=pass;unsigned=pass"
}
$hashLines | Out-File -LiteralPath (Join-Path $out 'SHA256SUMS-G4.txt') -Encoding ascii
$report | Out-File -LiteralPath (Join-Path $out 'G4-UNSIGNED-AUDIT-EVIDENCE.txt') -Encoding utf8
Write-Host 'G4_UNSIGNED_AUDIT_BINARY_INSPECTION_PASS'
Write-Host 'G4_UNSIGNED_ARTIFACT_ONLY_NOT_PRODUCTION_OR_TV_PASS'
