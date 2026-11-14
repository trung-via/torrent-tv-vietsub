# Logged-in owner ONLY. Default = READ_ONLY. -Activate is explicit opt-in.
# Preflight original paired P4 cert+private media policy; no new secrets,
# no device install, no API/provider request, no LAN bind, no task kill.
[CmdletBinding()]
param(
    [switch]$Activate,
    [ValidatePattern('^[A-Za-z0-9_-]{1,80}$')]
    [string]$TorrServerProfile = 'owner-local',
    [ValidateRange(1024,65535)]
    [int]$TorrServerPort = 8090
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -eq 'true' -or $env:CI -eq 'true' -or
    -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0) {
    throw 'P3_P4_ACTIVATE_REQUIRES_LOGGED_IN_OWNER'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$loggedIn = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ($null -eq $identity.User -or
    $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($loggedIn) -or
    -not $identity.Name.Equals($loggedIn,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'P3_P4_ACTIVATE_NOT_LOGGED_IN_OWNER'
}
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$origin = (& git -C $repoRoot remote get-url origin 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or
    $origin -notmatch '(?i)^(https://github\.com/|git@github\.com:)trung-via/torrent-tv-vietsub(?:\.git)?$') {
    throw 'P3_P4_ACTIVATE_UNTRUSTED_ORIGIN'
}
$sourceHead = (& git -C $repoRoot rev-parse HEAD | Out-String).Trim()
$trackedStatus = @(& git -C $repoRoot status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or
    $sourceHead -notmatch '^[0-9a-f]{40}$' -or
    $trackedStatus.Count -ne 0) {
    throw 'P3_P4_ACTIVATE_SOURCE_NOT_CLEAN_AND_PINNED'
}
try {
    $pr = Invoke-RestMethod -Method Get -TimeoutSec 15 -Uri 'https://api.github.com/repos/trung-via/torrent-tv-vietsub/pulls/162' -Headers @{
      'Accept'='application/vnd.github+json'
      'User-Agent'='TorrentTV-Owner-P3-P4-Activation'
    } -ErrorAction Stop
} catch { throw 'P3_P4_ACTIVATE_PR_PROVENANCE_UNAVAILABLE' }
if ($pr.state -cne 'open' -or -not $pr.draft -or
    $pr.head.repo.full_name -cne 'trung-via/torrent-tv-vietsub' -or
    $pr.head.ref -cne 'feature/p3-p4-cross-lane-tv-owner-compose-20261114' -or
    $pr.head.sha -cne $sourceHead -or $pr.base.ref -cne 'main') {
    throw 'P3_P4_ACTIVATE_REVIEWED_PR_HEAD_DRIFT'
}
Write-Host 'P3_P4_ACTIVATE_CURRENT_PR162_SHA=PINNED_PASS'
$home = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$owner = Join-Path $home 'OwnerBridge'
$p4 = Join-Path $home 'P4'
$policy = Join-Path $owner 'p3-p4-policy.json'
$media = Join-Path $owner 'approved-media'
$cache = Join-Path $home 'subtitle-trials'
$state = Join-Path $home 'P2\auto-lean120-state'
$entry = Join-Path $repoRoot 'poc\p2-sub-discovery\owner_p3_p4_entrypoint.py'
$installer = Join-Path $repoRoot 'poc\p2-sub-discovery\install-owner-session-bridge.ps1'
$pairingReady = (Test-Path -LiteralPath $p4 -PathType Container)
foreach ($name in @('pairing-key.hex','gateway-bind.txt','pairing-token.txt',
                    'pc-cert.pem','pc-key.pem','adb-staged-v1.receipt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $p4 $name) -PathType Leaf)) {
        $pairingReady = $false
    }
}
$secretsReady = (Test-Path -LiteralPath (Join-Path $owner 'secrets\opensub.dpapi') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $owner 'secrets\gemini.dpapi') -PathType Leaf)
$task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -ErrorAction SilentlyContinue
$taskReady = $null -ne $task
Write-Host ('P3_P4_ACTIVATE_PAIRING_FILES_PRESENT=' + $pairingReady.ToString().ToUpperInvariant())
Write-Host ('P3_P4_ACTIVATE_DPAPI_FILES_PRESENT=' + $secretsReady.ToString().ToUpperInvariant())
Write-Host ('P3_P4_ACTIVATE_OWNER_TASK_PRESENT=' + $taskReady.ToString().ToUpperInvariant())
if (-not $Activate) {
    Write-Host 'P3_P4_ACTIVATE=READ_ONLY_NO_USER_OR_TV_CHANGES'
    return
}
if (-not $pairingReady -or -not $secretsReady -or
    -not (Test-Path -LiteralPath $owner -PathType Container)) {
    Write-Host 'P3_P4_ACTIVATE=HOLD_PAIRING_OR_OWNER_BRIDGE_MISSING'
    return
}
# A clean owner session can also be a FIRST enrollment: the existing
# owner-only installer can create the interactive task if it does not exist.
# Never mutate a task of another principal or a service logon task.
if ($taskReady -and (
    [string]$task.Principal.LogonType -cne 'Interactive' -or
    [string]$task.Principal.UserId -cne $identity.Name)) {
    throw 'P3_P4_ACTIVATE_OWNER_TASK_IDENTITY_MISMATCH'
}
if (-not (Test-Path -LiteralPath $entry -PathType Leaf) -or
    -not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw 'P3_P4_ACTIVATE_REVIEWED_SOURCES_MISSING'
}
$created = $false
$ownedBytes = $null
try {
    if (Test-Path -LiteralPath $policy) {
        if (-not (Test-Path -LiteralPath $policy -PathType Leaf) -or
            (Get-Item -LiteralPath $policy).LinkType) {
            throw 'P3_P4_ACTIVATE_POLICY_PATH_NOT_REGULAR'
        }
        Write-Host 'P3_P4_ACTIVATE_POLICY=EXISTING_UNMODIFIED'
    } else {
        if (-not (Test-Path -LiteralPath $media)) {
            New-Item -ItemType Directory -Path $media -ErrorAction Stop | Out-Null
        }
        if (-not (Test-Path -LiteralPath $media -PathType Container)) {
            throw 'P3_P4_ACTIVATE_MEDIA_ROOT_INVALID'
        }
        # Owner enables listener but authorizes ZERO films by default.
        $manifest = [ordered]@{
            schema='TTV-P3-P4-OWNER-POLICY-V1'
            enabled=$true
            profile_id=$TorrServerProfile
            torrserver_port=$TorrServerPort
            private_media_root=[IO.Path]::GetFullPath($media)
            media=@()
        }
        $ownedBytes = [Text.UTF8Encoding]::new($false).GetBytes(
            (ConvertTo-Json $manifest -Depth 5))
        $handle = [IO.File]::Open($policy,[IO.FileMode]::CreateNew,
                                 [IO.FileAccess]::Write,[IO.FileShare]::None)
        $created = $true
        try {
            $handle.Write($ownedBytes,0,$ownedBytes.Length)
            $handle.Flush($true)
        } finally { $handle.Dispose() }
        Write-Host 'P3_P4_ACTIVATE_POLICY=DENY_ALL_MEDIA_ENROLLED'
    }
    $python = (Get-Command py.exe -ErrorAction Stop).Source
    $lines = @(& $python -3 $entry --owner-root $owner --cache-root $cache --state-root $state --preflight-only)
    if ($LASTEXITCODE -ne 0 -or
        @($lines | Where-Object { $_ -ceq 'P3_P4_OWNER_PREFLIGHT=PASS_NO_LAN_NO_PROVIDER' }).Count -ne 1) {
        throw 'P3_P4_ACTIVATE_OWNER_PRIVATE_PREFLIGHT_BLOCKED'
    }
    Write-Host 'P3_P4_ACTIVATE_OWNER_PRIVATE_PREFLIGHT=PASS_NO_LAN'
    # The existing installer never kills or hot-reloads an active P2 worker.
    & $installer
    Write-Host 'P3_P4_ACTIVATE_SOURCE=STAGED_NO_INFLIGHT_WORK_INTERRUPTED'
    Write-Host 'P3_P4_ACTIVATE_LAN_AND_TV=NOT_YET_OBSERVED'
    Write-Host 'P3_P4_ACTIVATE_PROVIDER=NO_FILM_AUTHORIZED_YET'
} catch {
    if ($created -and (Test-Path -LiteralPath $policy -PathType Leaf) -and
        $null -ne $ownedBytes) {
        $actual = [IO.File]::ReadAllBytes($policy)
        if ([Convert]::ToBase64String($actual) -ceq
            [Convert]::ToBase64String([byte[]]$ownedBytes)) {
            Remove-Item -LiteralPath $policy -Force -ErrorAction Stop
            Write-Host 'P3_P4_ACTIVATE_FAILED_NEW_POLICY_ROLLED_BACK=YES'
        }
    }
    throw
}
