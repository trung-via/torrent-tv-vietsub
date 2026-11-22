# Trusted /tv-hostops run <exact SHA> owner-laptop-ops-dispatch, Issue #82.
# NETWORK_SERVICE writes a bounded request and starts a separately enrolled
# Owner-interactive task. It never runs source code as the Windows Owner.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $sid -cne 'S-1-5-20') {
    throw 'HOSTOPS_OWNER_OPS_TRUSTED_RUNNER_REQUIRED'
}
$commit = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $commit -cnotmatch '\A[0-9a-f]{40}\z') {
    throw 'HOSTOPS_OWNER_OPS_COMMIT_INVALID'
}
$manifestRel = 'hostops/laptop-ops/manifests/current.json'
$psi = [Diagnostics.ProcessStartInfo]::new()
$psi.FileName = 'git.exe'
$psi.Arguments = 'show HEAD:' + $manifestRel
$psi.WorkingDirectory = $env:GITHUB_WORKSPACE
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$process = [Diagnostics.Process]::Start($psi)
$stream = [IO.MemoryStream]::new()
try {
    $process.StandardOutput.BaseStream.CopyTo($stream)
    $process.WaitForExit()
    if ($process.ExitCode -ne 0 -or $stream.Length -le 0 -or
        $stream.Length -gt 8192) {
        throw 'HOSTOPS_OWNER_OPS_MANIFEST_GIT_BLOB_INVALID'
    }
    $manifestBytes = $stream.ToArray()
} finally { $stream.Dispose(); $process.Dispose() }
$sha256 = [Security.Cryptography.SHA256]::Create()
try {
    $hash = [BitConverter]::ToString($sha256.ComputeHash($manifestBytes)).Replace('-','').ToLowerInvariant()
} finally { $sha256.Dispose() }
# Issue #82 invokes this dispatcher with Windows PowerShell 5.1, whereas the
# Owner task helper uses pwsh 7. Keep the dispatcher 5.1-compatible.
$manifest = [Text.Encoding]::UTF8.GetString($manifestBytes) | ConvertFrom-Json
if (@($manifest.PSObject.Properties.Name | Sort-Object) -join ',' -cne
        'arguments,category,operation,risk,schema,script_path,script_sha256' -or
    $manifest.schema -cne 'TTV-LAPTOP-HOSTOPS-OPERATION-V1' -or
    $manifest.risk -cne 'ROUTINE' -or
    $manifest.operation -cnotmatch '\A[a-z][a-z0-9-]{2,60}\z' -or
    $manifest.category -cnotin @('diagnostics','owner-maintenance',
                                 'development','app-maintenance','device-lan') -or
    $manifest.script_path -cnotmatch
        '\Ahostops/laptop-ops/operations/[a-z][a-z0-9-]*\.ps1\z' -or
    $manifest.script_sha256 -cnotmatch '\A[0-9a-f]{64}\z' -or
    $manifest.arguments -isnot [array] -or $manifest.arguments.Count -gt 8) {
    throw 'HOSTOPS_OWNER_OPS_MANIFEST_NOT_ROUTINE'
}
foreach ($arg in $manifest.arguments) {
    if ($arg -isnot [string] -or $arg -cnotmatch '\A-[A-Za-z][A-Za-z0-9]{0,39}\z') {
        throw 'HOSTOPS_OWNER_OPS_ARGUMENT_INVALID'
    }
}

