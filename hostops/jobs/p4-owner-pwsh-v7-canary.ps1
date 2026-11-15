# Regression: PowerShell 5.1 runner launcher is NOT pwsh.exe 7.
# Invoke the owner's canonical executable helper only in an actual trusted
# PowerShell 7 child process. No private task, DPAPI, LAN, media, provider.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
   $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_ACTIONS -cne 'true'){
   throw 'P4_OWNER_V7_TEST_WRONG_RUNNER'
}
$expected=@{
 'poc/p2-sub-discovery/diagnose-owner-task-executable.ps1'='90c512dab791295ff7012b59df7a1a75dab867da'
 'poc/p2-sub-discovery/owner-task-action-identity.ps1'='f7ab32b54e17deba92c83b167c1c6a17e269eea2'
 'poc/p2-sub-discovery/test-owner-task-action-identity.ps1'='3b6d8fee74085c36fa4280bca9af071d1f89cedf'
}
foreach($item in $expected.GetEnumerator()){
 $b=(& git rev-parse ("HEAD:"+$item.Key) | Out-String).Trim()
 if($LASTEXITCODE -ne 0 -or $b -cne $item.Value){throw 'P4_OWNER_V7_CANARY_BLOB_DRIFT'}
}
foreach($f in $expected.Keys){
 $tok=$null;$errs=$null
 [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $env:GITHUB_WORKSPACE $f),[ref]$tok,[ref]$errs)
 if($errs.Count -ne 0){throw 'P4_OWNER_V7_POWERSHELL_SYNTAX_FAIL'}
}
Write-Host 'P4_OWNER_V7_POWERSHELL_PARSER=PASS'
$pwshFile=Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
if(-not(Test-Path -LiteralPath $pwshFile -PathType Leaf)){
    throw 'P4_OWNER_V7_BINARY_NOT_FOUND_ON_RUNNER'
}
# The test asserts the current host process is pwsh.exe; execute it explicitly.
$test=Join-Path $env:GITHUB_WORKSPACE 'poc/p2-sub-discovery/test-owner-task-action-identity.ps1'
& $pwshFile -NoLogo -NoProfile -NonInteractive -File $test
if($LASTEXITCODE -ne 0){throw 'P4_OWNER_V7_SYNTHETIC_ACTION_FAIL'}
Write-Host 'P4_OWNER_V7_CANARY_REAL_PWSH_PROCESS=PASS'
Write-Host 'P4_OWNER_REAL_SCHEDULED_TASK_READ=NO'
Write-Host 'P4_OWNER_LAN_API_TV=NOT_RUN'
