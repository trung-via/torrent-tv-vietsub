# Exact PR #178 ARM32 APK install on already paired Redmi via trusted HostOps.
# The ONLY device mutation is adb install -r (no uninstall, -d, clear or reboot).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $sid -cne 'S-1-5-20') {
    throw 'TV_SIDE178_TRUSTED_WINDOWS_RUNNER_REQUIRED'
}
$source = '4cb525edc0c527ddbdfacb425774228571c5b75d'
$expected = 'c63cbedd59c4227fa03a214886cb5e3c07797d757faa14220e5dee0ee8ef72db'
$pkg = 'com.spacesarmat.omp.test'
$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
$toolsRoot = 'C:\TOOL\Android-SDK\build-tools'
$root = [IO.Path]::GetFullPath('C:\TOOL\TorrentTV-Runner\_work').TrimEnd('\') + '\'
$workspace = [IO.Path]::GetFullPath($env:RUNNER_WORKSPACE).TrimEnd('\') + '\'
if (-not $workspace.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'TV_SIDE178_RUNNER_WORKSPACE_OUTSIDE_TRUSTED_ROOT'
}
$folder = Join-Path $env:RUNNER_WORKSPACE ('_omp-fast-cache\p4-flat-staged\' + $source)
$apk = Join-Path $folder 'app-armeabi-v7a-debug.apk'
$receipt = Join-Path $folder 'stage-receipt.txt'
foreach ($file in @($apk,$receipt)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or
        ((Get-Item -LiteralPath $file -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'TV_SIDE178_STAGE_FILE_MISSING_OR_LINK'
    }
}
if ((Get-Item -LiteralPath $apk).Length -lt 5000000 -or
    (Get-Item -LiteralPath $apk).Length -gt 600000000 -or
    (Get-Item -LiteralPath $receipt).Length -gt 1024) {
    throw 'TV_SIDE178_STAGE_SIZE_UNEXPECTED'
}
$hash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hash -cne $expected) { throw 'TV_SIDE178_APK_HASH_NOT_EXACT_BUILD' }
$lines = @(Get-Content -LiteralPath $receipt -ErrorAction Stop)
foreach ($pair in @('schema=TTV-P4-FLAT-APK-STAGE-V1',
                   ('app_commit=' + $source),
                   'variant=app-armeabi-v7a-debug.apk',
                   ('sha256=' + $expected),
                   'device_installed=no')) {
    if (@($lines | Where-Object { $_ -ceq $pair }).Count -ne 1) {
        throw 'TV_SIDE178_STAGE_RECEIPT_INVALID'
    }
}
Write-Output 'TV_SIDE178_EXACT_STAGED_APK_VERIFIED'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf) -or
    -not (Test-Path -LiteralPath $toolsRoot -PathType Container)) {
    throw 'TV_SIDE178_ANDROID_TOOLS_UNAVAILABLE'
}
$buildTools = @(Get-ChildItem -LiteralPath $toolsRoot -Directory | Where-Object {
    (Test-Path -LiteralPath (Join-Path $_.FullName 'aapt.exe') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat') -PathType Leaf)
} | Sort-Object Name -Descending)
if ($buildTools.Count -eq 0) { throw 'TV_SIDE178_SIGNER_TOOLS_MISSING' }
$aapt = Join-Path $buildTools[0].FullName 'aapt.exe'
$signer = Join-Path $buildTools[0].FullName 'apksigner.bat'
$certParser = Join-Path $env:GITHUB_WORKSPACE 'poc\p4-auto-sub\cert-parser.ps1'
if (-not (Test-Path -LiteralPath $certParser -PathType Leaf)) {
    throw 'TV_SIDE178_CERT_PARSER_MISSING'
}
. $certParser
if (@(Get-Process -Name adb -ErrorAction SilentlyContinue).Count -eq 0) {
    throw 'TV_SIDE178_NO_EXISTING_ADB_PAIRING_SERVER'
}
$scratch = Join-Path $env:RUNNER_TEMP ('tv-sidecar-178-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($scratch) | Out-Null
try {
    function CallAdb([string[]]$arguments) {
        $out = Join-Path $scratch 'adb-out.txt'
        $err = Join-Path $scratch 'adb-err.txt'
        $p = Start-Process -FilePath $adb -ArgumentList $arguments -Wait -NoNewWindow `
            -PassThru -RedirectStandardOutput $out -RedirectStandardError $err -ErrorAction Stop
        return @{ code=[int]$p.ExitCode; lines=@(Get-Content -LiteralPath $out -ErrorAction Stop) }
    }
    $devices = CallAdb @('devices')
    if ($devices.code -ne 0) { throw 'TV_SIDE178_ADB_DEVICES_FAILED' }
    $authorized = @($devices.lines | Where-Object { $_ -match '^[^\s]+\s+device(\s|$)' })
    $unusable = @($devices.lines | Where-Object { $_ -match '^[^\s]+\s+(unauthorized|offline)(\s|$)' })
    if ($authorized.Count -ne 1 -or $unusable.Count -ne 0) {
        throw 'TV_SIDE178_NO_UNIQUE_AUTHORIZED_REDMi'
    }
    $serial = ([string]$authorized[0]).Trim().Split()[0]
    function DeviceProp([string]$name) {
        $value = CallAdb @('-s',$serial,'shell','getprop',$name)
        if ($value.code -ne 0 -or $value.lines.Count -ne 1) {
            throw 'TV_SIDE178_DEVICE_PROPERTY_UNAVAILABLE'
        }
        return ([string]$value.lines[0]).Trim()
    }
    if ((DeviceProp 'ro.product.model') -cne 'MiTV-ASTR0' -or
        (DeviceProp 'ro.product.cpu.abi') -cne 'armeabi-v7a' -or
        (DeviceProp 'ro.build.version.sdk') -cne '30') {
        throw 'TV_SIDE178_DEVICE_IDENTITY_MISMATCH'
    }
    Write-Output 'TV_SIDE178_REDMi_ABI_API_VERIFIED'
    $remote = CallAdb @('-s',$serial,'shell','pm','path',$pkg)
    $basePaths = @($remote.lines | Where-Object { $_ -match '^package:/[^ \t\r\n]+/base\.apk$' })
    if ($remote.code -ne 0 -or $basePaths.Count -ne 1) {
        throw 'TV_SIDE178_INSTALLED_PACKAGE_NOT_FOUND'
    }
    $before = Join-Path $scratch 'installed-before.apk'
    $pulled = CallAdb @('-s',$serial,'pull',([string]$basePaths[0]).Trim().Substring(8),$before)
    if ($pulled.code -ne 0 -or -not (Test-Path -LiteralPath $before -PathType Leaf)) {
        throw 'TV_SIDE178_CANNOT_READ_EXISTING_APK'
    }
    function PkgInfo([string]$file) {
        $badge = @(& $aapt dump badging $file 2>$null)
        $pLine = @($badge | Where-Object { $_ -match '^package: name=' })
        if ($LASTEXITCODE -ne 0 -or $pLine.Count -ne 1 -or
            $pLine[0] -notmatch "name='([^']+)' versionCode='([0-9]+)'") {
            throw 'TV_SIDE178_PACKAGE_IDENTITY_UNREADABLE'
        }
        return @{ name=$Matches[1]; version=[long]::Parse($Matches[2]) }
    }
    function Cert([string]$file) {
        $text = @(& $signer verify --verbose --print-certs $file 2>$null)
        if ($LASTEXITCODE -ne 0) { throw 'TV_SIDE178_SIGNATURE_INVALID' }
        return [string](Get-P4SingleSignerDigest -Lines $text)
    }
    $current = PkgInfo $before
    $candidate = PkgInfo $apk
    if ($current.name -cne $pkg -or $candidate.name -cne $pkg -or
        $candidate.version -lt $current.version) {
        throw 'TV_SIDE178_PACKAGE_OR_VERSION_MISMATCH'
    }
    if ((Cert $before) -cne (Cert $apk)) {
        throw 'TV_SIDE178_SIGNATURE_MISMATCH_KEEP_APP_AND_DATA'
    }
    Write-Output 'TV_SIDE178_PACKAGE_AND_SIGNER_VERIFIED'
    if ((Get-FileHash -LiteralPath $before -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $expected) {
        Write-Output 'TV_SIDE178=ALREADY_INSTALLED_EXACT_APK'
        return
    }
    $installation = CallAdb @('-s',$serial,'install','-r',$apk)
    if ($installation.code -ne 0 -or
        @($installation.lines | Where-Object { ([string]$_).Trim() -ceq 'Success' }).Count -ne 1) {
        throw 'TV_SIDE178_ADB_REPLACE_FAILED_KEEP_DATA'
    }
    $remoteAfter = CallAdb @('-s',$serial,'shell','pm','path',$pkg)
    $afterBases = @($remoteAfter.lines | Where-Object { $_ -match '^package:/[^ \t\r\n]+/base\.apk$' })
    if ($remoteAfter.code -ne 0 -or $afterBases.Count -ne 1) {
        throw 'TV_SIDE178_POST_APK_PATH_UNVERIFIED'
    }
    $installedAfter = Join-Path $scratch 'installed-after.apk'
    $afterPull = CallAdb @('-s',$serial,'pull',([string]$afterBases[0]).Trim().Substring(8),$installedAfter)
    if ($afterPull.code -ne 0 -or -not (Test-Path -LiteralPath $installedAfter -PathType Leaf) -or
        (Get-FileHash -LiteralPath $installedAfter -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected) {
        throw 'TV_SIDE178_POST_APK_HASH_NOT_VERIFIED'
    }
    Write-Output 'TV_SIDE178=INSTALLED_APK_HASH_VERIFIED_DATA_PRESERVED'
    Write-Output 'TV_SIDE178=LIVE_SUBTITLE_NOT_TESTED'
} finally {
    if (Test-Path -LiteralPath $scratch -PathType Container) {
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}
