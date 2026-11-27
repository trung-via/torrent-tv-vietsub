# Read-only source test; no provider, browser, Owner, ADB, TV or cache effects.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or $env:RUNNER_OS -cne 'Windows'){throw 'TRUSTED_RUNNER_REQUIRED'}
$root=$env:GITHUB_WORKSPACE
$expected='7927eee0b5b26bacc27c1973aaeef9d3f116a62b'
# HostOps uses a depth-one checkout. Verify the complete candidate source subtree directly.
$actual=(& git -C $root rev-parse HEAD:poc).Trim()
if($LASTEXITCODE -ne 0 -or $actual -cne '42a28031cc7fcb1caffbefbe1ba9232b4498412a'){throw 'QA_SOURCE_TREE_DRIFT'}
$env:PYTHONDONTWRITEBYTECODE='1'
$env:PYTHONPATH=@((Join-Path $root 'poc\p2-sub-discovery'),(Join-Path $root 'poc\p2-aisub'),(Join-Path $root 'poc\p3-vietsub-trigger')) -join ';'
Push-Location (Join-Path $root 'poc\p2-sub-discovery')
try {
  & python -B -m unittest -v test_agy_v13_browser_evidence test_agy_v13_native_producer
  if($LASTEXITCODE -ne 0){throw 'G1_V135_QA_FAIL'}
}finally{Pop-Location}
Write-Output ('G1_V135_EXACT_SOURCE_OFFLINE_QA_PASS='+$expected)
