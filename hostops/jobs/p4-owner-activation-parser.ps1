# Exact-source P3/P4 interactive owner activation parser checks only.
# No access to the logged-in owner's profile, pairing, media, task, API or LAN.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_ACTIONS -cne 'true') {
    throw 'P4_OWNER_ACTIVATION_PARSER_WRONG_RUNNER'
}
$expected = @{
    'poc/p2-sub-discovery/activate-owner-p3-p4.ps1' = 'f1127c7df3fdb0d7cee458f6eb55251dfbc14eb3'
    'poc/p2-sub-discovery/owner_p3_p4_entrypoint.py' = '693301bf2959c74d16dae949820729de2e91c7c8'
    'poc/p2-sub-discovery/install-owner-session-bridge.ps1' = '1f100887f0f592eec614ca6ab61768bac84cd67d'
    'poc/p2-sub-discovery/test_owner_p3_p4_private_bootstrap.py' = '2b4f8d6304bc5dfec9c4de5e9381b1680ce72461'
}
foreach ($item in $expected.GetEnumerator()) {
    $sha = (& git rev-parse ("HEAD:" + $item.Key) | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $sha -cne $item.Value) {
        throw 'P4_OWNER_ACTIVATION_PARSER_SOURCE_DRIFT'
    }
}
foreach ($path in @(
    'poc/p2-sub-discovery/activate-owner-p3-p4.ps1',
    'poc/p2-sub-discovery/start-owner-session-agent.ps1',
    'poc/p2-sub-discovery/install-owner-session-bridge.ps1'
)) {
    $tokens=$null; $errors=$null
    $file=Join-Path $env:GITHUB_WORKSPACE $path
    [void][System.Management.Automation.Language.Parser]::ParseFile(
       $file,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) { throw 'P4_OWNER_ACTIVATION_POWERSHELL_PARSE_FAILED' }
}
Write-Host 'P4_OWNER_ACTIVATION_POWERSHELL_PARSE=PASS'
$python='C:\Program Files\Python314\python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw 'P4_OWNER_ACTIVATION_PYTHON_MISSING'
}
$env:PYTHONPATH = (Join-Path $env:GITHUB_WORKSPACE 'poc\p2-sub-discovery') + ';' +
    (Join-Path $env:GITHUB_WORKSPACE 'poc\p2-aisub') + ';' +
    (Join-Path $env:GITHUB_WORKSPACE 'poc\p3-vietsub-trigger')
$env:PYTHONDONTWRITEBYTECODE='1'
& $python -m unittest -q test_owner_p3_p4_private_bootstrap
if ($LASTEXITCODE -ne 0) { throw 'P4_OWNER_ACTIVATION_PYTHON_ENTRYPOINT_TEST_FAIL' }
Write-Host 'P4_OWNER_ACTIVATION_PYTHON_ENTRYPOINT_TEST=PASS'
Write-Host 'P4_OWNER_ACTIVATION_REAL_USER_INSTALL=NOT_RUN'
Write-Host 'P4_OWNER_ACTIVATION_REAL_LAN_PROVIDER_TV=NOT_RUN'
