# Structural guard only, not a compiler or a real-device test.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OmpRoot)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path -LiteralPath $OmpRoot).Path
$src = Join-Path $root 'android\app\src'
$activity = Get-Content -LiteralPath (Join-Path $src 'main\java\com\spacesarmat\omp\player\PlayerActivity.kt') -Raw -Encoding UTF8
$native = Get-Content -LiteralPath (Join-Path $src 'main\java\com\spacesarmat\omp\player\NativePlayer.kt') -Raw -Encoding UTF8
$debug = Get-Content -LiteralPath (Join-Path $src 'debug\java\com\spacesarmat\omp\player\P1G1CSubtitleRegistry.kt') -Raw -Encoding UTF8
$release = Get-Content -LiteralPath (Join-Path $src 'release\java\com\spacesarmat\omp\player\P1G1CSubtitleRegistry.kt') -Raw -Encoding UTF8
$client = Get-Content -LiteralPath (Join-Path $root 'src\api\torrserver.ts') -Raw -Encoding UTF8
$page = Get-Content -LiteralPath (Join-Path $root 'src\player\nativePlayer.ts') -Raw -Encoding UTF8

foreach ($entry in @(
    @($activity, 'session.load(P1G1CSubtitleRegistry.prepare(this, r), next)'),
    @($native, 'val serverProfileId: String? = null'),
    @($native, 'serverProfileId = o.optString("serverProfileId").ifEmpty { null }'),
    @($client, 'readonly profileId?: string;'),
    @($client, 'this.profileId = typeof cfg.id'),
    @($page, 'this.client?.profileId ? { serverProfileId: this.client.profileId }'),
    @($debug, 'p1-g1c.register'),
    @($debug, 'p1-g1-external.vi.srt'),
    @($debug, 'private fun key(server: String?, hash: String?, fileIndex: Int?)'),
    @($debug, 'val registrationKey = key(r.serverProfileId, current.hash, current.fileIndex)'),
    @($debug, 'prefs.edit().putString(registrationKey, checksum).commit()'),
    @($debug, 'if (prefs.getString(mediaKey, null) != currentChecksum) continue'),
    @($debug, 'if (!marker.delete()) return r'),
    @($debug, 'CodingErrorAction.REPORT')
)) {
    if (-not $entry[0].Contains($entry[1])) {
        throw "STOP: missing G1c safety guard: $($entry[1])"
    }
}
if (-not $release.Contains('PlayRequest = r') -or
    $release.Contains('getSharedPreferences') -or $release.Contains('Uri.fromFile')) {
    throw 'STOP: G1c release is not no-op'
}
foreach ($asset in @('p1-g1-external.vi.srt', 'p1-vietsub-utf8.srt')) {
    foreach ($set in @('main','debug','release')) {
        if (Test-Path -LiteralPath (Join-Path $src "$set\assets\$asset")) {
            throw "STOP: unexpected SRT in APK assets"
        }
    }
}
& git -C $root diff --check
if ($LASTEXITCODE -ne 0) { throw 'STOP: git diff --check' }
Write-Host 'G1C_STATIC_GUARDS_PASS; KOTLIN_TYPESCRIPT_BUILD_UNVERIFIED'
Write-Host 'REAL_TV_UNVERIFIED; G1C_TRACK_SELECTION_UNVERIFIED; G4_RELEASE_ARTIFACT_UNVERIFIED'
