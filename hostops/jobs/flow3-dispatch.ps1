# Reusable Flow3 ingress on trusted main. Reuses existing Owner task and receipt spool.
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

$manifest = [Text.Encoding]::UTF8.GetString($manifestBytes) | ConvertFrom-Json
if($manifest.schema -cne 'TTV-LAPTOP-HOSTOPS-OPERATION-V1' -or
   $manifest.operation -cne 'owner-flow3-dispatch' -or
   $manifest.script_path -cne 'hostops/laptop-ops/operations/flow3-dispatch.ps1' -or
   $manifest.category -cne 'device-lan' -or $manifest.risk -cne 'ROUTINE' -or
   $manifest.arguments.Count -ne 0 -or $manifest.script_sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'FLOW3_MANIFEST'}
$operationFile=Join-Path $env:GITHUB_WORKSPACE ($manifest.script_path.Replace('/','\'))
# Verify the committed bytes, not the potentially CRLF-converted checkout.
$tokens=$null;$errors=$null
[Management.Automation.Language.Parser]::ParseFile($operationFile,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count -ne 0){throw 'FLOW3_OPERATION_PARSE'}
$py='C:\Program Files\Python314\python.exe'
$payloadJson=(& $py -I -B -c 'import sys,os,json;sys.path.insert(0,os.path.join(os.environ["GITHUB_WORKSPACE"],"poc","p2-source"));from flow3_ingress import build_request;print(json.dumps(build_request(os.environ["HOSTOPS_REQUEST"].strip(),os.environ["HOSTOPS_COMMENT_ID"]),ensure_ascii=True))' 2>$null | Out-String).Trim()
if($LASTEXITCODE -ne 0 -or -not $payloadJson){throw 'FLOW3_COMMAND_INVALID'}
$payload=$payloadJson|ConvertFrom-Json
$nonce=[string]$payload.request_id
if($nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'FLOW3_REQUEST_ID'}
$name = 'TorrentTV-Vietsub-Laptop-HostOps'
$task = Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue

if($null -eq $task){throw 'HOSTOPS_OWNER_OPS_NOT_ENROLLED'}
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

# The comment identity is stable even if Actions is rerun. Never resubmit it.
$payloadFile=Join-Path $inbox ('flow3-'+$nonce+'.json')
if((Test-Path -LiteralPath $payloadFile) -or (Test-Path -LiteralPath (Join-Path $history ('request-'+$nonce+'.json')))){
    Write-Output 'FLOW3_PRIOR_REQUEST_NO_REPLAY'
    return
}
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


# A single sidecar carries only data; installed helper request schema is unchanged.
$bytes=[Text.UTF8Encoding]::new($false).GetBytes($payloadJson)
$fs=[IO.File]::Open($payloadFile,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$fs.Write($bytes,0,$bytes.Length);$fs.Flush($true)}finally{$fs.Dispose()}
$request=[ordered]@{
    schema='TTV-LAPTOP-HOSTOPS-REQUEST-V1'
    nonce=$nonce
    source_commit=$commit
    manifest_path=$manifestRel
    manifest_sha256=$hash
    requested_utc_epoch=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
}
$temp=Join-Path $inbox ('request-'+$nonce+'.tmp')
[IO.File]::WriteAllBytes($temp,[Text.UTF8Encoding]::new($false).GetBytes(($request|ConvertTo-Json -Compress)))
[IO.File]::Move($temp,$requestFile)
Start-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop
Write-Output 'FLOW3_OWNER_DISPATCHED'
$deadline=[DateTimeOffset]::UtcNow.AddMinutes(7)
while([DateTimeOffset]::UtcNow -lt $deadline){
    Start-Sleep -Seconds 1
    if(-not (Test-Path -LiteralPath $receiptFile -PathType Leaf)){continue}
    $v=Get-Content -LiteralPath $receiptFile -Raw|ConvertFrom-Json
    if($v.schema -cne 'TTV-LAPTOP-HOSTOPS-RECEIPT-V1' -or $v.nonce -cne $nonce -or $v.source_commit -cne $commit){continue}
    if($v.operation -cne $manifest.operation -or $v.result -cne 'SUCCESS'){throw 'FLOW3_OWNER_FAILED_NO_REPLAY'}
    $stageFile=Join-Path $outbox ('odyssey-stage-'+$nonce+'.json')
    $s=Get-Content -LiteralPath $stageFile -Raw|ConvertFrom-Json
    if($s.schema -cne 'TTV-ODYSSEY-STAGE-V1' -or $s.nonce -cne $nonce -or $s.reason -cnotmatch '^FLOW3_[A-Z0-9_]{3,84}$'){throw 'FLOW3_STAGE_INVALID'}
    Write-Output ('FLOW3_STAGE='+$s.reason)
    if($s.reason -ceq 'FLOW3_LIBRARY_READY' -and $payload.schema -ceq 'TTV-OWNER-G2-CONCIERGE-V1'){
        & pwsh -NoLogo -NoProfile -NonInteractive -File (Join-Path $env:GITHUB_WORKSPACE 'poc\p2-source\owner_movie_flow.ps1') -RequestId $nonce
        if($LASTEXITCODE -ne 0){throw 'FLOW3_PLAY_HOLD_NO_REPLAY'}
    }
    return
}
throw 'FLOW3_RECEIPT_PENDING_NO_REPLAY'
