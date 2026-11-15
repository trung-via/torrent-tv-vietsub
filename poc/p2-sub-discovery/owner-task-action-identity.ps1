# Pure TaskScheduler action semantic identity for owner-private P3/P4.
# One trusted PowerShell executable, fixed four launch switches, literal
# owner-private launcher script and no working directory.
# Accept harmless path casing/quotes and pwsh.exe vs its resolved full path.
# This function never modifies any task or executes an action.
Set-StrictMode -Version Latest

function Get-TTVOwnerTaskActionState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Task,
        [Parameter(Mandatory)][string]$ExpectedExecutable,
        [Parameter(Mandatory)][string]$ExpectedLauncher
    )
    $state = [ordered]@{
        Accepted = $false
        OneAction = $false
        ExecutableMatch = $false
        LauncherMatch = $false
        SwitchesMatch = $false
        WorkingDirectoryEmpty = $false
    }
    try {
        if ($null -eq $Task -or $null -eq $Task.Actions -or
            @($Task.Actions).Count -ne 1) {
            return [pscustomobject]$state
        }
        $state.OneAction = $true
        $action = @($Task.Actions)[0]
        if ($null -eq $action) { return [pscustomobject]$state }
        $state.WorkingDirectoryEmpty = [string]::IsNullOrWhiteSpace(
            [string]$action.WorkingDirectory)

        $actualExe = ([string]$action.Execute).Trim().Trim('"')
        if ($actualExe -ieq 'pwsh.exe' -or $actualExe -ieq 'pwsh') {
            $actualExe = [string](Get-Command pwsh.exe -CommandType Application -ErrorAction Stop).Source
        }
        $expectedExe = [IO.Path]::GetFullPath($ExpectedExecutable)
        $actualExe = [IO.Path]::GetFullPath($actualExe)
        $state.ExecutableMatch = $actualExe.Equals(
            $expectedExe, [StringComparison]::OrdinalIgnoreCase)

        $argumentText = ([string]$action.Arguments).Trim()
        # Fixed switches only. No -Command/-EncodedCommand/-ExecutionPolicy,
        # extra statements or arbitrary executable arguments.
        if ($argumentText -match '[\r\n]') { return [pscustomobject]$state }
        $pattern = @'
(?ix) \A \s*
-NoLogo \s+ -NoProfile \s+ -NonInteractive \s+ -File \s+
(?:"(?<double>[^"]+)"|'(?<single>[^']+)'|(?<bare>\S+))
\s* \z
'@
        $m = [regex]::Match($argumentText,$pattern)
        if (-not $m.Success) { return [pscustomobject]$state }
        $state.SwitchesMatch = $true
        $fileArg = if ($m.Groups['double'].Success) {
            $m.Groups['double'].Value
        } elseif ($m.Groups['single'].Success) {
            $m.Groups['single'].Value
        } else { $m.Groups['bare'].Value }
        if ($fileArg -match '[%$*?"\r\n]' -or
            -not [IO.Path]::IsPathRooted($fileArg)) {
            return [pscustomobject]$state
        }
        $target = [IO.Path]::GetFullPath($ExpectedLauncher)
        $actual = [IO.Path]::GetFullPath($fileArg)
        $state.LauncherMatch = $actual.Equals(
            $target, [StringComparison]::OrdinalIgnoreCase)
        $state.Accepted = $state.OneAction -and $state.ExecutableMatch -and
            $state.LauncherMatch -and $state.SwitchesMatch -and
            $state.WorkingDirectoryEmpty
        return [pscustomobject]$state
    } catch {
        return [pscustomobject]$state
    }
}
