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


# Exercise the REAL read-only source classifier from the Owner script with
# synthetic data. No OwnerBridge files, Scheduled Tasks or network calls.
foreach ($functionName in @(
    'Hold', 'SafeItem', 'ExactHash', 'V1CanonicalHash',
    'GetOwnerInstalledSourceVersion'
)) {
    $definition = @($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -ceq $functionName
    }, $true))
    if ($definition.Count -ne 1) {
        throw ('TTV_WINDOWS_VERSION_FUNCTION_MISSING_' + $functionName)
    }
    . ([ScriptBlock]::Create($definition[0].Extent.Text))
}
function HashFixtureText([string]$source) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($source)
        return [BitConverter]::ToString($hash.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    } finally { $hash.Dispose() }
}
$versionFixture = Join-Path ([IO.Path]::GetTempPath()) (
    'ttv-owner-version-ci-' + [Guid]::NewGuid().ToString('N'))
$app = Join-Path $versionFixture 'app'
[IO.Directory]::CreateDirectory($app) | Out-Null
try {
    $names = @('first.py', 'second.py', 'third.py')
    $baseline = [ordered]@{}
    $v2 = [ordered]@{}
    $v2PreR0 = [ordered]@{}
    $utf8 = [Text.UTF8Encoding]::new($false)
    foreach ($name in $names) {
        $baseline[$name] = HashFixtureText ("v1-" + $name + "`n")
        $v2[$name] = HashFixtureText ("v2-" + $name + "`n")
        $v2PreR0[$name] = HashFixtureText ("v2old-" + $name + "`n")
        # CRLF is allowed for V1 identity, but the recovery bytes stay intact.
        [IO.File]::WriteAllText((Join-Path $app $name),
            ("v1-" + $name + "`r`n"), $utf8)
    }
    $v2['p3_ingress_telemetry.py'] = HashFixtureText "v2-telemetry`n"
    $v2PreR0['p3_ingress_telemetry.py'] = HashFixtureText "v2old-telemetry`n"
    if ((GetOwnerInstalledSourceVersion) -cne 'V1_SOURCE_EXACT') {
        throw 'TTV_WINDOWS_VERSION_V1_CLASSIFICATION_FAILED'
    }
    # An unexpected telemetry file must not produce a V1 success.
    $telemetry = Join-Path $app 'p3_ingress_telemetry.py'
    [IO.File]::WriteAllText($telemetry, "v2-telemetry`n", $utf8)
    if ((GetOwnerInstalledSourceVersion) -cne 'MIXED_OR_UNKNOWN') {
        throw 'TTV_WINDOWS_VERSION_MIXED_V1_TELEMETRY_NOT_BLOCKED'
    }
    foreach ($name in $names) {
        [IO.File]::WriteAllText((Join-Path $app $name),
            ("v2-" + $name + "`n"), $utf8)
    }
    if ((GetOwnerInstalledSourceVersion) -cne 'V2_R0_SOURCE_EXACT') {
        throw 'TTV_WINDOWS_VERSION_V2_CLASSIFICATION_FAILED'
    }
    foreach ($name in $names) {
        [IO.File]::WriteAllText((Join-Path $app $name),
            ("v2old-" + $name + "`n"), $utf8)
    }
    [IO.File]::WriteAllText($telemetry, "v2old-telemetry`n", $utf8)
    if ((GetOwnerInstalledSourceVersion) -cne 'V2_PRE_R0_SOURCE_EXACT') {
        throw 'TTV_WINDOWS_VERSION_PRE_R0_V2_CLASSIFICATION_FAILED'
    }
    [IO.File]::WriteAllText((Join-Path $app 'second.py'), "unreviewed`n", $utf8)
    if ((GetOwnerInstalledSourceVersion) -cne 'MIXED_OR_UNKNOWN') {
        throw 'TTV_WINDOWS_VERSION_DRIFT_NOT_BLOCKED'
    }
    Write-Host 'TTV_WINDOWS_INSTALLED_V1_V2_MIXED_CLASSIFIER=PASS'
} finally {
    if ([IO.Directory]::Exists($versionFixture)) {
        [IO.Directory]::Delete($versionFixture, $true)
    }
}
