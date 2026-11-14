# P3→Owner V3→P2(VI/EN offline fixture)→P4 complete-pipeline canary.
# Executes one real local HTTP socket (127.0.0.1:0) and production HMAC
# Python handler; no real ADB/TV, LAN, firewall, paid model or provider access.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_ACTIONS -cne 'true') {
    throw 'P4_MAIN_PIPELINE_WRONG_WINDOWS_RUNNER'
}
$expectedParent = '09c957da143b0255a1375d20d110badde6c68373'
$parent = (& git rev-parse 'HEAD^' | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $parent -cne $expectedParent) {
    throw 'P4_MAIN_PIPELINE_UNEXPECTED_PR162_SOURCE_PARENT'
}
$root = $env:GITHUB_WORKSPACE
$pythonExe = 'C:\Program Files\Python314\python.exe'
if (-not (Test-Path -LiteralPath $pythonExe -PathType Leaf)) {
    throw 'P4_MAIN_PIPELINE_WINDOWS_PYTHON314_UNAVAILABLE'
}
$env:PYTHONPATH = (Join-Path $root 'poc\p2-sub-discovery') + ';' +
    (Join-Path $root 'poc\p2-aisub') + ';' +
    (Join-Path $root 'poc\p3-vietsub-trigger') + ';' +
    (Join-Path $root 'poc\p3-p4-compose')
$env:PYTHONDONTWRITEBYTECODE = '1'
Write-Host 'P4_MAIN_PIPELINE_SCOPE=REAL_WINDOWS_LOOPBACK_SOCKET_SYNTHETIC_TV_AND_PROVIDER'
Write-Host 'P4_MAIN_PIPELINE_SOURCE_PR162=09c957da143b0255a1375d20d110badde6c68373'
$testFiles = @(
    'poc/p2-sub-discovery/test_p3_owner_p4_single_pipeline_socket.py',
    'poc/p2-sub-discovery/test_p3_p4_ready_wiring.py',
    'poc/p2-sub-discovery/test_p3_p4_verified_ready.py'
)
foreach ($path in $testFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $path) -PathType Leaf)) {
        throw 'P4_MAIN_PIPELINE_TEST_FILE_MISSING'
    }
}
& $pythonExe -m unittest -v test_p3_owner_p4_single_pipeline_socket
if ($LASTEXITCODE -ne 0) { throw 'P4_MAIN_PIPELINE_SIGNED_SOCKET_FLOW_FAILED' }
Write-Host 'P4_MAIN_PIPELINE_SIGNED_SOCKET_FLOW_PASS'
& $pythonExe -m unittest -v test_p3_p4_ready_wiring test_p3_p4_verified_ready
if ($LASTEXITCODE -ne 0) { throw 'P4_MAIN_PIPELINE_EXISTING_OWNER_LEAN120_FINAL_FEED_FAILED' }
Write-Host 'P4_MAIN_PIPELINE_EXISTING_OWNER_VI_EN_COMPLETION_PASS'
Write-Host 'P4_MAIN_PIPELINE_WINDOWS_INTEGRATION_PASS_NOT_REAL_REDMi_OR_LIVE_PROVIDER'
