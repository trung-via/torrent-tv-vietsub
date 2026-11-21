# Read-only PS7 source parse and GitHub RAW LF helper pin check.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 7) { throw 'P2_B15_V2_SOURCE_CHECK_PWSH7_REQUIRED' }
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$paths = @(
    'hostops/setup/owner-p2-b15-fresh-start-v2-once.ps1',
    'hostops/setup/enroll-owner-p2-b15-v2.ps1',
    'hostops/jobs/owner-p2-b15-v2-dispatch.ps1'
)
foreach ($name in $paths) {
    $path = Join-Path $root $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'P2_B15_V2_SOURCE_CHECK_MISSING_FILE'
    }
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $path,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) { throw 'P2_B15_V2_SOURCE_CHECK_PARSE_ERROR' }
}
$helper = [IO.File]::ReadAllText((Join-Path $root $paths[0]),
    [Text.UTF8Encoding]::new($false,$true))
if ($helper.StartsWith([char]0xfeff)) { throw 'P2_B15_V2_SOURCE_CHECK_BOM' }
$lf = $helper.Replace("`r`n","`n")
if ($lf.Contains("`r")) { throw 'P2_B15_V2_SOURCE_CHECK_LONE_CR' }
$bytes = [Text.UTF8Encoding]::new($false).GetBytes($lf)
$hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
$enroll = [IO.File]::ReadAllText((Join-Path $root $paths[1]))
if (-not $enroll.Contains(("`$helperSHA = '" + $hash + "'"))) {
    throw 'P2_B15_V2_SOURCE_CHECK_HELPER_PIN_MISMATCH'
}
Write-Output 'HOSTOPS_P2_B15_V2_SOURCE_CHECK=PASS_PWSH7_SYNTAX_HELPER_SHA'
Write-Output 'HOSTOPS_P2_B15_V2_SOURCE_CHECK_PRIVATE=NOT_ACCESSED'
Write-Output 'HOSTOPS_P2_B15_V2_SOURCE_CHECK_TASK=NOT_TRIGGERED'
Write-Output 'HOSTOPS_P2_B15_V2_SOURCE_CHECK_PROVIDER_TV=NOT_RUN'
