# Inspect the exact previous P2 text-QA install and Owner health; never mutate.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$result = [ordered]@{
    schema = 'TTV-P2-TEXT-QA-STATUS-V1'
    utc_epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    status = 'HOLD'
    phase = 'IDENTITY'
    task = 'UNKNOWN'
    gateway = 'UNKNOWN'
    bridge = 'UNKNOWN'
    bridge_sha16 = 'UNKNOWN'
    active_locks = -1
    pending_events = -1
    marker_count = -1
    owner_health = 'UNKNOWN'
    last_install_code = 'UNKNOWN'
}
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $logged = [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
    if ($env:GITHUB_ACTIONS -ceq 'true' -or
        [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
        $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
        [string]::IsNullOrWhiteSpace($logged) -or
        -not $identity.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'P2_TEXT_STATUS_OWNER_REQUIRED'
    }
    $result.phase = 'TASK'
    $task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\' -ErrorAction Stop
    $result.task = [string]$task.State
    if ($result.task -cnotin @('Running','Ready','Disabled')) { throw 'P2_TEXT_STATUS_TASK_STATE' }

    $result.phase = 'FILES'
    $app = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge\app'
    $files = [ordered]@{
        'poc\p2-aisub\translator_gateway.py' = @{
            new = 'd63c468a6417fab87d6c9e56e6dd319ddc28289f7c95eb064eaf9684d5774fc3'
            previous = @('b06c151cc4275a7793fdb7891d7859715e602a676a553ea89e6e242578190183')
        }
        'poc\p2-sub-discovery\owner_session_bridge.py' = @{
            new = '85f8ca9e75d83e357becf7c9191734ce0f41b664b83cf8ea684a3bff1e1dc4b7'
            previous = @('5727ac9f71a5b736c198ce5697714d6a66fcf5b20feb4331a2db905ce1e8b997',
                '6a8af62e4ff33806b7fd3c2deb66df08283302d3441c51edd65da02d1633ce31',
                '1b3154846966879aa05ee1e15f4da0603b7ff75b9dbc0e69d3aaebd5036f1121')
        }
    }
    foreach ($rel in $files.Keys) {
        $path = Join-Path $app $rel
        $classification = 'OTHER'
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $item = Get-Item -LiteralPath $path -Force
            if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $sha = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($rel -match 'owner_session_bridge') {
                    $result.bridge_sha16 = $sha.Substring(0,16)
                }
                if ($sha -ceq $files[$rel].new) { $classification = 'NEW' }
                elseif ($sha -cin $files[$rel].previous) { $classification = 'OLD' }
            }
        }
        if ($rel -match 'translator_gateway') { $result.gateway = $classification }
        else { $result.bridge = $classification }
    }

    $result.phase = 'WORK'
    $ownerRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
    $inbox = Join-Path $ownerRoot 'inbox'
    $state = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
    if (Test-Path -LiteralPath $inbox -PathType Container) {
        $result.pending_events = @(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json').Count
    }
    if (Test-Path -LiteralPath $state -PathType Container) {
        $result.active_locks = @(Get-ChildItem -LiteralPath $state -File -Recurse -Filter 'active.lock').Count
        $result.marker_count = @(Get-ChildItem -LiteralPath $state -File -Recurse -Filter 'batch-*.inflight').Count
    }
    $healthPath = Join-Path $ownerRoot 'agent-health.json'
    if ((Test-Path -LiteralPath $healthPath -PathType Leaf) -and
        (Get-Item -LiteralPath $healthPath).Length -le 512) {
        $health = Get-Content -LiteralPath $healthPath -Raw | ConvertFrom-Json
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$health.observed_utc_epoch
        $result.owner_health = if ($health.schema -ceq 'TTV-OWNER-AGENT-HEALTH-V1' -and
            $health.state -ceq 'READY' -and $age -ge 0 -and $age -le 90) {'READY_FRESH'} else {'STALE'}
    } else { $result.owner_health = 'MISSING' }

    $result.phase = 'LAST_INSTALL'
    $receiptPath = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps\Receipts\receipt.json'
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if ($receipt.schema -cne 'TTV-LAPTOP-HOSTOPS-RECEIPT-V1' -or
        $receipt.operation -cnotin @('owner-p2-text-qa-install-v1','owner-p2-gateway-install-v2') -or
        $receipt.nonce -cnotmatch '^[0-9a-f]{32}$') {
        throw 'P2_TEXT_STATUS_PREVIOUS_INSTALL_RECEIPT_MISSING'
    }
    $log = Join-Path $env:LOCALAPPDATA (
        'TorrentTVVietsub\LaptopHostOps\run-' + $receipt.nonce + '\full-owner-output.log')
    $item = Get-Item -LiteralPath $log -Force -ErrorAction Stop
    if ($item.Length -gt 2097152 -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'P2_TEXT_STATUS_LOG_UNTRUSTED'
    }
    $lines = @(Get-Content -LiteralPath $log -Tail 100 -Encoding UTF8)
    $codes = @(
        'ALREADY_INSTALLED_EXACT_HASH', 'INSTALLED_HASH_VERIFIED_OWNER_RUNNING',
        'ROLLED_BACK_OLD_OWNER_RUNNING', 'HOLD_INTERACTIVE_OWNER_REQUIRED',
        'HOLD_FILE_MISSING_OR_REPARSE','HOLD_DIRECTORY_MISSING_OR_REPARSE',
        'HOLD_OWNER_TASK_IDENTITY_DRIFT','HOLD_OWNER_NOT_READY_TO_PATCH',
        'HOLD_OWNER_PENDING_EVENTS','HOLD_P2_ACTIVE_PROVIDER_JOB',
        'HOLD_UNEXPECTED_MULTIPLE_P2_MARKERS','HOLD_RESIDUAL_WORKER_COUNT',
        'HOLD_RESIDUAL_WORKER_UNVERIFIED','HOLD_RESIDUAL_WORKER_CHANGED',
        'HOLD_RESIDUAL_WORKERS_STILL_RUNNING','HOLD_OWNER_UNEXPECTED_STATE',
        'HOLD_OWNER_REENABLED_DURING_STOP','HOLD_STAGE_HASH_DRIFT',
        'HOLD_INSTALLED_VERSION_UNRECOGNIZED','HOLD_BACKUP_HASH_MISMATCH',
        'HOLD_INSTALLED_CHANGED_AFTER_BACKUP','HOLD_STAGED_TEMP_HASH_DRIFT',
        'HOLD_INSTALLED_HASH_MISMATCH','HOLD_NEW_OWNER_NOT_HEALTHY',
        'HOLD_ROLLBACK_BACKUP_DRIFT','HOLD_OLD_OWNER_RESTART_FAILED',
        'HOLD_ROLLBACK_FAILED_OWNER_MAY_BE_DISABLED')
    foreach ($line in $lines) {
        if ($line -cmatch '^P2_TEXT_QA_OWNER=([A-Z][A-Z0-9_]+)$' -and
            $Matches[1] -cin $codes) {
            $result.last_install_code = $Matches[1]
        }
    }
    $result.status = 'OBSERVED'
    $result.phase = 'COMPLETE'
} catch {
    $result.status = 'HOLD'
}
try {
    $folder = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps\Receipts'
    $target = Join-Path $folder 'p2-text-qa-status-v1.json'
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($result | ConvertTo-Json -Compress))
    if ($bytes.Length -gt 512) { throw 'P2_TEXT_STATUS_RECEIPT_TOO_LARGE' }
    $temp = $target + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllBytes($temp,$bytes)
    [IO.File]::Move($temp,$target,$true)
    Write-Output 'P2_TEXT_STATUS=SANITIZED_RECEIPT_WRITTEN'
} catch {
    Write-Output 'P2_TEXT_STATUS=RECEIPT_WRITE_FAILED'
    exit 1
}
