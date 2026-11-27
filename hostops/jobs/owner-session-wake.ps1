# Inert Signal Only — no username/profile, script args, media or credentials.
# This job can run as the dedicated GitHub NETWORK_SERVICE runner and has
# only CreateFiles access inside an explicitly enrolled ProgramData WAKE dir.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_ACTIONS -cne 'true') {
    throw 'OWNER_BRIDGE_WAKE_UNTRUSTED_RUNNER'
}

$dir = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\Wake'
if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
    Write-Host 'OWNER_BRIDGE_WAKE=NOT_ENROLLED'
    Write-Host 'NO_USER_PROFILE_ACCESS=YES'
    exit 0
}
$path = Join-Path $dir ('wake-' + [Guid]::NewGuid().ToString('N') + '.txt')
try {
    $bytes = [Text.Encoding]::ASCII.GetBytes('WAKE_V1' + [char]10)
    $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew,
                             [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
    }
    finally { $stream.Dispose() }
    Write-Host 'OWNER_BRIDGE_WAKE=INERT_SIGNAL_CREATED'
}
catch [UnauthorizedAccessException] {
    Write-Host 'OWNER_BRIDGE_WAKE=BLOCKED_BY_WINDOWS_ACL'
}
Write-Host 'NO_MEDIA_NAME_OR_API_KEY_IN_GITHUB=YES'
Write-Host 'NO_ARBITRARY_OWNER_COMMAND_EXECUTED=YES'
Write-Host 'NO_WINDOWS_PERMISSION_CHANGE=YES'