$name = 'TorrentTV-Vietsub-Laptop-HostOps'
$task = Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue
if ($null -eq $task) {
    Write-Output 'HOSTOPS_OWNER_OPS=HOSTOPS_SETUP_REQUIRED'
    throw 'HOSTOPS_OWNER_OPS_NOT_ENROLLED'
}
$owner = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'
function SidOf([string]$id) {
    if ($id -match '^S-\d+(?:-\d+){2,}$') { return $id }
    return ([Security.Principal.NTAccount]::new($id).Translate(
        [Security.Principal.SecurityIdentifier])).Value
}
if ([string]$task.State -cne 'Ready' -or
    [string]$task.Description -cne 'TTV_LAPTOP_HOSTOPS_OWNER_INTERACTIVE_ROUTINE_V1' -or
    [string]$task.Principal.LogonType -ine 'Interactive' -or
    [string]$task.Principal.RunLevel -ine 'Limited' -or
    [string]$task.Settings.MultipleInstances -ine 'IgnoreNew' -or
    (SidOf ([string]$task.Principal.UserId)) -cne
        (SidOf ([string]$owner.Principal.UserId)) -or
    @($task.Actions).Count -ne 1 -or
    ($null -ne $task.Triggers -and @($task.Triggers).Count -ne 0)) {
    throw 'HOSTOPS_OWNER_OPS_TASK_IDENTITY_DRIFT'
}
$action = @($task.Actions)[0]
if (-not [IO.Path]::GetFileName([string]$action.Execute).Equals(
        'pwsh.exe', [StringComparison]::OrdinalIgnoreCase) -or
    [string]$action.Arguments -cnotmatch
        '\A-NoLogo -NoProfile -NonInteractive -File "[A-Z]:\\[^"\r\n]*\\TorrentTVVietsub\\OwnerBridge\\Maintenance\\owner-laptop-ops-helper\.ps1"\z') {
    throw 'HOSTOPS_OWNER_OPS_TASK_ACTION_DRIFT'
}

