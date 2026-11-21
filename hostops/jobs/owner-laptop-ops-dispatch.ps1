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
for ($i=0; $i -lt 200; $i++) {
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
    return
}
throw 'HOSTOPS_OWNER_OPS_TIMEOUT_UNKNOWN_EFFECT_NO_RETRY'
