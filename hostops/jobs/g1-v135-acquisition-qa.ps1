# Read-only source test; no provider, browser, Owner, ADB, TV or cache effects.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or $env:RUNNER_OS -cne 'Windows'){throw 'TRUSTED_RUNNER_REQUIRED'}
$root=$env:GITHUB_WORKSPACE
$expected='7927eee0b5b26bacc27c1973aaeef9d3f116a62b'
$parent=(& git -C $root rev-parse HEAD^).Trim()
if($LASTEXITCODE -ne 0 -or $parent -cne $expected){throw 'QA_SOURCE_DRIFT'}
$changes=@(& git -C $root diff --name-only $expected HEAD)
if($LASTEXITCODE -ne 0 -or $changes.Count -ne 1 -or $changes[0] -cne 'hostops/jobs/g1-v135-acquisition-qa.ps1'){throw 'QA_DIFF_DRIFT'}
$env:PYTHONDONTWRITEBYTECODE='1'
$env:PYTHONPATH=@((Join-Path $root 'poc\p2-sub-discovery'),(Join-Path $root 'poc\p2-aisub'),(Join-Path $root 'poc\p3-vietsub-trigger')) -join ';'
Push-Location (Join-Path $root 'poc\p2-sub-discovery')
try {
  & python -B -m unittest -v test_agy_v13_browser_evidence test_agy_v13_native_producer
  if($LASTEXITCODE -ne 0){throw 'G1_V135_QA_FAIL'}
}finally{Pop-Location}
Write-Output ('G1_V135_EXACT_SOURCE_OFFLINE_QA_PASS='+$expected)
