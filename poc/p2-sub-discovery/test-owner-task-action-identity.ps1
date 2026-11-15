# Pure TaskScheduler action tests. NO actual task mutation, owner files or LAN.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'owner-task-action-identity.ps1')
$exe = (Get-Command pwsh.exe -CommandType Application -ErrorAction Stop).Source
$launcher = [IO.Path]::GetFullPath((Join-Path $env:TEMP 'ttv-synthetic-owner\start-owner-session-agent.ps1'))
$canonical = '-NoLogo -NoProfile -NonInteractive -File "' + $launcher + '"'
function New-SafeFixture([string]$exeText,[string]$argumentText,[string]$workDir = '') {
    return [pscustomobject]@{ Actions = @(
        [pscustomobject]@{
            Execute=$exeText
            Arguments=$argumentText
            WorkingDirectory=$workDir
        }) }
}
function Require-Action([string]$label,[object]$task,[bool]$expected) {
    $state = Get-TTVOwnerTaskActionState -Task $task -ExpectedExecutable $exe -ExpectedLauncher $launcher
    if ($state.Accepted -ne $expected) {
        throw ('OWNER_TASK_ACTION_REGRESSION_' + $label)
    }
}
Require-Action 'EXACT_ACTION' (New-SafeFixture $exe $canonical) $true
Require-Action 'SHORT_EXE' (New-SafeFixture 'pwsh.exe' $canonical) $true
Require-Action 'EXE_QUOTES' (New-SafeFixture ('"' + $exe + '"') $canonical) $true
Require-Action 'UNQUOTED_SCRIPT' (New-SafeFixture $exe (
    '-NoLogo -NoProfile -NonInteractive -File ' + $launcher)) $true
Require-Action 'CASE_VARIANT' (New-SafeFixture $exe.ToUpperInvariant() (
    '-NOLOGO -NOPROFILE -NONINTERACTIVE -FILE "' +
    $launcher.ToUpperInvariant() + '"')) $true
Require-Action 'OTHER_SCRIPT' (New-SafeFixture $exe (
    '-NoLogo -NoProfile -NonInteractive -File "' +
    ([IO.Path]::GetFullPath((Join-Path $env:TEMP 'untrusted-script.ps1'))) + '"')) $false
Require-Action 'CMD_EXECUTABLE' (New-SafeFixture 'C:\Windows\System32\cmd.exe' $canonical) $false
Require-Action 'EXTRA_COMMAND' (New-SafeFixture $exe ($canonical + '; Write-Output success')) $false
Require-Action 'EXECUTION_POLICY' (New-SafeFixture $exe (
    '-NoProfile -ExecutionPolicy Bypass -File "' + $launcher + '"')) $false
Require-Action 'WORKING_DIRECTORY' (New-SafeFixture $exe $canonical $env:TEMP) $false
Require-Action 'SECOND_ACTION' ([pscustomobject]@{ Actions=@(
    [pscustomobject]@{Execute=$exe;Arguments=$canonical;WorkingDirectory=''},
    [pscustomobject]@{Execute=$exe;Arguments=$canonical;WorkingDirectory=''}
) }) $false
Require-Action 'SHELL_WRAPPER' (New-SafeFixture 'cmd.exe' (
    '/c pwsh.exe -File "'+$launcher+'"')) $false
Write-Host 'OWNER_BRIDGE_TASK_ACTION_EQUIVALENCE_TESTS=12_PASS'
Write-Host 'OWNER_BRIDGE_REAL_OWNER_TASK_READ_OR_MUTATED=NO'
