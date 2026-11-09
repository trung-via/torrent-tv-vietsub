# G4-B2: audit signed Release APK files, no publication or installation.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ApkDirectory,
    [Parameter(Mandatory=$true)][string]$ExpectedCertSha256,
    [Parameter(Mandatory=$true)][string]$AndroidSdk
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$debugCert = '8BF6937801524FD7C264B55855BB35A213C242114FB66B5FA9F1907E334FD84'
$expected = ($ExpectedCertSha256 -replace '[:\s]','').ToUpperInvariant()
if ($expected -notmatch '^[0-9A-F]{64}$' -or $expected -ceq $debugCert) {
    throw 'G4B2_STOP_APPROVED_SIGNER_NOT_ESTABLISHED'
}
$buildTools = @(Get-ChildItem -LiteralPath (Join-Path $AndroidSdk 'build-tools') -Directory |
    Where-Object {
        (Test-Path -LiteralPath (Join-Path $_.FullName 'aapt2.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat') -PathType Leaf)
    } | Sort-Object Name -Descending)
if ($buildTools.Count -eq 0) { throw 'G4B2_STOP_ANDROID_BUILD_TOOLS_MISSING' }
$aapt2 = Join-Path $buildTools[0].FullName 'aapt2.exe'
$apksigner = Join-Path $buildTools[0].FullName 'apksigner.bat'
$apks = @(Get-ChildItem -LiteralPath $ApkDirectory -Filter '*.apk' -File -ErrorAction Stop)
if ($apks.Count -lt 2 -or $apks.Count -gt 5) { throw 'G4B2_STOP_RELEASE_APK_COUNT' }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$arm32 = $false
$results = @()
foreach ($apk in $apks) {
    $badging = @(& $aapt2 dump badging $apk.FullName 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'G4B2_STOP_BADGING_FAILED' }
    $text = $badging -join [Environment]::NewLine
    if ($text -notmatch "(?m)^package: name='com\.spacesarmat\.omp'" -or
        $text -match '(?m)^application-debuggable') {
        throw 'G4B2_STOP_BAD_PACKAGE_OR_DEBUGGABLE'
    }
    $signature = @(& $apksigner verify --verbose --print-certs $apk.FullName 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'G4B2_STOP_APKSIGNER_FAILED' }
    $matches = @([regex]::Matches(($signature -join [Environment]::NewLine),
        '(?im)Signer #\d+ certificate SHA-256 digest:\s*([0-9a-f:]{64,95})'))
    if ($matches.Count -ne 1) { throw 'G4B2_STOP_NOT_ONE_RELEASE_SIGNER' }
    $actual = ($matches[0].Groups[1].Value -replace ':','').ToUpperInvariant()
    if ($actual -cne $expected -or $actual -ceq $debugCert) {
        throw 'G4B2_STOP_RELEASE_SIGNER_MISMATCH'
    }
    $zip = [IO.Compression.ZipFile]::OpenRead($apk.FullName)
    try {
        $entries = @($zip.Entries | ForEach-Object { $_.FullName })
        if (@($entries | Where-Object { $_ -match '(?i)(p1-g1-external\.vi\.srt|p1-vietsub-utf8\.srt|p1-g1c\.register)' }).Count -gt 0) {
            throw 'G4B2_STOP_DEBUG_FIXTURE_IN_RELEASE'
        }
        if (@($entries | Where-Object { $_ -like 'lib/armeabi-v7a/*' }).Count -gt 0) { $arm32 = $true }
        $dexFiles = @($zip.Entries | Where-Object { $_.FullName -match '^classes\d*\.dex$' })
        if ($dexFiles.Count -eq 0) { throw 'G4B2_STOP_MISSING_DEX' }
        $hasG1 = $false
        foreach ($entry in $dexFiles) {
            $inputStream = $entry.Open()
            $memory = New-Object System.IO.MemoryStream
            try {
                $inputStream.CopyTo($memory)
                $dexString = [Text.Encoding]::ASCII.GetString($memory.ToArray())
                if ($dexString.Contains('P1ProductionSubtitles')) { $hasG1 = $true }
                if ($dexString.Contains('P1G1CSubtitleRegistry') -or
                    $dexString.Contains('P1G0SubtitleProbe')) {
                    throw 'G4B2_STOP_DEBUG_HOOK_IN_DEX'
                }
            } finally { $memory.Dispose(); $inputStream.Dispose() }
        }
        if (-not $hasG1) { throw 'G4B2_STOP_G1_HELPER_NOT_IN_RELEASE_DEX' }
    } finally { $zip.Dispose() }
    $sha = (Get-FileHash -LiteralPath $apk.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $results += "SHA256=$sha"
}
if (-not $arm32) { throw 'G4B2_STOP_ARM32_ABI_ABSENT' }
Write-Host 'G4B2_RELEASE_MANIFEST_ABI_DEX_AND_SIGNATURE_PASS'
Write-Host 'G4B2_RELEASE_BINARY_VERIFIED_NOT_TV_PASS'
# Public workflow summary contains only checksums; never keystore data or signed APK.
return $results
