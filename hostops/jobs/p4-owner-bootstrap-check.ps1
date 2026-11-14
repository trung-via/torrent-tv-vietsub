# Windows source-level P3/P4 owner bootstrap validation, no user secrets/TV.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_ACTIONS -cne 'true') {
    throw 'P4_OWNER_BOOTSTRAP_WRONG_RUNNER'
}
$expectedTestBlob='de269a53e926c07e848110de70f05ff24760c1b1'
$blob = (& git rev-parse 'HEAD:poc/p2-sub-discovery/test_owner_p3_p4_private_bootstrap.py' | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $blob -cne $expectedTestBlob) {
    throw 'P4_OWNER_BOOTSTRAP_UNEXPECTED_SOURCE_BLOB'
}
$root=$env:GITHUB_WORKSPACE
$python='C:\Program Files\Python314\python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw 'P4_OWNER_BOOTSTRAP_PYTHON_NOT_AVAILABLE'
}
foreach($relative in @(
  'poc\p2-sub-discovery\start-owner-session-agent.ps1',
  'poc\p2-sub-discovery\install-owner-session-bridge.ps1'
)){
    $path=Join-Path $root $relative
    $tokens=$null; $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $path,[ref]$tokens,[ref]$errors)
    if ($errors.Count -ne 0) {
        throw 'P4_OWNER_BOOTSTRAP_POWERSHELL_LAUNCHER_PARSE_FAILED'
    }
}
Write-Host 'P4_OWNER_BOOTSTRAP_EXISTING_TASK_LAUNCHER_PARSE_PASS'
$env:PYTHONPATH=(Join-Path $root 'poc\p2-sub-discovery')+';'+
   (Join-Path $root 'poc\p2-aisub')+';'+
   (Join-Path $root 'poc\p3-vietsub-trigger')
$env:PYTHONDONTWRITEBYTECODE='1'
& $python -m unittest -v test_owner_p3_p4_private_bootstrap test_owner_p3_p4_runtime test_p3_p4_ready_wiring
if ($LASTEXITCODE -ne 0) {
    throw 'P4_OWNER_BOOTSTRAP_WINDOWS_TEST_FAILED'
}
Write-Host 'P4_OWNER_BOOTSTRAP_WINDOWS_TESTS_PASS_SOURCE_ONLY'
Write-Host 'P4_OWNER_BOOTSTRAP_REAL_OWNER_TASK=NOT_EXECUTED'
Write-Host 'P4_OWNER_BOOTSTRAP_REAL_LAN=NOT_STARTED'
Write-Host 'P4_OWNER_BOOTSTRAP_REAL_PROVIDER=NOT_CALLED'
