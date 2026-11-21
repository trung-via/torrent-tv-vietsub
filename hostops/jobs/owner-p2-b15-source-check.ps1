# Safe, read-only PowerShell 7 source gate on the dedicated Windows runner.
# Never execute the Owner helper, enroll a task, or access private media.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 7) {
    throw 'HOSTOPS_OWNER_P2_SOURCE_CHECK_PWSH7_REQUIRED'
}
$relative = @(
    'hostops/setup/owner-p2-batch15-fresh-start-once.ps1',
    'hostops/setup/enroll-owner-p2-batch15-fresh-start.ps1',
    'hostops/jobs/owner-p2-batch15-fresh-start-dispatch.ps1'
)
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
foreach ($file in $relative) {
    $path = Join-Path $root $file
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'HOSTOPS_OWNER_P2_SOURCE_CHECK_FILE_MISSING'
    }
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $path,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -ne 0) {
        throw 'HOSTOPS_OWNER_P2_SOURCE_CHECK_PARSE_FAILURE'
    }
}
$helper = Join-Path $root $relative[0]
$enroller = Join-Path $root $relative[1]
$hash = (Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash.ToLowerInvariant()
$enrollText = [IO.File]::ReadAllText($enroller)
if (-not $enrollText.Contains(("`$helperSHA = '" + $hash + "'"))) {
    throw 'HOSTOPS_OWNER_P2_SOURCE_CHECK_SHA_PIN_DRIFT'
}
Write-Output 'HOSTOPS_OWNER_P2_FRESH_SOURCE_CHECK=PASS_PARSE_AND_HELPER_SHA_PIN'
Write-Output 'HOSTOPS_OWNER_P2_FRESH_SOURCE_CHECK_PRIVATE_STATE=NOT_ACCESSED'
Write-Output 'HOSTOPS_OWNER_P2_FRESH_SOURCE_CHECK_TASK=NOT_TRIGGERED'
Write-Output 'HOSTOPS_OWNER_P2_FRESH_SOURCE_CHECK_PROVIDER_TV=NOT_RUN'
