# Isolated Windows PowerShell 7 test: never invokes the Owner installer,
# Scheduled Task, provider, TV, or user's private OwnerBridge directory.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptFile = Join-Path $PSScriptRoot '..\..\hostops\setup\owner-p3p4-v2-offline-activation.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    $scriptFile, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw 'TTV_WINDOWS_REPLACE_PARSE_FAILED' }
$functions = @($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -ceq 'InvokeTTVAtomicReplacement'
}, $true))
if ($functions.Count -ne 1) { throw 'TTV_WINDOWS_REPLACE_FUNCTION_MISSING' }
# Execute only the source-pinned replacement helper, NOT the installer body.
. ([ScriptBlock]::Create($functions[0].Extent.Text))
function EqualFixtureBytes([string]$path, [byte[]]$expected) {
    if (-not [IO.File]::Exists($path)) { return $false }
    return ([BitConverter]::ToString([IO.File]::ReadAllBytes($path)) -ceq [BitConverter]::ToString($expected))
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) (
    'ttv-owner-v2-ci-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
try {
    $original = Join-Path $fixture 'module.py'
    $stage = Join-Path $fixture 'v2-upload.tmp'
    $originalBytes = [Text.Encoding]::UTF8.GetBytes('original-v1-lf')
    $newBytes = [Text.Encoding]::UTF8.GetBytes('new-v2-lf')
    [IO.File]::WriteAllBytes($original, $originalBytes)
    [IO.File]::WriteAllBytes($stage, $newBytes)

    $backup = InvokeTTVAtomicReplacement $stage $original 'v2-original'
    if (-not [IO.File]::Exists($backup) -or [IO.File]::Exists($stage) -or
        -not (EqualFixtureBytes $backup $originalBytes) -or
        -not (EqualFixtureBytes $original $newBytes)) {
        throw 'TTV_WINDOWS_REPLACE_INSTALL_BYTES_INVALID'
    }

    # Inject a downstream failure AFTER the first V2 destination changed;
    # restore via the SAME helper with an independent byte-exact V1 copy.
    try { throw 'TTV_CI_INJECTED_POST_REPLACE_FAILURE' }
    catch {
        if ($_.Exception.Message -cne 'TTV_CI_INJECTED_POST_REPLACE_FAILURE') { throw }
        $restoreTemp = Join-Path $fixture 'v1-restore.tmp'
        [IO.File]::Copy($backup, $restoreTemp)
        $displaced = InvokeTTVAtomicReplacement $restoreTemp $original 'v1-displaced'
        if (-not [IO.File]::Exists($displaced) -or [IO.File]::Exists($restoreTemp) -or
            -not (EqualFixtureBytes $original $originalBytes)) {
            throw 'TTV_WINDOWS_REPLACE_ROLLBACK_BYTES_INVALID'
        }
    }

    # Empty backup-kind and missing temp must fail without altering V1.
    $invalid = $false
    try { InvokeTTVAtomicReplacement $stage $original '' | Out-Null }
    catch { $invalid = $_.Exception.Message -ceq 'TTV_ATOMIC_REPLACE_ARGUMENT_INVALID' }
    if (-not $invalid) { throw 'TTV_WINDOWS_REPLACE_EMPTY_BACKUP_NOT_REJECTED' }
    $invalid = $false
    try { InvokeTTVAtomicReplacement $stage $original 'v2-original' | Out-Null }
    catch { $invalid = $_.Exception.Message -ceq 'TTV_ATOMIC_REPLACE_PRECONDITION_FAILED' }
    if (-not $invalid -or -not (EqualFixtureBytes $original $originalBytes)) {
        throw 'TTV_WINDOWS_REPLACE_MISSING_SOURCE_NOT_GUARDED'
    }
    Write-Host 'TTV_WINDOWS_REPLACE_INSTALL_ROLLBACK_INJECTED_FAILURE=PASS'
} finally {
    if ([IO.Directory]::Exists($fixture)) {
        [IO.Directory]::Delete($fixture, $true)
    }
}
