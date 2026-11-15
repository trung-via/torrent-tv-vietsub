# Validate semantic P4 Owner TaskScheduler action and no-copy-on-conflict
# on dedicated Windows runner. Pure fixtures only; never inspect/modify
# actual user's task, DPAPI, media, pairing, LAN, or TV.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_ACTIONS -cne 'true') {
    throw 'P4_TASK_ACTION_TEST_WRONG_RUNNER'
}
$blobs = @{
 'poc/p2-sub-discovery/owner-task-action-identity.ps1' = 'c74643fec39ae316370614eab04a2f44a95ce55b'
 'poc/p2-sub-discovery/test-owner-task-action-identity.ps1' = '47ceab448ee5274a6bf47afb80b2d79aebedb018'
 'poc/p2-sub-discovery/activate-owner-p3-p4.ps1' = '25497b1eef057e79063f1868afc7b0149ba97341'
 'poc/p2-sub-discovery/install-owner-session-bridge.ps1' = 'ed23934f4250dd408dbb50d45e77f8ab1dc79b29'
 'poc/p2-sub-discovery/test_owner_activation_powershell_automatic_variables.py' = '0e2aa4f8dab444eed03817bb56ccc1a15ec881e8'
}
foreach($item in $blobs.GetEnumerator()){
    $got=(& git rev-parse ("HEAD:"+$item.Key) | Out-String).Trim()
    if($LASTEXITCODE -ne 0 -or $got -cne $item.Value){
        throw 'P4_TASK_ACTION_SOURCE_BLOB_DRIFT'
    }
}
foreach($relative in @(
 'poc/p2-sub-discovery/owner-task-action-identity.ps1',
 'poc/p2-sub-discovery/test-owner-task-action-identity.ps1',
 'poc/p2-sub-discovery/activate-owner-p3-p4.ps1',
 'poc/p2-sub-discovery/install-owner-session-bridge.ps1')){
 $tokens=$null;$errors=$null
 [void][System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $env:GITHUB_WORKSPACE $relative),[ref]$tokens,[ref]$errors)
 if($errors.Count -ne 0){throw 'P4_TASK_ACTION_POWERSHELL_PARSE_FAILED'}
}
Write-Host 'P4_TASK_ACTION_POWERSHELL_PARSE=PASS'
& (Join-Path $env:GITHUB_WORKSPACE 'poc/p2-sub-discovery/test-owner-task-action-identity.ps1')
if($LASTEXITCODE -ne 0){throw 'P4_TASK_ACTION_REGRESSION_FAILED'}
$py='C:\Program Files\Python314\python.exe'
if(-not(Test-Path -LiteralPath $py -PathType Leaf)){throw 'P4_TASK_ACTION_PYTHON_NOT_FOUND'}
$env:PYTHONPATH=(Join-Path $env:GITHUB_WORKSPACE 'poc\p2-sub-discovery')+';'+
 (Join-Path $env:GITHUB_WORKSPACE 'poc\p2-aisub')+';'+
 (Join-Path $env:GITHUB_WORKSPACE 'poc\p3-vietsub-trigger')
$env:PYTHONDONTWRITEBYTECODE='1'
& $py -m unittest -q test_owner_activation_powershell_automatic_variables test_owner_p3_p4_private_bootstrap
if($LASTEXITCODE -ne 0){throw 'P4_TASK_ACTION_PYTHON_REGRESSION_FAILED'}
Write-Host 'P4_TASK_ACTION_WINDOWS_REGRESSION=PASS'
Write-Host 'P4_TASK_ACTION_OWNER_INSTALLED_TASK=UNTOUCHED'
Write-Host 'P4_TASK_ACTION_PRIVATE_LAN_PROVIDER_TV=NOT_RUN'
