# Exact-PR162 source canary on the dedicated Windows runner.
# One signed P3/V3/P4 pipeline through owner rights-pinned stream-only source.
# Real localhost OS socket, synthetic TV/VI/ffp metadata only. No LAN listener,
# private media, device write, provider, owner's DPAPI or credentials.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_ACTIONS -cne 'true') {
    throw 'P4_STREAM_ONLY_UNTRUSTED_WINDOWS_RUNNER'
}
$blobs = @{
    'poc/p2-sub-discovery/test_owner_torrserver_ffp_tracks.py' = '13b5209f9eec671a9c594426db3e3bc8b37007fb'
    'poc/p2-sub-discovery/test_p3_owner_p4_single_pipeline_socket.py' = '6cfea02f64c8f384d33f07bc0ac84a8defdb4a7a'
    'poc/p2-sub-discovery/test_owner_p3_p4_private_bootstrap.py' = 'de269a53e926c07e848110de70f05ff24760c1b1'
}
foreach ($path in $blobs.Keys) {
    $blob = (& git rev-parse ('HEAD:' + $path) | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $blob -cne $blobs[$path]) {
        throw 'P4_STREAM_ONLY_SOURCE_BLOB_DRIFT'
    }
}
$python = 'C:\Program Files\Python314\python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw 'P4_STREAM_ONLY_OWNER_PYTHON_NOT_FOUND'
}
$env:PYTHONPATH = (Join-Path $env:GITHUB_WORKSPACE 'poc\p2-sub-discovery') + ';' +
    (Join-Path $env:GITHUB_WORKSPACE 'poc\p2-aisub') + ';' +
    (Join-Path $env:GITHUB_WORKSPACE 'poc\p3-vietsub-trigger')
$env:PYTHONDONTWRITEBYTECODE = '1'
Write-Host 'P4_STREAM_ONLY_MODE=EXACT_SOURCE_WINDOWS_LOOPBACK_SYNTHETIC'
& $python -m unittest -v test_owner_torrserver_ffp_tracks test_p3_owner_p4_single_pipeline_socket test_owner_p3_p4_private_bootstrap
if ($LASTEXITCODE -ne 0) {
    throw 'P4_STREAM_ONLY_P3_V3_D1_P2_P4_WINDOWS_PIPELINE_FAIL'
}
Write-Host 'P4_STREAM_ONLY_P3_V3_D1_P2_P4_WINDOWS_PIPELINE_PASS'
Write-Host 'P4_STREAM_ONLY_NO_REAL_TV_NO_LAN_NO_PROVIDER_NO_OWNER_SECRET'
