# G2 Thor acceptance: transfer ONLY two copyright-free synthetic SRT files to TV Download.
# No playback, user-media inspection, network changes, uninstall/clear, root or APK install.
# Fixed new filenames, refuse overwrite. Source 120/240 cue bytes equal prior G2 fixture pack.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Stop-Test([string]$reason) { throw ('G2_THOR_FIXTURE_HOLD: ' + $reason) }

if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:GITHUB_EVENT_NAME -cne 'issue_comment' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows') {
    Stop-Test 'UNTRUSTED_HOSTOPS_CONTEXT'
}
$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) { Stop-Test 'ADB_MISSING' }
$raw = @(& $adb devices 2>&1 | ForEach-Object { "$_" })
if ($LASTEXITCODE -ne 0) { Stop-Test 'ADB_LIST_FAILED' }
$entries = @($raw | ForEach-Object {
    if ($_ -match '^(?<serial>\S+)\s+(?<status>device|unauthorized|offline|recovery|sideload)\s*$') {
        [PSCustomObject]@{ serial = $Matches['serial']; status = $Matches['status'] }
    }
})
if ($entries.Count -ne 1 -or $entries[0].status -cne 'device') {
    Stop-Test 'EXACTLY_ONE_AUTHORIZED_DEVICE_REQUIRED'
}
$serial = $entries[0].serial
function Read-Prop([string]$prop) {
    $x = @(& $adb -s $serial shell getprop $prop 2>&1)
    if ($LASTEXITCODE -ne 0) { Stop-Test 'DEVICE_PROPERTY_FAILED' }
    return ($x -join '').Trim()
}
if ((Read-Prop 'ro.product.model') -cne 'MiTV-ASTR0' -or
    (Read-Prop 'ro.product.device') -cne 'blueplanet' -or
    (Read-Prop 'ro.build.version.sdk') -cne '30' -or
    (Read-Prop 'ro.product.cpu.abilist') -cne 'armeabi-v7a,armeabi') {
    Stop-Test 'XIAOMI_TV_IDENTITY_NOT_EXPECTED'
}
$pkg = @(& $adb -s $serial shell pm path com.spacesarmat.omp.test 2>&1)
if ($LASTEXITCODE -ne 0 -or
    @($pkg | Where-Object { "$_" -match '^package:/.*\.apk\s*$' }).Count -lt 1) {
    Stop-Test 'EXPECTED_DEBUG_APP_NOT_INSTALLED'
}
$folder = '/sdcard/Download'
& $adb -s $serial shell test -d $folder | Out-Null
if ($LASTEXITCODE -ne 0) { Stop-Test 'TV_DOWNLOAD_DIR_UNAVAILABLE' }

# Decode a fixed original synthetic Unicode sentence via ASCII Base64 for PowerShell 5.1.
$cueTemplate = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(
    'S2nhu4NtIHRo4butIEEg4oCTIGPDonUgezA6MDAwfSDigJMgdGnhur9uZyBWaeG7h3QgY8OzIGThuqV1OiDEgyDDoiDDqiDDtCDGoSDGsCDEkS4='))
function Srt-Time([int]$ms) {
    return ('{0:00}:{1:00}:{2:00},{3:000}' -f 0,
        [int][Math]::Floor($ms / 60000),
        [int][Math]::Floor(($ms % 60000) / 1000),
        [int]($ms % 1000))
}
function Build-SyntheticSrt([int]$count) {
    $sb = [System.Text.StringBuilder]::new()
    for ($i = 1; $i -le $count; $i++) {
        $ms = ($i - 1) * 500
        [void]$sb.Append("$i")
        [void]$sb.Append([char]10)
        [void]$sb.Append((Srt-Time $ms) + ' --> ' + (Srt-Time ($ms + 450)))
        [void]$sb.Append([char]10)
        [void]$sb.Append(($cueTemplate -f $i))
        [void]$sb.Append([char]10)
        [void]$sb.Append([char]10)
    }
    return $sb.ToString()
}
$root = Join-Path $env:RUNNER_TEMP ('g2-thor-fixtures-' + $env:GITHUB_RUN_ID)
if (Test-Path -LiteralPath $root) { Stop-Test 'LOCAL_FIXTURE_TEMP_DIR_ALREADY_EXISTS' }
New-Item -ItemType Directory -Path $root -ErrorAction Stop | Out-Null

