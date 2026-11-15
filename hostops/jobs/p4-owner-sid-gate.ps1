# Exact source Windows TaskScheduler canonical SID gate regression.
# Pure simulated principal tests only. No private owner files, task mutation,
# network listener, ADB, provider, media or credential access.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_ACTIONS -cne 'true') {
    throw 'P4_SID_GATE_WRONG_WINDOWS_RUNNER'
}
$blobs=@{
'poc/p2-sub-discovery/owner-task-principal-identity.ps1'='260175be6d909e1bbd51861b9663fa0f82ef1ae2'
'poc/p2-sub-discovery/test-owner-task-principal-identity.ps1'='9068e4dfef2c83136eea0aabf13a7ad447904202'
'poc/p2-sub-discovery/activate-owner-p3-p4.ps1'='32fca475ae34277021d6018d7581d95898c6e2a5'
'poc/p2-sub-discovery/install-owner-session-bridge.ps1'='730dc335f472f5e02802d5a6759f7e1124b7358b'
'poc/p2-sub-discovery/test_owner_activation_powershell_automatic_variables.py'='f20c9cbde0fe86000d1fbef90914a9dcd1504bd9'
}
foreach ($item in $blobs.GetEnumerator()) {
    $b=(& git rev-parse ("HEAD:"+$item.Key) | Out-String).Trim()
    if($LASTEXITCODE -ne 0 -or $b -cne $item.Value) {
        throw 'P4_SID_GATE_EXACT_PR162_BLOB_MISMATCH'
    }
}
foreach($path in @(
'poc/p2-sub-discovery/owner-task-principal-identity.ps1',
'poc/p2-sub-discovery/test-owner-task-principal-identity.ps1',
'poc/p2-sub-discovery/activate-owner-p3-p4.ps1',
'poc/p2-sub-discovery/install-owner-session-bridge.ps1'
)) {
  $tokens=$null;$errors=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile(
      (Join-Path $env:GITHUB_WORKSPACE $path),[ref]$tokens,[ref]$errors)
  if($errors.Count -ne 0){throw 'P4_SID_GATE_PS_PARSER_FAILED'}
}
Write-Host 'P4_OWNER_SID_POWERSHELL_PARSER=PASS'
& (Join-Path $env:GITHUB_WORKSPACE 'poc/p2-sub-discovery/test-owner-task-principal-identity.ps1')
if($LASTEXITCODE -ne 0){throw 'P4_SID_GATE_PRINCIPAL_IDENTITY_TEST_FAILED'}
$python='C:\Program Files\Python314\python.exe'
if(-not(Test-Path -LiteralPath $python -PathType Leaf)) {
    throw 'P4_SID_GATE_PYTHON_MISSING'
}
$env:PYTHONPATH=(Join-Path $env:GITHUB_WORKSPACE 'poc\p2-sub-discovery')+';'+
 (Join-Path $env:GITHUB_WORKSPACE 'poc\p2-aisub')+';'+
 (Join-Path $env:GITHUB_WORKSPACE 'poc\p3-vietsub-trigger')
$env:PYTHONDONTWRITEBYTECODE='1'
& $python -m unittest -q test_owner_activation_powershell_automatic_variables test_owner_p3_p4_private_bootstrap
if($LASTEXITCODE -ne 0){throw 'P4_SID_GATE_REGRESSION_FAILED'}
Write-Host 'P4_OWNER_SID_REGRESSION_WINDOWS=PASS'
Write-Host 'P4_OWNER_REAL_TASK_RECONFIGURED=NO'
Write-Host 'P4_OWNER_REAL_USER_LOGIN=NOT_IMPERSONATED'
Write-Host 'P4_OWNER_TV_LAN_AND_API=NOT_RUN'
