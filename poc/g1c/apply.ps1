# G1c DEBUG PoC: apply only to a clean, disposable pinned OMP snapshot.
# No AIOS, global Windows changes, ADB, build or workflow execution.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$OmpRoot,
    [string]$AppRepoRoot = (Join-Path $PSScriptRoot '..\..')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ompPin = '52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f'
$playerPin = '6ba6edd39f5d986ddfae29b5425b8ac0b319844e'
$OmpRoot = (Resolve-Path -LiteralPath $OmpRoot).Path
$AppRepoRoot = (Resolve-Path -LiteralPath $AppRepoRoot).Path
if ($env:GITHUB_ACTIONS -eq 'true') {
    if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
        $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
        $env:RUNNER_OS -cne 'Windows') { throw 'STOP: wrong runner/repository' }
    if (-not $env:RUNNER_WORKSPACE -or -not $env:RUNNER_TEMP -or
        -not $env:GITHUB_RUN_ID -or -not $env:GITHUB_RUN_ATTEMPT) {
        throw 'STOP: missing runner identity'
    }
    $allowed = [IO.Path]::GetFullPath('C:\TOOL\TorrentTV-Runner\_work').TrimEnd('\') + '\'
    foreach ($candidate in @($env:RUNNER_WORKSPACE, $env:RUNNER_TEMP)) {
        $candidateRoot = [IO.Path]::GetFullPath($candidate).TrimEnd('\') + '\'
        if (-not $candidateRoot.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'STOP: outside dedicated runner workspace'
        }
    }
    $expected = [IO.Path]::GetFullPath((Join-Path $env:RUNNER_TEMP "p1-g1c-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT")).TrimEnd('\')
    if (-not [IO.Path]::GetFullPath($OmpRoot).TrimEnd('\').Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'STOP: G1c only in this run disposable clone'
    }
}
$gitRoot = (& git -C $OmpRoot rev-parse --show-toplevel)
if ($LASTEXITCODE -ne 0 -or
    -not [IO.Path]::GetFullPath($gitRoot).TrimEnd('\').Equals(
        [IO.Path]::GetFullPath($OmpRoot).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'STOP: source root mismatch'
}
$sha = (& git -C $OmpRoot rev-parse HEAD)
if ($LASTEXITCODE -ne 0 -or $sha.Trim() -cne $ompPin) { throw 'STOP: OMP SHA drift' }
$sub = (& git -C (Join-Path $OmpRoot 'android\vendor\2160player') rev-parse HEAD)
if ($LASTEXITCODE -ne 0 -or $sub.Trim() -cne $playerPin) { throw 'STOP: 2160 SHA drift' }
$dirty = @(& git -C $OmpRoot status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'STOP: dirty worktree' }
if (-not (Test-Path -LiteralPath (Join-Path $OmpRoot 'LICENSE') -PathType Leaf)) { throw 'STOP: missing license' }

$tsClient = Join-Path $OmpRoot 'src\api\torrserver.ts'
$tsNative = Join-Path $OmpRoot 'src\player\nativePlayer.ts'
$ktNative = Join-Path $OmpRoot 'android\app\src\main\java\com\spacesarmat\omp\player\NativePlayer.kt'
$ktActivity = Join-Path $OmpRoot 'android\app\src\main\java\com\spacesarmat\omp\player\PlayerActivity.kt'
$debug = Join-Path $OmpRoot 'android\app\src\debug\java\com\spacesarmat\omp\player\P1G1CSubtitleRegistry.kt'
$release = Join-Path $OmpRoot 'android\app\src\release\java\com\spacesarmat\omp\player\P1G1CSubtitleRegistry.kt'
$fromDebug = Join-Path $PSScriptRoot 'P1G1CSubtitleRegistry.debug.kt'
$fromRelease = Join-Path $PSScriptRoot 'P1G1CSubtitleRegistry.release.kt'
foreach ($f in @($tsClient,$tsNative,$ktNative,$ktActivity,$fromDebug,$fromRelease)) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "STOP: missing file: $f" }
}
foreach ($f in @($debug,$release)) {
    if (Test-Path -LiteralPath $f) { throw 'STOP: existing G1c helper' }
}
function ReplaceOnce([string]$source, [string]$old, [string]$new) {
    if (-not $source.Contains($old) -or $source.IndexOf($old) -ne $source.LastIndexOf($old)) {
        throw 'STOP: source changed or replacement anchor ambiguous'
    }
    return $source.Replace($old,$new)
}
$nl = [Environment]::NewLine

# Preflight all 4 texts before mutating the disposable worktree.
$a = [IO.File]::ReadAllText($tsClient)
$a = ReplaceOnce $a 'export interface ServerConfig {' ('export interface ServerConfig {'+$nl+'  id?: string;')
$a = ReplaceOnce $a '  readonly baseUrl: string;' ('  readonly baseUrl: string;'+$nl+'  readonly profileId?: string;')
$a = ReplaceOnce $a '    this.cfg = cfg;' ('    this.cfg = cfg;'+$nl+"    this.profileId = typeof cfg.id === 'string' && /^[A-Za-z0-9_-]{1,80}$/.test(cfg.id) ? cfg.id : undefined;")
$b = [IO.File]::ReadAllText($tsNative)
$b = ReplaceOnce $b '        return this.plugin.playNative({' ('        return this.plugin.playNative({'+$nl+'          ...(this.client?.profileId ? { serverProfileId: this.client.profileId } : {}),')
$c = [IO.File]::ReadAllText($ktNative)
$c = ReplaceOnce $c '    val testPx: Int = 0,' ('    val testPx: Int = 0,'+$nl+'    val serverProfileId: String? = null,')
$c = ReplaceOnce $c '                testPx = o.optInt("testPx", 0),' ('                testPx = o.optInt("testPx", 0),'+$nl+'                serverProfileId = o.optString("serverProfileId").ifEmpty { null },')
$d = [IO.File]::ReadAllText($ktActivity)
$d = ReplaceOnce $d '        session.load(r, next)' '        session.load(P1G1CSubtitleRegistry.prepare(this, r), next)'
$d = ReplaceOnce $d '    override fun trackChosen(choice: TrackChoice) {' ('    override fun trackChosen(choice: TrackChoice) {'+$nl+'        if (!closedSent && ::session.isInitialized) P1G1CSubtitleRegistry.noteTrackChoice(this, session.request, index(), choice)')
if ($d.Contains('P1G0SubtitleProbe') -or $d.Contains('P1G1SubtitleProbe')) {
    throw 'STOP: cannot layer G1c over G0/G1b patched player'
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($tsClient,$a,$utf8)
[IO.File]::WriteAllText($tsNative,$b,$utf8)
[IO.File]::WriteAllText($ktNative,$c,$utf8)
[IO.File]::WriteAllText($ktActivity,$d,$utf8)
foreach ($pair in @(@($fromDebug,$debug),@($fromRelease,$release))) {
    $dest = $pair[1]
    New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
    Copy-Item -LiteralPath $pair[0] -Destination $dest -ErrorAction Stop
}
& git -C $OmpRoot diff --check
if ($LASTEXITCODE -ne 0) { throw 'STOP: git diff --check failed' }
Write-Host 'G1C_SOURCE_PATCH_PREPARED; NO_COMPILE_OR_REAL_TV_PASS'
Write-Host 'Rollback: discard disposable OMP checkout.'
