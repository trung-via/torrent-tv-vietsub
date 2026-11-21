# Read-only Owner-context classifier for the current unknown-effect P2 batch.
# Reads private batch metadata and the tail of the Owner log, but exports only
# source-owned enum codes/counts to the already enrolled HostOps receipt spool.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$report = [ordered]@{
    schema = 'TTV-P2-BLOCK-ROOTCAUSE-V1'
    utc_epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    status = 'HOLD'
    phase = 'IDENTITY'
    task_state = 'UNKNOWN'
    marker_count = -1
    marker_batch = 'UNKNOWN'
    batch1_file = 'UNKNOWN'
    batch2_file = 'UNKNOWN'
    log_block_seen = 'UNKNOWN'
    last_block_code = 'UNKNOWN'
    first_actionable_code = 'UNKNOWN'
    block_event_count = -1
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $logged = [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
    if ($env:GITHUB_ACTIONS -ceq 'true' -or
        [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
        $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
        [string]::IsNullOrWhiteSpace($logged) -or
        -not $identity.Name.Equals($logged, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'P2_ROOTCAUSE_OWNER_IDENTITY_REQUIRED'
    }

    $report.phase = 'TASK'
    $task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\' -ErrorAction Stop
    $report.task_state = [string]$task.State
    if ($report.task_state -cnotin @('Running','Ready','Disabled')) {
        throw 'P2_ROOTCAUSE_TASK_STATE_UNKNOWN'
    }

    $report.phase = 'MARKER'
    $stateRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
    if (-not (Test-Path -LiteralPath $stateRoot -PathType Container)) {
        throw 'P2_ROOTCAUSE_STATE_MISSING'
    }
    $markers = @(Get-ChildItem -LiteralPath $stateRoot -File -Filter 'batch-*.inflight' -Recurse -ErrorAction Stop)
    $report.marker_count = $markers.Count
    if ($markers.Count -ne 1) { throw 'P2_ROOTCAUSE_MARKER_NOT_UNIQUE' }
    $marker = $markers[0]
    $folder = $marker.Directory
    if ($marker.Name -cne 'batch-0002.inflight' -or
        $folder.Name -cnotmatch '^[0-9a-f]{64}$' -or
        -not $folder.Parent.FullName.Equals($stateRoot, [StringComparison]::OrdinalIgnoreCase) -or
        ($marker.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        $marker.Length -le 0 -or $marker.Length -gt 1024) {
        throw 'P2_ROOTCAUSE_MARKER_SHAPE_HOLD'
    }
    $markerDoc = Get-Content -LiteralPath $marker.FullName -Raw -Encoding UTF8 |
        ConvertFrom-Json -AsHashtable
    if (@($markerDoc.Keys | Sort-Object) -join ',' -cne 'job,schema,version' -or
        $markerDoc.schema -cne 'TTV-P2-INFLIGHT-V1' -or
        $markerDoc.job -cne $folder.Name -or $markerDoc.version -ne 2) {
        throw 'P2_ROOTCAUSE_MARKER_CONTENT_HOLD'
    }
    $report.marker_batch = 'BATCH_0002'
    $first = Join-Path $folder.FullName 'batch-0001.json'
    $second = Join-Path $folder.FullName 'batch-0002.json'
    foreach ($path in @($first,$second)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $item = Get-Item -LiteralPath $path -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'P2_ROOTCAUSE_UNTRUSTED_CHECKPOINT'
            }
        }
    }
    $report.batch1_file = if (Test-Path -LiteralPath $first -PathType Leaf) {'YES'} else {'NO'}
    $report.batch2_file = if (Test-Path -LiteralPath $second -PathType Leaf) {'YES'} else {'NO'}

    $report.phase = 'LOG'
    $ownerLog = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge\diagnostics\owner-full.log'
    $logItem = Get-Item -LiteralPath $ownerLog -Force -ErrorAction Stop
    if ($logItem.Length -le 0 -or $logItem.Length -gt 134217728 -or
        ($logItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'P2_ROOTCAUSE_LOG_UNTRUSTED'
    }
    # A later retry can only report the protective UNCERTAIN_BATCH hold.
    # Search prior blocked tracebacks for the actual initiating exception.
    $tailLines = @(Get-Content -LiteralPath $ownerLog -Tail 2400 -Encoding UTF8 -ErrorAction Stop)
    if (($tailLines -join "`n").Length -gt 1000000) {
        throw 'P2_ROOTCAUSE_LOG_TAIL_TOO_LARGE'
    }
    $blockLines = @()
    for ($index=0; $index -lt $tailLines.Count; $index++) {
        if ($tailLines[$index] -match "^OWNER_FULL_TRACE 'P2_EVENT_BLOCKED' ") {
            $blockLines += $index
        }
    }
    $report.block_event_count = $blockLines.Count
    $report.log_block_seen = if ($blockLines.Count -gt 0) {'YES'} else {'NO'}
    $known = @(
            'AGY_TIMEOUT_RESULT_UNKNOWN','AGY_PROCESS_FAILED_RESULT_UNKNOWN',
            'AGY_PROCESS_START_FAILED','AGY_NO_SUCCESSFUL_RESULT',
            'AGY_EVENT_INVALID','AGY_UNEXPECTED_TOOL_USAGE',
            'AGY_MULTIPLE_RESULTS','AGY_RESPONSE_TOO_LARGE',
            'AGY_STRUCTURED_OUTPUT_REQUIRED','AGY_TRANSLATION_ENVELOPE_INVALID',
            'AGY_TRANSLATION_COUNT_INVALID','AGY_TRANSLATION_ID_OR_TEXT_INVALID',
            'AGY_ACCOUNT_SETTINGS_UNREADABLE','AGY_ACCOUNT_SETTINGS_INVALID',
            'AGY_ACCOUNT_REQUIRED_API_KEY_MODE_REFUSED',
            'AGY_PERSONAL_ACCOUNT_MODE_REQUIRED','AGY_APP_ACCOUNT_SETTINGS_UNREADABLE',
            'AGY_APP_ACCOUNT_SETTINGS_INVALID','AGY_ACCOUNT_REQUIRED_ADC_MODE_REFUSED',
            'AGY_LIVE_PROVIDER_FORBIDDEN_IN_CI','AGY_OWNER_HOME_UNAVAILABLE',
            'AGY_CLI_NOT_INSTALLED_FOR_OWNER','AGY_MODEL_SLUG_INVALID',
            'AGY_MODEL_THINKING_LEVEL_MISMATCH',
            'AUTO_LEAN120_UNCERTAIN_BATCH_MANUAL_RECONCILE',
            'AUTO_LEAN120_CHECKPOINT_INVALID','AUTO_LEAN120_CHECKPOINT_DIGEST_MISMATCH',
            'AUTO_LEAN120_PRIOR_PROVIDER_INFLIGHT_HOLD',
            'AUTO_LEAN120_ABANDONED_JOB_HOLD',
            'LEAN120_WINDOW_INVALID','LEAN120_GLOSSARY_INVALID',
            'P4_ROLLING_TV_SESSION_CHANGED','P4_ROLLING_TORRSERVER_FILE_CHANGED',
            'P4_ROLLING_SELECTED_MEDIA_CHANGED'
    )
    foreach ($line in $blockLines) {
        # A subsequent OWNER_FULL_TRACE belongs to a different event. The
        # traceback remains Owner-private; only source-owned codes escape.
        $candidate = 'UNCLASSIFIED'
        for ($index=$line+1; $index -lt $tailLines.Count; $index++) {
            if ($tailLines[$index] -match '^OWNER_FULL_TRACE ') { break }
            if ($tailLines[$index] -cmatch '^(?:ValueError|RuntimeError): ([A-Z][A-Z0-9_]{4,79})\s*$' -and
                $Matches[1] -cin $known) {
                $candidate = $Matches[1]
            }
        }
        $report.last_block_code = $candidate
        if ($report.first_actionable_code -ceq 'UNKNOWN' -and
            $candidate -cnotin @('UNCLASSIFIED',
                'AUTO_LEAN120_UNCERTAIN_BATCH_MANUAL_RECONCILE',
                'AUTO_LEAN120_PRIOR_PROVIDER_INFLIGHT_HOLD',
                'AUTO_LEAN120_ABANDONED_JOB_HOLD')) {
            $report.first_actionable_code = $candidate
        }
    }
    if ($blockLines.Count -gt 0 -and $report.first_actionable_code -ceq 'UNKNOWN') {
        $report.first_actionable_code = 'UNCLASSIFIED'
    }
    $report.status = 'OBSERVED'
    $report.phase = 'COMPLETE'
} catch {
    # Never emit exception strings, private file paths, or translated cues.
    $report.status = 'HOLD'
}

try {
    $receiptDir = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps\Receipts'
    if (-not (Test-Path -LiteralPath $receiptDir -PathType Container)) {
        throw 'P2_ROOTCAUSE_RECEIPT_DIR_MISSING'
    }
    $target = Join-Path $receiptDir 'p2-block-rootcause-v1.json'
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($report | ConvertTo-Json -Compress))
    if ($bytes.Length -gt 512) { throw 'P2_ROOTCAUSE_RECEIPT_TOO_LARGE' }
    $temp = $target + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllBytes($temp,$bytes)
    [IO.File]::Move($temp,$target,$true)
    Write-Output 'P2_ROOTCAUSE=SANITIZED_RECEIPT_WRITTEN'
} catch {
    Write-Output 'P2_ROOTCAUSE=RECEIPT_WRITE_FAILED'
    exit 1
}
