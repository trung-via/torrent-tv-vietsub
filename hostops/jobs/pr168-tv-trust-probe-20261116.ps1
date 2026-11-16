# Read-only metadata probe after on-TV "Bật Vietsub AI" showed a send failure.
# Reads only existence of app-private preference fields through debug run-as.
# No secret values, device IDs, paths, media metadata, keys or XML are printed.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_EVENT_NAME -cne 'issue_comment' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win') {
    throw 'TTV_TRUST_PROBE_UNTRUSTED_CONTEXT'
}

$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
$pkg = 'com.spacesarmat.omp.test'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    throw 'TTV_TRUST_PROBE_ADB_NOT_FOUND'
}
$listeners = @(Get-NetTCPConnection -LocalPort 5037 -State Listen -ErrorAction SilentlyContinue)
if ($listeners.Count -eq 0) {
    Write-Host 'TTV_TRUST_ADB=NOT_RUNNING'
    exit 0
}
$rows = @(& $adb devices 2>&1 | ForEach-Object { $_.ToString() } |
    Where-Object { $_ -match '^\S+\s+device\s*$' })
if ($rows.Count -ne 1) {
    Write-Host 'TTV_TRUST_ADB=NOT_EXACT_ONE_AUTHORIZED'
    exit 0
}
$deviceId = ($rows[0] -split '\s+')[0]
Write-Host 'TTV_TRUST_ADB=EXACT_ONE_AUTHORIZED'

$runAsCheck = @(& $adb -s $deviceId shell run-as $pkg pwd 2>&1 |
    ForEach-Object { $_.ToString() })
if ($LASTEXITCODE -ne 0 -or $runAsCheck.Count -ne 1) {
    Write-Host 'TTV_TRUST_RUN_AS=UNAVAILABLE'
    exit 0
}
Write-Host 'TTV_TRUST_RUN_AS=AVAILABLE'

function Read-PrivateXml([string]$relativePath) {
    # Returns metadata strings in memory only. Command output is never logged.
    $saved = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $xmlText = @(& $adb -s $deviceId shell run-as $pkg cat $relativePath 2>&1 |
            ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $saved
    }
    if ($exitCode -ne 0) { return $null }
    return ($xmlText -join [Environment]::NewLine)
}

$pairXml = Read-PrivateXml 'shared_prefs/p4-tv-paired-pc-v2-tls.xml'
$pairState = 'PREF_FILE_NOT_FOUND_OR_UNREADABLE'
if ($null -ne $pairXml) {
    $fields = @('host', 'port', 'iv', 'sealed')
    $all = $true
    foreach ($field in $fields) {
        if ($pairXml -notmatch ('name="' + $field + '"')) { $all = $false }
    }
    $pairState = if ($all) {
        'SEALED_FIELDS_PRESENT_KEYSTORE_UNVERIFIED'
    } else { 'NO_COMPLETE_SEALED_PAIRING_FIELDS' }
}
Write-Host "TTV_TV_PAIRING_PREFERENCES=$pairState"

$p3Xml = Read-PrivateXml 'shared_prefs/p3-owner-selected-media-v1.xml'
$p3Enabled = 'PREF_FILE_NOT_FOUND_OR_UNREADABLE'
if ($null -ne $p3Xml) {
    $p3Enabled = if ($p3Xml -match 'name="owner_enabled"\s+value="true"') {
        'TRUE'
    } elseif ($p3Xml -match 'name="owner_enabled"\s+value="false"') {
        'FALSE'
    } else { 'NOT_SET' }
}
Write-Host "TTV_TV_P3_ENABLED=$p3Enabled"

$saved = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $bootstrap = @(& $adb -s $deviceId shell run-as $pkg ls 'files/p4-owner-bootstrap-v1.txt' 2>&1 |
        ForEach-Object { $_.ToString() })
    $bootstrapExit = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $saved
}
Write-Host ("TTV_TV_BOOTSTRAP_PENDING=" + $(if ($bootstrapExit -eq 0) { 'YES' } else { 'NO_OR_UNREADABLE' }))
Write-Host 'TTV_TRUST_PROBE=READ_ONLY_COMPLETE_NO_SECRET_VALUES'
