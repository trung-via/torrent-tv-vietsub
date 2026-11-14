# HostOps read-only; no secret value, media name or user path ever printed.
# Purpose: distinguish dedicated runner SERVICE account from owner's
# interactive Windows profile before attempting automatic local EN->P2.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub') {
    throw 'AUTO_HOSTOPS_UNTRUSTED_RUNNER'
}

$local = $env:LOCALAPPDATA
$hasProfile = -not [string]::IsNullOrWhiteSpace($local)
$cachePresent = $false
$cacheSrtPresent = $false
if ($hasProfile) {
    $root = Join-Path $local 'TorrentTVVietsub\subtitle-trials'
    $cachePresent = Test-Path -LiteralPath $root -PathType Container
    if ($cachePresent) {
        $cacheSrtPresent = [bool]@(Get-ChildItem -LiteralPath $root -File -Filter '*.srt' -ErrorAction SilentlyContinue | Select-Object -First 1).Count
    }
}
$hasOstKey = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('OPENSUBTITLES_API_KEY','Process'))
$hasGemKey = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('GEMINI_API_KEY','Process'))
$pythonReady = [bool](Get-Command py.exe -ErrorAction SilentlyContinue)
$pwshReady = [bool](Get-Command pwsh.exe -ErrorAction SilentlyContinue)
$schedulerRunning = (Get-Service -Name 'Schedule' -ErrorAction SilentlyContinue).Status -eq 'Running'
$session = [Diagnostics.Process]::GetCurrentProcess().SessionId
$interactive = [Environment]::UserInteractive

Write-Host 'AUTO_TTV_HOSTOPS_READONLY_V1'
Write-Host ('RUNNER_HAS_OWNER_CACHE_DIR=' + $cachePresent.ToString().ToUpperInvariant())
Write-Host ('RUNNER_HAS_OWNER_CACHED_SRT=' + $cacheSrtPresent.ToString().ToUpperInvariant())
Write-Host ('RUNNER_HAS_OPENSUBTITLES_KEY=' + $hasOstKey.ToString().ToUpperInvariant())
Write-Host ('RUNNER_HAS_GEMINI_KEY=' + $hasGemKey.ToString().ToUpperInvariant())
Write-Host ('PYTHON_LAUNCHER_PRESENT=' + $pythonReady.ToString().ToUpperInvariant())
Write-Host ('POWERSHELL_7_PRESENT=' + $pwshReady.ToString().ToUpperInvariant())
Write-Host ('TASK_SCHEDULER_RUNNING=' + $schedulerRunning.ToString().ToUpperInvariant())
Write-Host ('RUNNER_USER_INTERACTIVE=' + $interactive.ToString().ToUpperInvariant())
Write-Host ('RUNNER_SESSION_IS_ZERO=' + ($session -eq 0).ToString().ToUpperInvariant())
Write-Host 'NO_SECRET_OR_SUBTITLE_CONTENT_READ=YES'
Write-Host 'NO_WINDOWS_CONFIGURATION_CHANGED=YES'
