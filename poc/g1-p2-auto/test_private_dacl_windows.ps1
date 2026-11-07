# Hosted Windows test of the exact private-vault ACL helper without a build,
# service, network, self-hosted runner, APK, secrets or device operations.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$source = Join-Path $PSScriptRoot 'retain-private-arm32.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw 'DACL_TEST_SOURCE_PARSER_FAILED' }

# Import only these three helper definitions. Never run the retention script's
# top-level GitHub/runner checks or copy an artifact while testing.
foreach ($name in @('Stop-Retention','Guard-NoReparse','Restrict-Directory')) {
    $nodes = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -ceq $name
    }, $true))
    if ($nodes.Count -ne 1) { throw ('DACL_TEST_FUNCTION_NOT_UNIQUE_' + $name) }
    . ([scriptblock]::Create($nodes[0].Extent.Text))
}

$temp = Join-Path $env:TEMP ('TorrentTvDaclTest-' + [guid]::NewGuid().ToString('N'))
$vault = Join-Path $temp 'vault'
$access = [Security.AccessControl.AccessControlSections]::Access
try {
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    Restrict-Directory $vault
    Restrict-Directory $vault  # Existing protected directory must be repeatable.
    $info = New-Object IO.DirectoryInfo($vault)
    $secure = $info.GetAccessControl($access)
    if (-not $secure.AreAccessRulesProtected) {
        throw 'DACL_TEST_INHERITANCE_STILL_ENABLED'
    }
    $rules = @($secure.GetAccessRules($true,$true,
        [Security.Principal.SecurityIdentifier]))
    if ($rules.Count -lt 2) { throw 'DACL_TEST_REQUIRED_RULES_MISSING' }
    if (@($rules | Where-Object {
        $_.IsInherited -or $_.IdentityReference.Value -eq 'S-1-1-0'
    }).Count -ne 0) { throw 'DACL_TEST_INHERITED_OR_EVERYONE_ACCESS' }

    # A locally injected broad ACE must be corrected on next protected setup.
    $everyone = New-Object Security.Principal.SecurityIdentifier('S-1-1-0')
    $unsafe = [Security.AccessControl.FileSystemAccessRule]::new(
        $everyone, [Security.AccessControl.FileSystemRights]::ReadAndExecute,
        [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
            [Security.AccessControl.InheritanceFlags]::ObjectInherit,
        [Security.AccessControl.PropagationFlags]::None,
        [Security.AccessControl.AccessControlType]::Allow)
    $secure.AddAccessRule($unsafe)
    $info.SetAccessControl($secure)
    Restrict-Directory $vault
    $readback = $info.GetAccessControl($access)
    $after = @($readback.GetAccessRules($true,$true,
        [Security.Principal.SecurityIdentifier]))
    if (@($after | Where-Object { $_.IdentityReference.Value -eq 'S-1-1-0' }).Count -ne 0) {
        throw 'DACL_TEST_BROAD_ACCESS_NOT_REMOVED'
    }

    Write-Host 'G1P2_PRIVATE_DACL_WINDOWS_REAL_EXECUTION_PASS_NO_ELEVATION_OR_SACL'
} finally {
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction Stop
    }
}
