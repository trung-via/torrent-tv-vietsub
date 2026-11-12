# Owner-only read-only morphology check of Android Debug APK signer output.
# No media, private app data, package install, cloud upload or account secrets.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = 'trung-via/torrent-tv-vietsub'
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_EVENT_NAME -cne 'pull_request' -or
    $env:GITHUB_REPOSITORY -cne $repo -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:GITHUB_HEAD_REF -cne 'feature/p4-native-auto-sub-g2-20261111' -or
    $env:GITHUB_BASE_REF -cne 'feature/g2-refresh-vietsub-inplace-20261111' -or
    $env:GITHUB_REF -cne 'refs/pull/120/merge') {
    throw 'P4_SIGNER_MORPH_STOP_OWNER_IDENTITY'
}
if (-not $env:GITHUB_EVENT_PATH -or -not (Test-Path -LiteralPath $env:GITHUB_EVENT_PATH -PathType Leaf)) {
    throw 'P4_SIGNER_MORPH_STOP_EVENT_MISSING'
}
$eventData=Get-Content -LiteralPath $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json
if ([int]$eventData.number -ne 120 -or
    $eventData.pull_request.head.repo.full_name -cne $repo -or
    $eventData.pull_request.user.login -cne 'trung-via' -or
    $eventData.pull_request.head.ref -cne $env:GITHUB_HEAD_REF -or
    $eventData.pull_request.head.sha -cne $env:GITHUB_SHA) {
    throw 'P4_SIGNER_MORPH_STOP_PR_IDENTITY'
}
$root = 'C:\TOOL\TorrentTV-Runner\_work\'
if (-not $env:RUNNER_TEMP -or
    -not ([IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\')+'\').StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'P4_SIGNER_MORPH_STOP_RUNNER_TEMP'
}
$adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf) -or
    @(Get-Process -Name adb -ErrorAction SilentlyContinue).Count -lt 1) {
    throw 'P4_SIGNER_MORPH_STOP_ADB_NOT_RUNNING'
}
$devices=@(& $adb devices 2>$null)
$authorized=@($devices | Where-Object { $_ -match '^[^\s]+\s+device(\s|$)' })
if ($LASTEXITCODE -ne 0 -or $authorized.Count -ne 1 -or
    @($devices | Where-Object { $_ -match '^[^\s]+\s+(offline|unauthorized)(\s|$)' }).Count -ne 0) {
    throw 'P4_SIGNER_MORPH_STOP_ONE_DEVICE_REQUIRED'
}
$serial=($authorized[0].Trim() -split '\s+')[0]
$props=@{}
foreach ($key in @('ro.product.model','ro.build.version.sdk','ro.product.cpu.abi')) {
    $p=@(& $adb -s $serial shell getprop $key 2>$null)
    if ($LASTEXITCODE -ne 0 -or $p.Count -ne 1) {throw 'P4_SIGNER_MORPH_STOP_PROPS'}
    $props[$key]=([string]$p[0]).Trim()
}
if ($props['ro.product.model'] -cne 'MiTV-ASTR0' -or
    $props['ro.build.version.sdk'] -cne '30' -or
    $props['ro.product.cpu.abi'] -cne 'armeabi-v7a') {
    throw 'P4_SIGNER_MORPH_STOP_TV_IDENTITY_CHANGED'
}
$paths=@(& $adb -s $serial shell pm path com.spacesarmat.omp.test 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'P4_SIGNER_MORPH_STOP_NO_DEBUG_APP' }
$base=@($paths | Where-Object { ([string]$_).Trim() -match '^package:/[^\s]+/base\.apk$' })
if ($base.Count -ne 1) {throw 'P4_SIGNER_MORPH_STOP_DEBUG_BASE_PATH'}
$remote=([string]$base[0]).Trim().Substring(8)
$dir=Join-Path $env:RUNNER_TEMP ('p4-signer-morph-'+$env:GITHUB_RUN_ID+'-'+$env:GITHUB_RUN_ATTEMPT)
if (Test-Path -LiteralPath $dir) {throw 'P4_SIGNER_MORPH_STOP_TEMP_REUSE'}
New-Item -ItemType Directory -Path $dir | Out-Null
try {
    $installed=Join-Path $dir 'installed-base.apk'
    $stdout=Join-Path $dir 'pull-out.txt'
    $stderr=Join-Path $dir 'pull-err.txt'
    $proc=Start-Process -FilePath $adb -ArgumentList @('-s',$serial,'pull',$remote,$installed) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if ($proc.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $installed -PathType Leaf)) {
        throw 'P4_SIGNER_MORPH_STOP_PULL_FAILED'
    }
    $sdk='C:\TOOL\Android-SDK\build-tools'
    $versions=@(Get-ChildItem -LiteralPath $sdk -Directory | Where-Object {
        Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat') -PathType Leaf
    } | Sort-Object Name -Descending)
    if ($versions.Count -lt 1) {throw 'P4_SIGNER_MORPH_STOP_TOOL_NOT_FOUND'}
    $tool=Join-Path $versions[0].FullName 'apksigner.bat'
    $lines=@(& $tool verify --verbose --print-certs $installed 2>$null)
    if ($LASTEXITCODE -ne 0) {throw 'P4_SIGNER_MORPH_STOP_APK_VERIFY_FAILED'}
    Write-Host ('P4_SIGNER_MORPH_LINE_COUNT='+$lines.Count)
    for ($i=0;$i -lt $lines.Count;$i++) {
        $s=[string]$lines[$i]
        $containsSigner=$s.IndexOf('Signer',[StringComparison]::OrdinalIgnoreCase) -ge 0
        $startsSigner=$s -match '(?i)^\s*Signer'
        $firstCode=if ($s.Length -gt 0) { [int][char]$s[0] } else { 0 }
        $kind=if ($s -match '(?i)^\s*Verified') {'VERIFIED'} elseif ($s -match '(?i)^\s*Verifies') {'VERIFIES'} elseif ($s -match '(?i)^\s*Number of') {'COUNT'} elseif ($containsSigner) {'SIGNER_CONTAINS'} else {'OTHER'}
        $head=if ($containsSigner) {
            $p=($s -split ':',2)[0].Trim()
            if ($p -match '^(?i:Signer\s*#\s*[0-9]+\s+certificate\s+[A-Za-z0-9 \-]{1,65})$') { $p } else { 'UNRECOGNIZED_SIGNER_PREFIX' }
        } else { 'NO_SIGNER_PREFIX' }
        Write-Host ('P4_SIGNER_MORPH_LINE_'+$i+'='+$kind+';starts='+$startsSigner+';length='+$s.Length+';first_char_code='+$firstCode+';prefix='+$head)
    }
    Write-Host 'P4_SIGNER_MORPH_READ_ONLY_COMPLETE_NO_INSTALL'
} finally {
    if (Test-Path -LiteralPath $dir) {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
$global:LASTEXITCODE=0
