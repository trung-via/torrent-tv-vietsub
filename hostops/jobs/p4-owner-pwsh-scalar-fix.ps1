# Windows exact source test: no owner file access, no TaskScheduler writes.
# Reproduces scalar [string] parameter binding that failed on owner desktop.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_ACTIONS -cne 'true') { throw 'P4_OWNER_PWSH_SCALAR_WRONG_RUNNER' }
$expected = @{
'poc/p2-sub-discovery/owner-task-action-identity.ps1'='f7ab32b54e17deba92c83b167c1c6a17e269eea2'
'poc/p2-sub-discovery/activate-owner-p3-p4.ps1'='372550b3c3cde93c21d0da174221ff09c3bfe1ad'
'poc/p2-sub-discovery/install-owner-session-bridge.ps1'='7ad94afc03786e8b470f0e1df6721e75f56780fe'
'poc/p2-sub-discovery/test-owner-task-action-identity.ps1'='3b6d8fee74085c36fa4280bca9af071d1f89cedf'
'poc/p2-sub-discovery/test_owner_activation_powershell_automatic_variables.py'='6e708cccd54422d1e54a72b1029fb4b5393b0c33'
}
foreach ($item in $expected.GetEnumerator()) {
 $v=(& git rev-parse ("HEAD:"+$item.Key) | Out-String).Trim()
 if ($LASTEXITCODE -ne 0 -or $v -cne $item.Value) {
   throw 'P4_OWNER_PWSH_SCALAR_BLOB_DRIFT'
 }
}
foreach ($name in @(
'poc/p2-sub-discovery/owner-task-action-identity.ps1',
'poc/p2-sub-discovery/activate-owner-p3-p4.ps1',
'poc/p2-sub-discovery/install-owner-session-bridge.ps1',
'poc/p2-sub-discovery/test-owner-task-action-identity.ps1'
)) {
 $t=$null;$errors=$null
 [void][System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $env:GITHUB_WORKSPACE $name),[ref]$t,[ref]$errors)
 if($errors.Count -ne 0){throw 'P4_OWNER_PWSH_SCALAR_PARSE_FAILED'}
}
. (Join-Path $env:GITHUB_WORKSPACE 'poc/p2-sub-discovery/owner-task-action-identity.ps1')
$resolved = Get-TTVOwnerCurrentPwshExecutable
if ($resolved -isnot [string] -or
    [string]::IsNullOrWhiteSpace($resolved) -or
    -not [IO.Path]::IsPathRooted($resolved) -or
    -not [IO.File]::Exists($resolved)) {
 throw 'P4_OWNER_PWSH_SCALAR_INVALID'
}
# Exactly the invocation shape of the owner failure; synthetic task only.
$fakeScript = [IO.Path]::GetFullPath(
    (Join-Path $env:TEMP 'synthetic\start-owner-session-agent.ps1'))
$fake = [pscustomobject]@{Actions=@([pscustomobject]@{
 Execute=$resolved;Arguments=('-NoLogo -NoProfile -NonInteractive -File "'+$fakeScript+'"');
 WorkingDirectory=''
})}
$answer=Get-TTVOwnerTaskActionState -Task $fake -ExpectedExecutable $resolved -ExpectedLauncher $fakeScript
if (-not $answer.Accepted) { throw 'P4_OWNER_PWSH_SCALAR_BINDING_OR_ACTION_FAILED' }
Write-Host 'P4_OWNER_PWSH_SCALAR_BINDING=PASS'
& (Join-Path $env:GITHUB_WORKSPACE 'poc/p2-sub-discovery/test-owner-task-action-identity.ps1')
if ($LASTEXITCODE -ne 0) { throw 'P4_OWNER_PWSH_SCALAR_ACTION_REGRESSION_FAIL' }
$py='C:\Program Files\Python314\python.exe'
if(-not(Test-Path -LiteralPath $py -PathType Leaf)){throw 'P4_OWNER_PWSH_SCALAR_PYTHON_MISSING'}
$env:PYTHONPATH=(Join-Path $env:GITHUB_WORKSPACE 'poc\p2-sub-discovery')+';'+
 (Join-Path $env:GITHUB_WORKSPACE 'poc\p2-aisub')+';'+
 (Join-Path $env:GITHUB_WORKSPACE 'poc\p3-vietsub-trigger')
$env:PYTHONDONTWRITEBYTECODE='1'
& $py -m unittest -q test_owner_activation_powershell_automatic_variables test_owner_p3_p4_private_bootstrap
if ($LASTEXITCODE -ne 0){throw 'P4_OWNER_PWSH_SCALAR_PYTHON_REGRESSION_FAIL'}
Write-Host 'P4_OWNER_PWSH_SCALAR_WINDOWS_ALL_PASS'
Write-Host 'P4_OWNER_LIVE_TASK_LAN_TV_UNTOUCHED=TRUE'
