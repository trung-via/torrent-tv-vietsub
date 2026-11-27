# Read-only source test; no provider, browser, Owner, ADB, TV or cache effects.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or $env:RUNNER_OS -cne 'Windows'){throw 'TRUSTED_RUNNER_REQUIRED'}
$root=$env:GITHUB_WORKSPACE
$expected='b0e0cba86a09a7353c416536088d666363f3676c'
# HostOps uses a depth-one checkout. Verify the complete candidate source subtree directly.
$actual=(& git -C $root rev-parse HEAD:poc).Trim()
if($LASTEXITCODE -ne 0 -or $actual -cne 'c085bbb67ebfaa72dcb66b2dcbeb2d952aa930b3'){throw 'QA_SOURCE_TREE_DRIFT'}
$env:PYTHONDONTWRITEBYTECODE='1'
$env:PYTHONPATH=@((Join-Path $root 'poc\p2-sub-discovery'),(Join-Path $root 'poc\p2-aisub'),(Join-Path $root 'poc\p3-vietsub-trigger')) -join ';'
Push-Location (Join-Path $root 'poc\p2-sub-discovery')
try {
  & 'C:\Program Files\Python314\python.exe' -B -m unittest -v test_agy_v13_browser_evidence test_agy_v13_native_producer
  if($LASTEXITCODE -ne 0){throw 'G1_V135_QA_FAIL'}
}finally{Pop-Location}
Write-Output ('G1_V135_EXACT_SOURCE_OFFLINE_QA_PASS='+$expected)