$fixtures = @(
    [PSCustomObject]@{
        Count=120; Name='G2-THOR-120.srt'
        Hash='75714febe98ca221aa7a41f758583e7da67a9486859d2a1f1e246cd287e9c4bc'
    },
    [PSCustomObject]@{
        Count=240; Name='G2-THOR-240.srt'
        Hash='514d0f96071a94c6053e433ee489b8ed90fe22e1402b2e3c611732020f4c0666'
    }
)
try {
    # Generate and verify BOTH exact fixture byte sequences BEFORE making any TV changes.
    foreach ($f in $fixtures) {
        $f | Add-Member -NotePropertyName Local -NotePropertyValue (Join-Path $root $f.Name)
        $f | Add-Member -NotePropertyName Remote -NotePropertyValue ($folder + '/' + $f.Name)
        [IO.File]::WriteAllText($f.Local,(Build-SyntheticSrt $f.Count),
            ([Text.UTF8Encoding]::new($false)))
        $hash = (Get-FileHash -LiteralPath $f.Local -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -cne $f.Hash) { Stop-Test ('LOCAL_FIXTURE_HASH_MISMATCH_' + $f.Count) }
    }
    Write-Host 'G2_THOR_LOCAL_SYNTHETIC_120_240_SHA256_PASS'
    # No replacement of ANY existing file. If a prior partial attempt left one of
    # these fixed files, pull it back and require the exact known SHA256.
    foreach ($f in $fixtures) {
        $existsCheck = @(& $adb -s $serial shell test -e $f.Remote 2>&1)
        $f | Add-Member -NotePropertyName AlreadyThere -NotePropertyValue ($LASTEXITCODE -eq 0)
    }
    function Invoke-ADBTransfer([string]$mode, [string]$from, [string]$to) {
        if ($mode -cnotin @('push','pull')) { Stop-Test 'UNEXPECTED_ADB_TRANSFER_MODE' }
        # adb prints successful transfer progress to stderr. PowerShell 5.1
        # wrongly raises NativeCommandError with ErrorActionPreference=Stop.
        # Run the known binary directly and inspect its exit code, not its stderr.
        $args = @('-s',$serial,$mode,$from,$to)
        $proc = Start-Process -FilePath $adb -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $root ('adb-' + $mode + '.stdout')) -RedirectStandardError (Join-Path $root ('adb-' + $mode + '.stderr'))
        if ($proc.ExitCode -ne 0) { Stop-Test ('ADB_' + $mode.ToUpperInvariant() + '_FAILED') }
    }
    foreach ($f in $fixtures) {
        if (-not $f.AlreadyThere) {
            Invoke-ADBTransfer 'push' $f.Local $f.Remote
        } else {
            Write-Host ('G2_THOR_TV_EXISTING_' + $f.Count + '_CUES_READBACK_ONLY')
        }
        $localBack = Join-Path $root ('verified-' + $f.Name)
        Invoke-ADBTransfer 'pull' $f.Remote $localBack
        if (-not (Test-Path -LiteralPath $localBack -PathType Leaf)) {
            Stop-Test ('ADB_PULL_VERIFY_FILE_MISSING_' + $f.Count)
        }
        if ((Get-FileHash -LiteralPath $localBack -Algorithm SHA256).Hash.ToLowerInvariant() -cne $f.Hash) {
            Stop-Test ('TV_FIXTURE_READBACK_SHA256_MISMATCH_' + $f.Count)
        }
        Write-Host ('G2_THOR_TV_DOWNLOAD_' + $f.Count + '_CUES_PUSH_OR_EXISTING_AND_READBACK_PASS')
    }
    Write-Host 'G2_THOR_FIXTURES_READY_SYNTHETIC_NOT_REAL_MOVIE_DIALOGUE'
    Write-Host 'G2_THOR_EXISTING_USER_FILES_UNTOUCHED_NO_APP_LAUNCH_OR_PLAYBACK'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
