# Verify exact PR162 PowerShell variable repair on dedicated Windows runner.
# No owner profile access, task startup, install, LAN, API, or TV mutation.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_ACTIONS -cne 'true') {
    throw 'P4_HOME_FIX_UNTRUSTED_RUNNER'
}
$blobs = @{
    'poc/p2-sub-discovery/activate-owner-p3-p4.ps1' = '6790e2dc11821a2454ddb615fa91ca4303f4175a'
    'poc/p2-sub-discovery/install-owner-session-bridge.ps1' = 'd35ec4e4c5065b65363bf3c5aad5830aea339805'
    'poc/p2-sub-discovery/test_owner_activation_powershell_automatic_variables.py' = '8a8ce470d1fd3ad4bd8605ce1e082fb64a9a67c3'
}
foreach($item in $blobs.GetEnumerator()){
    $actual = (& git rev-parse ("HEAD:"+$item.Key) | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $actual -cne $item.Value) {
        throw 'P4_HOME_FIX_PR162_SOURCE_BLOB_CHANGED'
    }
}
$forbidden=@('HOME','HOST','PID','PROFILE','ERROR','TRUE','FALSE','NULL','PWD','PSVERSIONTABLE','PSCMDLET','MYINVOCATION','EXECUTIONCONTEXT')
foreach($path in @('poc/p2-sub-discovery/activate-owner-p3-p4.ps1',
                   'poc/p2-sub-discovery/install-owner-session-bridge.ps1',
                   'poc/p2-sub-discovery/start-owner-session-agent.ps1')){
    $file=Join-Path $env:GITHUB_WORKSPACE $path
    $tokens=$null;$errors=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) { throw 'P4_HOME_FIX_POWERSHELL_PARSER_FAIL' }
    $assignments=$ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst]
    },$true)
    foreach($assign in $assignments){
        $left=$assign.Left
        if($left -is [System.Management.Automation.Language.VariableExpressionAst]){
            $variable=($left.VariablePath.UserPath).ToUpperInvariant()
            if($forbidden -contains $variable) {
                throw 'P4_HOME_FIX_RESERVED_AUTOMATIC_VARIABLE_ASSIGNED'
            }
        }
    }
}
Write-Host 'P4_OWNER_HOME_PROFILE_AST_GUARDS_PASS'
Write-Host 'P4_OWNER_ACTIVATION_POWERSHELL_PARSE_PASS'
$python='C:\Program Files\Python314\python.exe'
if(-not(Test-Path -LiteralPath $python -PathType Leaf)){
    throw 'P4_HOME_FIX_PYTHON_MISSING'
}
$env:PYTHONPATH=(Join-Path $env:GITHUB_WORKSPACE 'poc\p2-sub-discovery')+';'+
    (Join-Path $env:GITHUB_WORKSPACE 'poc\p2-aisub')+';'+
    (Join-Path $env:GITHUB_WORKSPACE 'poc\p3-vietsub-trigger')
$env:PYTHONDONTWRITEBYTECODE='1'
& $python -m unittest -q test_owner_activation_powershell_automatic_variables test_owner_p3_p4_private_bootstrap
if($LASTEXITCODE -ne 0){throw 'P4_HOME_FIX_PYTHON_REGRESSION_FAIL'}
Write-Host 'P4_HOME_FIX_WINDOWS_REGRESSION_PASS'
Write-Host 'P4_HOME_FIX_REAL_OWNER_ACTIVATION=NOT_RUN'
Write-Host 'P4_HOME_FIX_REAL_TV_AND_PROVIDER=NOT_RUN'