$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$inbox = Join-Path $spool 'Requests'
$outbox = Join-Path $spool 'Receipts'
foreach ($dir in @($inbox,$outbox)) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container) -or
        ((Get-Item -LiteralPath $dir -Force).Attributes -band
            [IO.FileAttributes]::ReparsePoint)) {
        throw 'HOSTOPS_OWNER_OPS_SPOOL_NOT_ENROLLED'
    }
}
$requestFile = Join-Path $inbox 'request.json'
$receiptFile = Join-Path $outbox 'receipt.json'
$history = Join-Path $spool 'History'
if (Test-Path -LiteralPath $requestFile) {
    if (-not (Test-Path -LiteralPath $receiptFile -PathType Leaf)) {
        throw 'HOSTOPS_OWNER_OPS_UNRESOLVED_PREVIOUS_REQUEST'
    }
    $oldRequest = Get-Content -LiteralPath $requestFile -Raw | ConvertFrom-Json
    $oldReceipt = Get-Content -LiteralPath $receiptFile -Raw | ConvertFrom-Json
    if ($oldRequest.nonce -cne $oldReceipt.nonce -or
        $oldReceipt.result -cnotin @('SUCCESS','FAILED_NO_RETRY')) {
        throw 'HOSTOPS_OWNER_OPS_UNRESOLVED_PREVIOUS_REQUEST'
    }
    # Archive the service-owned request. The Owner-owned receipt has a
    # different ACL and must be COPIED, not moved by NETWORK_SERVICE.
    if (-not (Test-Path -LiteralPath $history -PathType Container)) {
        New-Item -ItemType Directory -Path $history -ErrorAction Stop | Out-Null
    }
    $oldRequestArchive = Join-Path $history ('request-' + $oldRequest.nonce + '.json')
    if (Test-Path -LiteralPath $oldRequestArchive) {
        throw 'HOSTOPS_OWNER_OPS_REQUEST_ARCHIVE_ALREADY_EXISTS'
    }
    Move-Item -LiteralPath $requestFile -Destination $oldRequestArchive -ErrorAction Stop
}
if (Test-Path -LiteralPath $receiptFile) {
    # Also recover the interrupted state where the prior request was moved
    # but moving its Owner-owned receipt was denied. Never erase that proof.
    $item = Get-Item -LiteralPath $receiptFile -Force -ErrorAction Stop
    if ($item.Length -le 0 -or $item.Length -gt 512 -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'HOSTOPS_OWNER_OPS_PREVIOUS_RECEIPT_INVALID'
    }
    $oldReceipt = Get-Content -LiteralPath $receiptFile -Raw | ConvertFrom-Json
    if ($oldReceipt.schema -cne 'TTV-LAPTOP-HOSTOPS-RECEIPT-V1' -or
        $oldReceipt.nonce -cnotmatch '\A[0-9a-f]{32}\z' -or
        $oldReceipt.result -cnotin @('SUCCESS','FAILED_NO_RETRY')) {
        throw 'HOSTOPS_OWNER_OPS_PREVIOUS_RECEIPT_NOT_TERMINAL'
    }
    $oldRequestArchive = Join-Path $history ('request-' + $oldReceipt.nonce + '.json')
    if (-not (Test-Path -LiteralPath $oldRequestArchive -PathType Leaf)) {
        throw 'HOSTOPS_OWNER_OPS_PREVIOUS_REQUEST_ARCHIVE_MISSING'
    }
    $archivedRequest = Get-Content -LiteralPath $oldRequestArchive -Raw | ConvertFrom-Json
    if ($archivedRequest.nonce -cne $oldReceipt.nonce -or
        $archivedRequest.source_commit -cne $oldReceipt.source_commit) {
        throw 'HOSTOPS_OWNER_OPS_ARCHIVED_REQUEST_RECEIPT_MISMATCH'
    }
    $oldReceiptArchive = Join-Path $history ('receipt-' + $oldReceipt.nonce + '.json')
    if (-not (Test-Path -LiteralPath $oldReceiptArchive)) {
        Copy-Item -LiteralPath $receiptFile -Destination $oldReceiptArchive -ErrorAction Stop
    }
    if ((Get-FileHash -LiteralPath $receiptFile -Algorithm SHA256).Hash -cne
        (Get-FileHash -LiteralPath $oldReceiptArchive -Algorithm SHA256).Hash) {
        throw 'HOSTOPS_OWNER_OPS_RECEIPT_ARCHIVE_HASH_MISMATCH'
    }
    Write-Output 'HOSTOPS_OWNER_OPS=TERMINAL_RECEIPT_COPIED_NO_DELETE'
}
$nonce = [Guid]::NewGuid().ToString('N')
$request = [ordered]@{
    schema = 'TTV-LAPTOP-HOSTOPS-REQUEST-V1'
    nonce = $nonce
    source_commit = $commit
    manifest_path = $manifestRel
    manifest_sha256 = $hash
    requested_utc_epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
}
$bytes = [Text.UTF8Encoding]::new($false).GetBytes(($request | ConvertTo-Json -Compress))
if ($bytes.Length -gt 1024) { throw 'HOSTOPS_OWNER_OPS_REQUEST_TOO_LARGE' }
$temp = Join-Path $inbox ('request-' + $nonce + '.tmp')
[IO.File]::WriteAllBytes($temp, $bytes)
[IO.File]::Move($temp, $requestFile)
Start-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop
Write-Output 'HOSTOPS_OWNER_OPS=OWNER_TASK_TRIGGERED'
# A maintenance transaction may include two independently bounded health
# observations and rollback. The former 200 s bound expired during recovery
# and mislabeled the completed Owner-side operation as an unknown effect.
# Diagnostic jobs retain the short bound; no retry is issued on expiry.
$waitSeconds = if ($manifest.category -ceq 'owner-maintenance') { 600 } else { 200 }
for ($i=0; $i -lt $waitSeconds; $i++) {
    Start-Sleep -Seconds 1
    if (-not (Test-Path -LiteralPath $receiptFile -PathType Leaf)) { continue }
    $item = Get-Item -LiteralPath $receiptFile -Force
    if ($item.Length -gt 512 -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
    $receipt = Get-Content -LiteralPath $receiptFile -Raw | ConvertFrom-Json
    if ($receipt.schema -cne 'TTV-LAPTOP-HOSTOPS-RECEIPT-V1' -or
        $receipt.nonce -cne $nonce -or
        $receipt.source_commit -cne $commit) { continue }
    if ($receipt.result -cne 'SUCCESS') {
        Write-Output 'HOSTOPS_OWNER_OPS=FAILED_NO_RETRY_PRIVATE_LOG'
        if ($receipt.diagnostic -cmatch '^OWNER_FULL_DIAG_FAILURE_PHASE=(REPLACE_FILES|OFFLINE_IMPORT|FRESH_OWNER_START|FULL_LOG_VERIFY)$') {
            Write-Output $receipt.diagnostic
        }
        throw 'HOSTOPS_OWNER_OPS_OWNER_TASK_FAILED'
    }
    Write-Output 'HOSTOPS_OWNER_OPS=SUCCESS_OWNER_PRIVATE_LOG'
    Write-Output ('HOSTOPS_OWNER_OPS_OPERATION=' + $receipt.operation)
    if ($receipt.operation -ceq 'owner-title178-diagnostic') {
        # Strictly bounded Owner-produced enum. Never print private log text.
        $summaryFile = Join-Path $outbox 'title178-diag.json'
        if (Test-Path -LiteralPath $summaryFile -PathType Leaf) {
            $item = Get-Item -LiteralPath $summaryFile -Force
            if ($item.Length -gt 0 -and $item.Length -le 512 -and
                -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $summary = Get-Content -LiteralPath $summaryFile -Raw | ConvertFrom-Json
                if ($summary.schema -ceq 'TTV-OWNER-TITLE178-DIAG-V4' -and
                    $summary.nonce -ceq $nonce -and
                    $summary.code -cmatch '^[A-Z0-9_]{3,80}$' -and
                    $summary.primary -cmatch '^[A-Z0-9_]{3,80}$' -and
                    [int]$summary.new_count -ge 0 -and [int]$summary.new_count -le 6 -and
                    $summary.backup -cin @('NOT_PROVEN','ORIGINAL_SIX_MATCH','BACKUP_DIFFERS') -and
                    $summary.task -cin @('UNKNOWN','RUNNING','READY','NOT_RUNNING') -and
                    $summary.health -cin @('NOT_VERIFIED','READY_FRESH','READY_STALE') -and
                    $summary.import_issue -cmatch '^[A-Z0-9_]{3,90}$' -and
                    $summary.health_identity -cin @('NOT_VERIFIED','PID_NOT_FOUND',
                        'CMDLINE_MISMATCH','PID_SID_MATCH','PID_SID_MISMATCH')) {
                    Write-Output ('HOSTOPS_OWNER_TITLE178_DIAG=' + $summary.code)
                    Write-Output ('HOSTOPS_OWNER_TITLE178_PRIMARY=' + $summary.primary)
                    Write-Output ('HOSTOPS_OWNER_TITLE178_NEW_MODULES=' + [int]$summary.new_count + '/6')
                    Write-Output ('HOSTOPS_OWNER_TITLE178_BACKUP=' + $summary.backup)
                    Write-Output ('HOSTOPS_OWNER_TITLE178_TASK=' + $summary.task)
                    Write-Output ('HOSTOPS_OWNER_TITLE178_HEALTH=' + $summary.health)
                    Write-Output ('HOSTOPS_OWNER_TITLE178_IMPORT_ISSUE=' + $summary.import_issue)
                    Write-Output ('HOSTOPS_OWNER_TITLE178_HEALTH_IDENTITY=' + $summary.health_identity)
                }
            }
        }
    }
    if ($receipt.operation -ceq 'owner-p2-source-trace-readonly') {
        $summaryFile = Join-Path $outbox 'source-trace.json'
        if (Test-Path -LiteralPath $summaryFile -PathType Leaf) {
            $item = Get-Item -LiteralPath $summaryFile -Force
            if ($item.Length -gt 0 -and $item.Length -le 512 -and
                -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $summary = Get-Content -LiteralPath $summaryFile -Raw | ConvertFrom-Json
                $expected = @('schema','nonce','scope','title_source','search',
                    'route','download','cached','en_source','p2_outcome')
                if ($summary.schema -ceq 'TTV-OWNER-SOURCE-TRACE-V1' -and
                    $summary.nonce -ceq $nonce -and
                    (@($summary.PSObject.Properties.Name | Sort-Object) -join ',') -ceq
                        (@($expected | Sort-Object) -join ',') -and
                    $summary.scope -cin @('NOT_OBSERVED','CURRENT_OWNER_REQUEST',
                        'SESSION_NOT_IN_TAIL','OWNER_HEALTH_UNVERIFIED') -and
                    $summary.title_source -cin @('NOT_OBSERVED','TORRENT_ALIAS','VIDEO_FILENAME') -and
                    $summary.search -cin @('NOT_OBSERVED','NO_TITLE','ROUTE_EVALUATED') -and
                    $summary.route -cin @('NOT_OBSERVED','VI_READY','EN_TRANSLATE',
                        'REVIEW_REQUIRED','NO_MATCH') -and
                    $summary.download -cin @('YES','NO') -and
                    $summary.cached -cin @('YES','NO') -and
                    $summary.en_source -cin @('NOT_OBSERVED','LOCAL_DIRECT',
                        'TORRENT_SIDECAR','CACHED') -and
                    $summary.p2_outcome -cin @('NOT_OBSERVED','VI_READY',
                        'VIETSUB_READY','REVIEW_REQUIRED')) {
                    Write-Output ('HOSTOPS_OWNER_SOURCE_SCOPE=' + $summary.scope)
                    Write-Output ('HOSTOPS_OWNER_SOURCE_TITLE=' + $summary.title_source)
                    Write-Output ('HOSTOPS_OWNER_SOURCE_SEARCH=' + $summary.search)
                    Write-Output ('HOSTOPS_OWNER_SOURCE_ROUTE=' + $summary.route)
                    Write-Output ('HOSTOPS_OWNER_SOURCE_DOWNLOAD=' + $summary.download)
                    Write-Output ('HOSTOPS_OWNER_SOURCE_CACHED=' + $summary.cached)
                    Write-Output ('HOSTOPS_OWNER_SOURCE_EN_SOURCE=' + $summary.en_source)
                    Write-Output ('HOSTOPS_OWNER_SOURCE_P2_OUTCOME=' + $summary.p2_outcome)
                }
            }
        }
    }
    if ($receipt.operation -ceq 'owner-p2-live-candidates-readonly') {
        $summaryFile = Join-Path $outbox 'live-candidates.json'
        if (Test-Path -LiteralPath $summaryFile -PathType Leaf) {
            $item = Get-Item -LiteralPath $summaryFile -Force
            if ($item.Length -gt 0 -and $item.Length -le 1024 -and
                -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $summary = Get-Content -LiteralPath $summaryFile -Raw | ConvertFrom-Json
                $expected = @('schema','nonce','scope','p3','route','reason',
                    'vi_rows','vi_ranked','vi_confident','en_rows','en_total',
                    'en_ranked','en_confident','en_top_score','en_top_confident',
                    'en_top_source','en_top_year','en_top_group',
                    'en_top_resolution','en_top_codec','download','cached','p2','p4')
                $countFields = @('vi_rows','vi_ranked','vi_confident',
                    'en_rows','en_total','en_ranked','en_confident','en_top_score')
                $matchFields = @('en_top_source','en_top_year','en_top_group',
                    'en_top_resolution','en_top_codec')
                $valid = $summary.schema -ceq 'TTV-OWNER-P2-LIVE-CANDIDATES-V1' -and
                    $summary.nonce -ceq $nonce -and
                    (@($summary.PSObject.Properties.Name | Sort-Object) -join ',') -ceq
                        (@($expected | Sort-Object) -join ',') -and
                    $summary.scope -cin @('NOT_OBSERVED','PRIVATE_LOG_UNAVAILABLE',
                        'OWNER_HEALTH_NOT_FRESH','SESSION_NOT_IN_TAIL',
                        'NO_DISPATCH_SINCE_RESTART','CURRENT_OWNER_SESSION','LOCAL_READ_ERROR') -and
                    $summary.p3 -cin @('NOT_OBSERVED','DISPATCHED') -and
                    $summary.route -cin @('NOT_OBSERVED','VI_READY','EN_TRANSLATE',
                        'REVIEW_REQUIRED','NO_MATCH') -and
                    $summary.reason -cin @('NOT_OBSERVED','CONFIDENT_VI_RELEASE',
                        'CONFIDENT_EN_RELEASE','EN_COVERAGE_INCOMPLETE',
                        'NO_CONFIDENT_UNAMBIGUOUS_RELEASE','NO_RANKABLE_SUBTITLES',
                        'VI_COVERAGE_INCOMPLETE') -and
                    $summary.en_top_confident -cin @('NOT_OBSERVED','YES','NO') -and
                    $summary.download -cin @('YES','NO') -and
                    $summary.cached -cin @('YES','NO') -and
                    $summary.p2 -cin @('NOT_OBSERVED','CLAIMED','BLOCKED',
                        'VI_READY','VIETSUB_READY','REVIEW_REQUIRED') -and
                    $summary.p4 -cin @('NOT_OBSERVED','REVISION_READY')
                foreach ($field in $matchFields) {
                    if ($summary.$field -cnotin @('NOT_OBSERVED','MATCH',
                            'MISSING','CONFLICT')) { $valid = $false }
                }
                foreach ($field in $countFields) {
                    if ($summary.$field -isnot [ValueType] -or
                        [int]$summary.$field -lt -1 -or
                        [int]$summary.$field -gt 10000000) { $valid = $false }
                }
                if ($valid) {
                    foreach ($field in @('scope','p3','route','reason')) {
                        Write-Output ('HOSTOPS_LIVE_CANDIDATE_' +
                            $field.ToUpperInvariant() + '=' + $summary.$field)
                    }
                    foreach ($field in $countFields) {
                        Write-Output ('HOSTOPS_LIVE_CANDIDATE_' +
                            $field.ToUpperInvariant() + '=' + [int]$summary.$field)
                    }
                    foreach ($field in (@('en_top_confident') + $matchFields +
                        @('download','cached','p2','p4'))) {
                        Write-Output ('HOSTOPS_LIVE_CANDIDATE_' +
                            $field.ToUpperInvariant() + '=' + $summary.$field)
                    }
                } else { throw 'HOSTOPS_LIVE_CANDIDATE_RECEIPT_INVALID' }
            }
        }
    }
    if ($receipt.operation -ceq 'owner-p2-candidate-audit-readonly') {
        $summaryFile = Join-Path $outbox 'candidate-audit.json'
        if (Test-Path -LiteralPath $summaryFile -PathType Leaf) {
            $item = Get-Item -LiteralPath $summaryFile -Force
            if ($item.Length -gt 0 -and $item.Length -le 1024 -and
                -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $summary = Get-Content -LiteralPath $summaryFile -Raw | ConvertFrom-Json
                $expected = @('schema','nonce','state','route','reason','title',
                    'vi_rows','vi_ranked','vi_confident','en_rows','en_ranked',
                    'en_confident','en_total','top_score','top_source','top_year',
                    'top_group','top_resolution','gap')
                if ($summary.schema -ceq 'TTV-OWNER-CANDIDATE-AUDIT-V1' -and
                    $summary.nonce -ceq $nonce -and
                    (@($summary.PSObject.Properties.Name | Sort-Object) -join ',') -ceq
                        (@($expected | Sort-Object) -join ',') -and
                    $summary.state -cmatch '^[A-Z0-9_]{3,60}$' -and
                    $summary.route -cin @('UNKNOWN','VI_READY','EN_TRANSLATE','REVIEW_REQUIRED','NO_MATCH') -and
                    $summary.reason -cmatch '^[A-Z0-9_]{3,60}$' -and
                    $summary.title -cin @('UNKNOWN','TORRENT_ALIAS','FILENAME') -and
                    $summary.top_source -cin @('UNKNOWN','MATCH','MISSING','CONFLICT') -and
                    $summary.top_year -cin @('UNKNOWN','MATCH','MISSING','CONFLICT') -and
                    $summary.top_group -cin @('UNKNOWN','MATCH','MISSING','CONFLICT') -and
                    $summary.top_resolution -cin @('UNKNOWN','MATCH','MISSING','CONFLICT')) {
                    Write-Output ('HOSTOPS_CANDIDATE_STATE=' + $summary.state)
                    Write-Output ('HOSTOPS_CANDIDATE_ROUTE=' + $summary.route)
                    Write-Output ('HOSTOPS_CANDIDATE_REASON=' + $summary.reason)
                    Write-Output ('HOSTOPS_CANDIDATE_TITLE=' + $summary.title)
                    foreach ($field in @('vi_rows','vi_ranked','vi_confident',
                          'en_rows','en_ranked','en_confident','en_total',
                          'top_score','gap')) {
                        if ($summary.$field -is [ValueType] -and
                            [int]$summary.$field -ge -1 -and
                            [int]$summary.$field -le 10000000) {
                            Write-Output ('HOSTOPS_CANDIDATE_' +
                                $field.ToUpperInvariant() + '=' + [int]$summary.$field)
                        }
                    }
                    foreach ($field in @('top_source','top_year','top_group','top_resolution')) {
                        Write-Output ('HOSTOPS_CANDIDATE_' +
                            $field.ToUpperInvariant() + '=' + $summary.$field)
                    }
                }
            }
        }
    }
    if ($receipt.operation -cin @('owner-p2-selector-178-install',
                                 'owner-p2-coverage-178-install')) {
        $summaryFile = Join-Path $outbox 'selector-install.json'
        if (Test-Path -LiteralPath $summaryFile -PathType Leaf) {
            $item = Get-Item -LiteralPath $summaryFile -Force
            if ($item.Length -gt 0 -and $item.Length -le 512 -and
                -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $summary = Get-Content -LiteralPath $summaryFile -Raw | ConvertFrom-Json
                $expected = @('schema','nonce','result','installed_modules','owner')
                $codes = @('PREFLIGHT_PASS_NO_STOP','ALREADY_INSTALLED',
                    'INSTALLED_OWNER_READY','ROLLED_BACK_OWNER_READY',
                    'SELECTOR_PENDING_OWNER_EVENT','SELECTOR_P2_ACTIVE_OR_UNCERTAIN',
                    'SELECTOR_INSTALLED_BASELINE_DRIFT',
                    'SELECTOR_PARTIAL_INSTALL_NEEDS_RECONCILIATION',
                    'SELECTOR_OWNER_TASK_NOT_RUNNABLE',
                    'SELECTOR_READY_TASK_WITHOUT_OWNER',
                    'SELECTOR_READY_OWNER_IDENTITY_DRIFT',
                    'SELECTOR_STAGED_IMPORT_FAILED','SELECTOR_SOURCE_HASH_DRIFT')
                if ($summary.schema -ceq 'TTV-OWNER-SELECTOR-INSTALL-V1' -and
                    $summary.nonce -ceq $nonce -and
                    (@($summary.PSObject.Properties.Name | Sort-Object) -join ',') -ceq
                        (@($expected | Sort-Object) -join ',') -and
                    $summary.result -cin $codes -and
                    [int]$summary.installed_modules -in @(0,2) -and
                    $summary.owner -cin @('RUNNING_READY','NOT_PROVEN')) {
                    Write-Output ('HOSTOPS_OWNER_SELECTOR_INSTALL=' + $summary.result)
                    Write-Output ('HOSTOPS_OWNER_SELECTOR_MODULES=' + [int]$summary.installed_modules + '/2')
                    Write-Output ('HOSTOPS_OWNER_SELECTOR_OWNER=' + $summary.owner)
                }
            }
        }
    }
    if ($receipt.operation -ceq 'owner-p2-selector-install-diagnostic') {
        $summaryFile = Join-Path $outbox 'selector-diag.json'
        if (Test-Path -LiteralPath $summaryFile -PathType Leaf) {
            $item = Get-Item -LiteralPath $summaryFile -Force
            if ($item.Length -gt 0 -and $item.Length -le 512 -and
                -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $summary = Get-Content -LiteralPath $summaryFile -Raw | ConvertFrom-Json
                $expected = @('schema','nonce','flow','matcher','backup','task',
                    'health','p2_busy','failure')
                if ($summary.schema -ceq 'TTV-OWNER-SELECTOR-DIAG-V1' -and
                    $summary.nonce -ceq $nonce -and
                    (@($summary.PSObject.Properties.Name | Sort-Object) -join ',') -ceq
                        (@($expected | Sort-Object) -join ',') -and
                    $summary.flow -cin @('OLD','NEW','MISSING_OR_OTHER') -and
                    $summary.matcher -cin @('OLD','NEW','MISSING_OR_OTHER') -and
                    $summary.backup -cin @('NOT_OBSERVED','INCOMPLETE','ORIGINAL_TWO_MATCH') -and
                    $summary.task -cin @('Running','Ready','Disabled','OTHER') -and
                    $summary.health -cin @('NOT_PROVEN','STALE','READY_PID_SID_MATCH') -and
                    $summary.p2_busy -cin @('YES','NO','UNKNOWN') -and
                    $summary.failure -cin @('NOT_OBSERVED','ROLLBACK_UNCERTAIN',
                        'FAILED_BEFORE_STOP','ROLLED_BACK','FILE_REPLACE_ERROR',
                        'OWNER_FAILURE_UNCLASSIFIED','PRIVATE_LOG_MISSING')) {
                    Write-Output ('HOSTOPS_SELECTOR_DIAG_FLOW=' + $summary.flow)
                    Write-Output ('HOSTOPS_SELECTOR_DIAG_MATCHER=' + $summary.matcher)
                    Write-Output ('HOSTOPS_SELECTOR_DIAG_BACKUP=' + $summary.backup)
                    Write-Output ('HOSTOPS_SELECTOR_DIAG_TASK=' + $summary.task)
                    Write-Output ('HOSTOPS_SELECTOR_DIAG_HEALTH=' + $summary.health)
                    Write-Output ('HOSTOPS_SELECTOR_DIAG_P2_BUSY=' + $summary.p2_busy)
                    Write-Output ('HOSTOPS_SELECTOR_DIAG_FAILURE=' + $summary.failure)
                }
            }
        }
    }
    if ($receipt.operation -ceq 'owner-selector-task-enable-recovery') {
        $summaryFile = Join-Path $outbox 'selector-recovery.json'
        if (Test-Path -LiteralPath $summaryFile -PathType Leaf) {
            $item = Get-Item -LiteralPath $summaryFile -Force
            if ($item.Length -gt 0 -and $item.Length -le 512 -and
                -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $summary = Get-Content -LiteralPath $summaryFile -Raw | ConvertFrom-Json
                $expected = @('schema','nonce','task','owner','version')
                if ($summary.schema -ceq 'TTV-OWNER-SELECTOR-RECOVERY-V1' -and
                    $summary.nonce -ceq $nonce -and
                    (@($summary.PSObject.Properties.Name | Sort-Object) -join ',') -ceq
                        (@($expected | Sort-Object) -join ',') -and
                    $summary.task -ceq 'ENABLED' -and
                    $summary.owner -ceq 'PRESERVED_RUNNING_VERIFIED' -and
                    $summary.version -ceq 'OLD_TWO') {
                    Write-Output 'HOSTOPS_SELECTOR_RECOVERY_TASK=ENABLED'
                    Write-Output 'HOSTOPS_SELECTOR_RECOVERY_OWNER=PRESERVED_RUNNING_VERIFIED'
                    Write-Output 'HOSTOPS_SELECTOR_RECOVERY_VERSION=OLD_TWO'
                }
            }
        }
    }
    return
}
throw 'HOSTOPS_OWNER_OPS_TIMEOUT_UNKNOWN_EFFECT_NO_RETRY'
