# Offline parser-only check. Never runs the privilege/delegation installer.
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:GITHUB_ACTIONS -cne 'true') { throw 'HOSTOPS_PARSE_CONTEXT_MISMATCH' }
$path = Join-Path $env:GITHUB_WORKSPACE 'hostops\setup\grant-owneragent-task-control.ps1'
if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw 'HOSTOPS_PARSE_TARGET_MISSING'
}
$tokens = $null
$errors = $null
$null = [Management.Automation.Language.Parser]::ParseFile(
    $path, [ref]$tokens, [ref]$errors)
Write-Host "TTV_TASK_ACL_PARSE_ERROR_COUNT=$(@($errors).Count)"
if (@($errors).Count -ne 0) { throw 'TTV_TASK_ACL_PS51_PARSE_FAILED' }
Write-Host 'TTV_TASK_ACL_PARSE=PASS'
Write-Host 'TTV_TASK_ACL_INSTALLER_EXECUTED=NO'
Write-Host 'TTV_TASK_ACL_WINDOWS_PERMISSIONS_CHANGED=NO'