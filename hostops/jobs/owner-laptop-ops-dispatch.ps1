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

# Parse the exact checked-out operation before sending it to Owner.
$operationFile = Join-Path $env:GITHUB_WORKSPACE ($manifest.script_path.Replace('/', '\'))
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($operationFile, [ref]$tokens, [ref]$parseErrors) | Out-Null
if (@($parseErrors).Count -ne 0) { throw 'HOSTOPS_OWNER_OPS_OPERATION_PARSE_FAILED' }
Write-Output 'HOSTOPS_OWNER_OPS_OPERATION_PARSE=PASS'
$name = 'TorrentTV-Vietsub-Laptop-HostOps'
$task = Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue
if ($manifest.operation -ceq 'owner-ts-ebml-range-readonly') {
    # This probe only reads selected-file metadata and bounded byte ranges.
    # This read-only probe never triggers an Owner task or modifies the spool.
    $relative = 'hostops/laptop-ops/operations/owner-ts-ebml-range-readonly.ps1'
    if ($manifest.script_path -cne $relative -or
        $manifest.category -cne 'diagnostics' -or
        $manifest.arguments.Count -ne 0) {
        throw 'EBML_PROBE_MANIFEST_DRIFT'
    }
    $reader = Join-Path $env:GITHUB_WORKSPACE ($relative.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $reader -PathType Leaf)) {
        throw 'EBML_PROBE_READER_MISSING'
    }
    $expectedBlob = (& git rev-parse ('HEAD:' + $relative)).Trim()
    $actualBlob = (& git hash-object --path=$relative $reader).Trim()
    if ($expectedBlob -cnotmatch '^[0-9a-f]{40}$' -or
        $expectedBlob -cne $actualBlob) {
        throw 'EBML_PROBE_SOURCE_DRIFT'
    }
    & $reader
    Write-Output 'HOSTOPS_EBML_DISPATCH_READONLY_PASS'
    return
}
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
# Teacher receipt-only observation. This path never triggers, archives or edits a request.
# Scope is the exact approved no-deadline Teacher operation, not all HostOps jobs.
if ($manifest.operation -ceq 'tr-ttv-teacher-receipt-readonly') {
    if ($manifest.category -cne 'diagnostics' -or $manifest.arguments.Count -ne 0 -or
        $manifest.script_path -cne 'hostops/laptop-ops/operations/tr-ttv-04b-teacher-no-deadline.ps1') {
        throw 'HOSTOPS_TEACHER_RECEIPT_MANIFEST_DRIFT'
    }
    $spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
    $inbox = Join-Path $spool 'Requests'
    $outbox = Join-Path $spool 'Receipts'
    foreach ($dir in @($inbox,$outbox)) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container) -or
            ((Get-Item -LiteralPath $dir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'HOSTOPS_OWNER_OPS_SPOOL_NOT_ENROLLED'
        }
    }
    $requestFile = Join-Path $inbox 'request.json'
    $receiptFile = Join-Path $outbox 'receipt.json'
    if (-not (Test-Path -LiteralPath $requestFile -PathType Leaf)) { throw 'HOSTOPS_TEACHER_REQUEST_MISSING' }
    $item=Get-Item -LiteralPath $requestFile -Force
    if ($item.Length -le 0 -or $item.Length -gt 1024 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'HOSTOPS_TEACHER_REQUEST_INVALID' }
    $request=Get-Content -LiteralPath $requestFile -Raw | ConvertFrom-Json
    if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $request.nonce -cnotmatch '\A[a-f0-9]{32}\z' -or $request.source_commit -cnotmatch '\A[a-f0-9]{40}\z') { throw 'HOSTOPS_TEACHER_REQUEST_INVALID' }
    # Resolve the original pinned manifest; never act on a different operation.
    $orig = (& git show ($request.source_commit + ':hostops/laptop-ops/manifests/current.json') | Out-String)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($orig)) { throw 'HOSTOPS_TEACHER_SOURCE_NOT_AVAILABLE' }
    $origManifest = $orig | ConvertFrom-Json
    if ($origManifest.operation -cne 'agy-native-browser-readout-1124' -or $origManifest.script_path -cnotin @('hostops/laptop-ops/operations/tr-ttv-04b-teacher-no-deadline.ps1','hostops/laptop-ops/operations/tr-ttv-06-student-v3.ps1')) { throw 'HOSTOPS_TEACHER_REQUEST_WRONG_OPERATION' }
    Write-Output ('HOSTOPS_TEACHER_SOURCE=' + $request.source_commit)
    Write-Output ('HOSTOPS_TEACHER_NONCE=' + $request.nonce)
    $receipt=$null
    if (Test-Path -LiteralPath $receiptFile -PathType Leaf) {
        $item=Get-Item -LiteralPath $receiptFile -Force
        if ($item.Length -gt 0 -and $item.Length -le 512 -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $v=Get-Content -LiteralPath $receiptFile -Raw | ConvertFrom-Json
            if ($v.schema -ceq 'TTV-LAPTOP-HOSTOPS-RECEIPT-V1' -and $v.nonce -ceq $request.nonce -and $v.source_commit -ceq $request.source_commit -and $v.operation -ceq $origManifest.operation -and $v.result -cin @('SUCCESS','FAILED_NO_RETRY')) { $receipt=$v }
        }
    }
    if ($null -eq $receipt) {
        if ([string]$task.State -ceq 'Running') { Write-Output 'HOSTOPS_TEACHER_STATE=RUNNING' }
        else { Write-Output 'HOSTOPS_TEACHER_STATE=PENDING_RECEIPT_UNKNOWN_EFFECT_NO_RETRY' }
        return
    }
    Write-Output ('HOSTOPS_TEACHER_STATE=' + $receipt.result)
    $stage=Join-Path $outbox ('odyssey-stage-' + $request.nonce + '.json')
    if (Test-Path -LiteralPath $stage -PathType Leaf) {
        $item=Get-Item -LiteralPath $stage -Force
        if ($item.Length -gt 0 -and $item.Length -le 1024 -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $v=Get-Content -LiteralPath $stage -Raw | ConvertFrom-Json
            if ($v.schema -ceq 'TTV-ODYSSEY-STAGE-V1' -and $v.nonce -ceq $request.nonce -and $v.reason -cmatch '^[A-Z0-9_]{3,90}$') { Write-Output ('HOSTOPS_ODYSSEY_STAGE=' + $v.reason) }
        }
    }
    return
}
# Wait only for the enrolled routine task to finish; do not stop it or replay it.
# The existing task identity and previous-receipt checks still run after the wait.
if ($manifest.operation -ceq 'owner-production-movie' -and [string]$task.State -ceq 'Running') {
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        Start-Sleep -Seconds 1
        $task = Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue
        if ($null -eq $task) { throw 'HOSTOPS_OWNER_OPS_NOT_ENROLLED' }
    } while ([string]$task.State -ceq 'Running' -and [DateTime]::UtcNow -lt $deadline)
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
# Human-approved recovery of ONE timed-out operation: preserve the original request,
# never fabricate its receipt, and submit only an Owner read-only reconciliation.
if ($manifest.script_path -ceq 'hostops/laptop-ops/operations/owner-control-recovery-readonly.ps1') {
    if ($manifest.category -cne 'diagnostics' -or $manifest.arguments.Count -ne 0 -or
        [string](Get-ScheduledTask -TaskName $name -TaskPath '\').State -cne 'Ready') {
        throw 'OWNER_CONTROL_RECOVERY_NOT_IDLE'
    }
    $old = Get-Content -LiteralPath $requestFile -Raw | ConvertFrom-Json
    if ($old.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
        $old.source_commit -cne '40b23c6556bc4258b69392e6990ba4bca9e16cf3' -or
        $old.nonce -cnotmatch '^[a-f0-9]{32}$') { throw 'OWNER_CONTROL_RECOVERY_WRONG_REQUEST' }
    $last = Get-ScheduledTaskInfo -TaskName $name -TaskPath '\'
    if ($last.LastTaskResult -ne 0 -or
        $last.LastRunTime.ToUniversalTime() -lt [DateTimeOffset]::FromUnixTimeSeconds([long]$old.requested_utc_epoch).UtcDateTime.AddSeconds(-2)) {
        throw 'OWNER_CONTROL_RECOVERY_TASK_RESULT_UNKNOWN'
    }
    if (-not (Test-Path -LiteralPath $history -PathType Container)) {
        New-Item -ItemType Directory -Path $history | Out-Null
    }
    $archive = Join-Path $history ('request-' + $old.nonce + '.json')
    if (Test-Path -LiteralPath $archive) { throw 'OWNER_CONTROL_RECOVERY_ARCHIVE_EXISTS' }
    $archiveHash = (Get-FileHash -LiteralPath $requestFile -Algorithm SHA256).Hash
    Move-Item -LiteralPath $requestFile -Destination $archive -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -cne $archiveHash) {
        throw 'OWNER_CONTROL_RECOVERY_ARCHIVE_HASH'
    }
    $record = Join-Path $history ('unknown-effect-' + $old.nonce + '.json')
    [IO.File]::WriteAllText($record,(@{schema='TTV-HOSTOPS-UNKNOWN-EFFECT-V1';nonce=$old.nonce;source_commit=$old.source_commit;state='ARCHIVED_NO_REPLAY';reconciliation_source=$commit}|ConvertTo-Json -Compress))
    Write-Output 'HOSTOPS_OWNER_CONTROL_TIMEOUT_ARCHIVED_NO_REPLAY'
}
# Verify both exact prior receipts before sending the Owner request.
function Flow3DualTvRead([string]$requiredHash) {
    $devices=@(& $adb devices 2>$null)
    $auth=@($devices|Where-Object{$_ -match '^\S+\s+device(\s|$)'})
    if($LASTEXITCODE -ne 0 -or $auth.Count -ne 1 -or @($devices|Where-Object{$_ -match '^\S+\s+(offline|unauthorized)(\s|$)'}).Count){throw 'DUAL_TV_ADB'}
    $device=($auth[0] -split '\s+')[0]
    if(((& $adb -s $device shell getprop ro.product.model 2>$null)|Out-String).Trim() -cne 'MiTV-ASTR0'){throw 'DUAL_TV_MODEL'}
    $activity=((& $adb -s $device shell dumpsys activity activities 2>$null)|Out-String)
    if($LASTEXITCODE -ne 0){throw 'DUAL_TV_ACTIVITY'}
    if(@($activity -split '\r?\n'|Where-Object{$_ -match 'mResumedActivity|topResumedActivity' -and $_ -match 'com\.spacesarmat\.omp\.test/' -and $_ -match 'PlayerActivity'}).Count){throw 'DUAL_TV_ACTIVE_PLAYBACK'}
    $paths=@(& $adb -s $device shell pm path com.spacesarmat.omp.test 2>$null|ForEach-Object{([string]$_).Trim()})
    if($LASTEXITCODE -ne 0 -or $paths.Count -ne 1 -or $paths[0] -notmatch '^package:(/data/app/[^ \r\n]+/base\.apk)$'){throw 'DUAL_TV_PACKAGE'}
    $remote=$Matches[1]
    $hash=((& $adb -s $device shell sha256sum $remote 2>$null)|Out-String).Trim()
    if($LASTEXITCODE -ne 0 -or $hash -notmatch '^([a-fA-F0-9]{64})\s' -or $Matches[1].ToLowerInvariant() -cne $requiredHash){throw 'DUAL_TV_INSTALLED_HASH'}
    return $device
}
if($manifest.operation -ceq 'owner-flow3-dual-apply'){
    $oldReceipt=Get-Content -LiteralPath $receiptFile -Raw|ConvertFrom-Json
    $oldRequest=Get-Content -LiteralPath $requestFile -Raw|ConvertFrom-Json
    if($oldReceipt.source_commit -cne '5b7a6f98025474a679e0947c9400f8745efe8216' -or $oldReceipt.operation -cne 'owner-flow3-dual-preflight' -or $oldReceipt.result -cne 'SUCCESS' -or $oldReceipt.nonce -cnotmatch '^[a-f0-9]{32}$' -or $oldReceipt.nonce -cne $oldRequest.nonce){throw 'DUAL_PREFLIGHT_RECEIPT'}
    $preNonce=$oldReceipt.nonce
    $cache=Join-Path $env:RUNNER_WORKSPACE '_omp-fast-cache'
    $rollback=Join-Path $cache ('flow3-dual-rollback\'+$preNonce)
    $proof=Get-Content -LiteralPath (Join-Path $rollback 'preflight.json') -Raw|ConvertFrom-Json
    $candidate='d93ca6bfaa25279402ee13a2bc8960d61992c6a4'
    $newsha='9d8ff2c9b34c105b1f74e2419790ff6b02520f92d6aae9fbaf7bea57170858fa'
    $oldsha='5e89c35f730fa9ab4bd18fdfa898b02fbca0240fdaf828ed441d605ab2f082d8'
    if($proof.schema -cne 'TTV-FLOW3-DUAL-TV-PREFLIGHT-V1' -or $proof.nonce -cne $preNonce -or $proof.candidate -cne $candidate -or $proof.new_sha256 -cne $newsha -or $proof.old_sha256 -cne $oldsha -or $proof.signer_match -ne $true -or $proof.player_foreground -ne $false -or $proof.new_version -lt $proof.old_version){throw 'DUAL_TV_PREFLIGHT_PROOF'}
    $apk=Join-Path $cache ('flow3-dual-staged\'+$candidate+'\app-armeabi-v7a-debug.apk')
    $old=Join-Path $rollback 'previous-base.apk'
    if((Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant() -cne $newsha -or (Get-FileHash -LiteralPath $old -Algorithm SHA256).Hash.ToLowerInvariant() -cne $oldsha){throw 'DUAL_APK_STAGE_DRIFT'}
    if(Test-Path -LiteralPath (Join-Path $rollback 'install-intent.json')){throw 'DUAL_PRIOR_INSTALL_RECONCILE'}
    $adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
    $dualDevice=Flow3DualTvRead $oldsha
    Write-Output 'FLOW3_DUAL_TV_RECHECK_PASS'
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

# Single continuous production request: avoid unnecessary provider work if a different player is active.
if ($manifest.operation -ceq 'owner-g2-production-once') {
    $adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
    $devices=@(& $adb devices 2>$null)
    $auth=@($devices|Where-Object{$_ -match '^\S+\s+device(\s|$)'})
    if($LASTEXITCODE -ne 0 -or $auth.Count -ne 1 -or @($devices|Where-Object{$_ -match '^\S+\s+(offline|unauthorized)(\s|$)'}).Count){throw 'G2_PROD_DEVICE_UNAVAILABLE'}
    $serial=($auth[0] -split '\s+')[0]
    if(((& $adb -s $serial shell getprop ro.product.model 2>$null)|Out-String).Trim() -cne 'MiTV-ASTR0'){throw 'G2_PROD_MODEL'}
    $act=((& $adb -s $serial shell dumpsys activity activities 2>$null)|Out-String)
    if($LASTEXITCODE -ne 0){throw 'G2_PROD_ACTIVITY_UNVERIFIED'}
    if(@($act -split '\r?\n'|Where-Object{$_ -match 'mResumedActivity|topResumedActivity' -and $_ -match 'com\.spacesarmat\.omp\.test/' -and $_ -match 'PlayerActivity'}).Count){
        Write-Output 'G2_PROD_HOLD_EXISTING_PLAYER_BEFORE_SUBMIT'
        return
    }
}

$nonce = [Guid]::NewGuid().ToString('N')
if($manifest.operation -ceq 'owner-production-movie'){
    $command=$env:HOSTOPS_REQUEST.Trim()
    if($command -cnotmatch '^/tv-hostops movie ([a-f0-9]{40}) (search|play) ([0-9]{4}) ([\p{L}\p{N}][\p{L}\p{N} .,:!?&()''_-]{0,159})$' -or $Matches[1] -cne $commit){throw 'PRODUCTION_MOVIE_COMMAND'}
    $mode=$Matches[2];$year=[int]$Matches[3];$title=$Matches[4].Trim()
    if($year -lt 1900 -or $year -gt 2100 -or $title.Length -eq 0){throw 'PRODUCTION_MOVIE_INPUT'}
    $event=Get-Content -LiteralPath $env:GITHUB_EVENT_PATH -Raw|ConvertFrom-Json
    if([string]$event.comment.id -cnotmatch '^[0-9]+$'){throw 'PRODUCTION_MOVIE_COMMENT_ID'}
    $nonce=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes('ttv-production-movie-v1:'+ $event.comment.id))).ToLowerInvariant().Substring(0,32)
    $inputFile=Join-Path $inbox ('movie-'+$nonce+'.json')
    if(Test-Path -LiteralPath $inputFile){throw 'PRODUCTION_MOVIE_PRIOR_DISPATCH_RECONCILE'}
    $inputBytes=[Text.UTF8Encoding]::new($false).GetBytes((@{schema='TTV-PRODUCTION-MOVIE-V1';request_id=$nonce;mode=$mode;year=$year;title=$title}|ConvertTo-Json -Compress))
    $fs=[IO.File]::Open($inputFile,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$fs.Write($inputBytes,0,$inputBytes.Length);$fs.Flush($true)}finally{$fs.Dispose()}
    Write-Output 'PRODUCTION_MOVIE_INPUT_ACCEPTED'
}
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
$waitSeconds = if ($manifest.script_path -ceq 'hostops/laptop-ops/operations/bt09d-asr-crosscheck.ps1') { 1500 } elseif ($manifest.script_path -ceq 'hostops/laptop-ops/operations/bt09-movie-audio-qa.ps1') { 1500 } elseif ($manifest.script_path -ceq 'hostops/laptop-ops/operations/tr-ttv-06-student-v3.ps1') { 1200 } elseif ($manifest.category -ceq 'owner-maintenance') { 600 } else { 200 }
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
    if ($receipt.operation -ceq 'owner-current-film-retest-reset') {
        $f=Join-Path $outbox ('retest-result-'+$nonce+'.json')
        if(Test-Path -LiteralPath $f -PathType Leaf){
            $v=Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
            if($v.schema -ceq 'TTV-RETEST-RESULT-V2' -and $v.nonce -ceq $nonce){
                foreach($key in @('status','phase','prior','registry','reason')){
                    if([string]$v.$key -cmatch '^[A-Z0-9_]{2,100}$'){Write-Output ('HOSTOPS_RETEST_'+$key.ToUpperInvariant()+'='+$v.$key)}
                }
                if([int]$v.jobs -ge -1 -and [int]$v.jobs -le 3){Write-Output ('HOSTOPS_RETEST_JOBS='+$v.jobs)}
            }
        }
    }
    if ($receipt.operation -ceq 'owner-g1-delta-1124') {
        $file = Join-Path $outbox ('g1-delta-' + $nonce + '.json')
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            $item = Get-Item -LiteralPath $file -Force
            if ($item.Length -le 1024 -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $v = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
                if ($v.schema -ceq 'TTV-G1-DELTA-V1' -and $v.nonce -ceq $nonce -and
                    $v.source -ceq '5e3ce11f76828daa2d5aa72cacc7514e74dc152e' -and
                    $v.status -cin @('SUCCESS','HOLD') -and
                    $v.phase -cin @('PREFLIGHT','STAGE','OFFLINE_CHECK','BACKUP','APPLY','START','DONE') -and
                    $v.reason -cmatch '^[A-Z0-9_]{3,80}$') {
                    Write-Output ('HOSTOPS_G1_DELTA_STATUS=' + $v.status)
                    Write-Output ('HOSTOPS_G1_DELTA_PHASE=' + $v.phase)
                    Write-Output ('HOSTOPS_G1_DELTA_REASON=' + $v.reason)
                }
            }
        }
    }
    if ($receipt.operation -cin @('owner-odyssey-en-stage-1124','owner-p3-gate-readonly-1124','agy-odyssey-trained-search-1124','agy-trained-search-readout-1124','agy-odyssey-direct-test-c-1124','agy-neon-indexed-search-1124','agy-neon-indexed-readout-1124','agy-spiderman-model-compare-1124','agy-spiderman-browser-readout-1124','agy-hydrogen-tooltrace-1124','opensubtitles-spiderman-http-control-1124','agy-browser-native-preflight-1124','agy-native-browser-interactive-1124','agy-native-browser-readout-1124','owner-g21-r4-reconcile','owner-g21-r4-acceptance','owner-g21-r5-acceptance','owner-g2-sintel-library-once','owner-g2-speed-first-bunny','owner-g2-deploy-readout','owner-g2-deploy-delta','owner-g2-start-applied','owner-g2-production-once','owner-g2-production-readout','owner-g2-production-resume','owner-g2-finalize','owner-g2-finalize-reconcile','owner-g2-finalize-chain','owner-flow3-overlay-readout','owner-flow3-overlay-apply','owner-flow3-overlay-resume','owner-flow3-dual-preflight','owner-flow3-dual-apply','owner-flow3-agy-metadata-once','owner-flow3-agy-denial-readout','owner-production-movie','owner-g21-r4-readout','agy-native-browser-srt-qa-1124','agy-browser-headless-control-1124','agy-browser-headless-restore-1124')) {
        $file = Join-Path $outbox ('odyssey-stage-' + $nonce + '.json')
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            $item = Get-Item -LiteralPath $file -Force
            if ($item.Length -le 1024 -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $v = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
                if ($v.schema -ceq 'TTV-ODYSSEY-STAGE-V1' -and $v.nonce -ceq $nonce -and $v.reason -cmatch '^[A-Z0-9_]{3,90}$') {
                    Write-Output ('HOSTOPS_ODYSSEY_STAGE=' + $v.reason)
                }
            }
        }
    }

    if ($receipt.operation -ceq 'owner-production-movie') {
        $stage=Get-Content -LiteralPath (Join-Path $outbox ('odyssey-stage-'+$nonce+'.json')) -Raw|ConvertFrom-Json
        if($receipt.result -cne 'SUCCESS' -or $stage.nonce -cne $nonce -or $stage.schema -cne 'TTV-ODYSSEY-STAGE-V1'){throw 'PRODUCTION_MOVIE_OWNER_RECEIPT'}
        if($stage.reason -ceq 'PRODUCTION_MOVIE_LIBRARY_READY'){
            if($mode -cne 'play'){throw 'PRODUCTION_MOVIE_MODE_DRIFT'}
            & pwsh.exe -NoLogo -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'production-movie-play.ps1') -RequestId $nonce
            if($LASTEXITCODE -ne 0){throw 'PRODUCTION_MOVIE_PLAY_FAILED_NO_REPLAY'}
        }
        return
    }

    if ($receipt.operation -ceq 'owner-flow3-dual-apply') {
        $f=Join-Path $outbox ('odyssey-stage-'+$nonce+'.json')
        $v=Get-Content -LiteralPath $f -Raw|ConvertFrom-Json
        if($receipt.result -cne 'SUCCESS' -or $v.nonce -cne $nonce -or $v.reason -cne 'FLOW3_DUAL_OWNER_APPLY_PASS_U5_HASH10_FRESH_OWNER'){Write-Output 'FLOW3_DUAL_TV_INSTALL_NOT_RUN_OWNER_HOLD';return}
        # Existing manual playback remains compatible during the short rollout.
        # If a new Human play arrives, do not interrupt it.
        $currentDevice=Flow3DualTvRead $oldsha
        if($currentDevice -cne $dualDevice){throw 'DUAL_TV_DEVICE_DRIFT'}
        if((Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant() -cne $newsha){throw 'DUAL_APK_DRIFT'}
        $intent=Join-Path $rollback 'install-intent.json'
        $bytes=[Text.Encoding]::UTF8.GetBytes((@{schema='TTV-FLOW3-DUAL-INSTALL-INTENT-V1';owner_nonce=$nonce;preflight_nonce=$preNonce;old_sha256=$oldsha;new_sha256=$newsha;utc=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()}|ConvertTo-Json -Compress))
        $fs=[IO.File]::Open($intent,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$fs.Write($bytes,0,$bytes.Length);$fs.Flush($true)}finally{$fs.Dispose()}
        # One in-place package replacement. No uninstall, clear data, launch or wake.
        $result=@(& $adb -s $dualDevice install -r $apk 2>&1)
        $exitCode=$LASTEXITCODE
        if($exitCode -ne 0 -or ($result|Out-String) -notmatch '(?m)^\s*Success\s*$'){Write-Output 'FLOW3_DUAL_INSTALL_UNCERTAIN_NO_REPLAY';return}
        $verifyDevice=Flow3DualTvRead $newsha
        if($verifyDevice -cne $dualDevice){throw 'DUAL_TV_READBACK_DEVICE'}
        [IO.File]::WriteAllText((Join-Path $rollback 'installed.json'),(@{schema='TTV-FLOW3-DUAL-INSTALLED-V1';owner_nonce=$nonce;preflight_nonce=$preNonce;new_sha256=$newsha;data_clear=$false;utc=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
        Write-Output 'FLOW3_DUAL_TV_INSTALL_PASS_HASH_DATA_PRESERVED'
        Write-Output 'FLOW3_DUAL_SYNC_PASS'
        return
    }

    if ($receipt.operation -ceq 'owner-flow3-dual-preflight') {
        # Runner can see the private APK cache and existing paired ADB; Owner
        # can see its installed source. Neither side mutates the active app.
        $f=Join-Path $outbox ('odyssey-stage-'+$nonce+'.json')
        $v=Get-Content -LiteralPath $f -Raw|ConvertFrom-Json
        if($receipt.result -cne 'SUCCESS' -or $v.nonce -cne $nonce -or $v.reason -cne 'FLOW3_DUAL_PREFLIGHT_READY_HASH10_U5_R1_HB1'){
            Write-Output 'FLOW3_DUAL_TV_PREFLIGHT_NOT_RUN_OWNER_HOLD'
            return
        }
        $candidate='d93ca6bfaa25279402ee13a2bc8960d61992c6a4'
        $sha='9d8ff2c9b34c105b1f74e2419790ff6b02520f92d6aae9fbaf7bea57170858fa'
        $cache=Join-Path $env:RUNNER_WORKSPACE '_omp-fast-cache'
        $stage=Join-Path $cache ('flow3-dual-staged\'+$candidate)
        $apk=Join-Path $stage 'app-armeabi-v7a-debug.apk'
        $meta=Get-Content -LiteralPath (Join-Path $stage 'stage-receipt.txt')
        foreach($line in @('schema=TTV-FLOW3-DUAL-APK-STAGE-V1',('app_commit='+$candidate),'baseline_commit=a6bd7882054b2d942809502c34c25c5b9c682cd1','omp_commit=52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f','variant=app-armeabi-v7a-debug.apk',('sha256='+$sha),'device_installed=no')){
            if($meta -cnotcontains $line){throw 'FLOW3_DUAL_STAGE_RECEIPT_DRIFT'}
        }
        if((Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant() -cne $sha){throw 'FLOW3_DUAL_APK_DRIFT'}
        Write-Output 'FLOW3_DUAL_STAGED_APK_SHA256_PASS'
        $adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
        $devices=@(& $adb devices 2>$null)
        $auth=@($devices|Where-Object{$_ -match '^\S+\s+device(\s|$)'})
        if($LASTEXITCODE -ne 0 -or $auth.Count -ne 1 -or @($devices|Where-Object{$_ -match '^\S+\s+(offline|unauthorized)(\s|$)'}).Count){Write-Output 'FLOW3_DUAL_TV_HOLD_ADB_UNAVAILABLE';return}
        $serial=($auth[0] -split '\s+')[0]
        if(((& $adb -s $serial shell getprop ro.product.model 2>$null)|Out-String).Trim() -cne 'MiTV-ASTR0'){throw 'FLOW3_DUAL_TV_MODEL'}
        $abi=((& $adb -s $serial shell getprop ro.product.cpu.abilist 2>$null)|Out-String).Trim()
        if($LASTEXITCODE -ne 0 -or ($abi -split ',') -cnotcontains 'armeabi-v7a'){throw 'FLOW3_DUAL_TV_ABI'}
        $pkg='com.spacesarmat.omp.test'
        $act=((& $adb -s $serial shell dumpsys activity activities 2>$null)|Out-String)
        if($LASTEXITCODE -ne 0){throw 'FLOW3_DUAL_TV_ACTIVITY'}
        $playing=@($act -split '\r?\n'|Where-Object{$_ -match 'mResumedActivity|topResumedActivity' -and $_ -match 'com\.spacesarmat\.omp\.test/' -and $_ -match 'PlayerActivity'}).Count -gt 0
        $paths=@(& $adb -s $serial shell pm path $pkg 2>$null|ForEach-Object{([string]$_).Trim()})
        if($LASTEXITCODE -ne 0 -or $paths.Count -ne 1 -or $paths[0] -notmatch '^package:(/data/app/[^ \r\n]+/base\.apk)$'){Write-Output 'FLOW3_DUAL_TV_HOLD_OLD_APK_LAYOUT';return}
        $remote=$Matches[1]
        # Retain actual old base APK privately for rollback, no device writes.
        $rollback=Join-Path $cache ('flow3-dual-rollback\'+$nonce)
        New-Item -ItemType Directory -Path $rollback -ErrorAction Stop|Out-Null
        $old=Join-Path $rollback 'previous-base.apk'
        & $adb -s $serial pull $remote $old 2>$null|Out-Null
        if($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $old -PathType Leaf)){throw 'FLOW3_DUAL_TV_OLD_APK_READ'}
        $oldsha=(Get-FileHash -LiteralPath $old -Algorithm SHA256).Hash.ToLowerInvariant()
        $tool=@(Get-ChildItem -LiteralPath 'C:\TOOL\Android-SDK\build-tools' -Directory|Where-Object{(Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat')) -and (Test-Path -LiteralPath (Join-Path $_.FullName 'aapt2.exe'))}|Sort-Object Name -Descending|Select-Object -First 1)
        if($tool.Count -ne 1){throw 'FLOW3_DUAL_SDK_TOOLS'}
        $signer=Join-Path $tool[0].FullName 'apksigner.bat'
        $aapt=Join-Path $tool[0].FullName 'aapt2.exe'
        $jdk=@(Get-ChildItem -LiteralPath 'C:\Program Files\Eclipse Adoptium' -Directory|Where-Object{$_.Name -like 'jdk-21*' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'bin\java.exe'))}|Sort-Object Name -Descending|Select-Object -First 1)
        if($jdk.Count -ne 1){throw 'FLOW3_DUAL_JAVA'}
        $env:JAVA_HOME=$jdk[0].FullName
        function Cert([string]$file){
            $lines=@(& $signer verify --print-certs $file 2>$null)
            if($LASTEXITCODE -ne 0){throw 'FLOW3_DUAL_APK_SIGNATURE'}
            $digests=@($lines|ForEach-Object{if($_ -match '^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]{64})$'){$Matches[1].ToLowerInvariant()}})
            if($digests.Count -ne 1){throw 'FLOW3_DUAL_APK_SIGNER_COUNT'}
            return $digests[0]
        }
        function Version([string]$file){
            $lines=@(& $aapt dump badging $file 2>$null)
            if($LASTEXITCODE -ne 0){throw 'FLOW3_DUAL_APK_BADGING'}
            $p=@($lines|Where-Object{$_ -match "^package: name='com\.spacesarmat\.omp\.test' versionCode='\d+'"})
            if($p.Count -ne 1 -or $p[0] -notmatch "versionCode='(\d+)'"){throw 'FLOW3_DUAL_APK_PACKAGE'}
            return [long]$Matches[1]
        }
        $oldcert=Cert $old;$newcert=Cert $apk
        $oldver=Version $old;$newver=Version $apk
        $proof=@{schema='TTV-FLOW3-DUAL-TV-PREFLIGHT-V1';nonce=$nonce;candidate=$candidate;new_sha256=$sha;old_sha256=$oldsha;old_version=$oldver;new_version=$newver;signer_match=($oldcert -ceq $newcert);player_foreground=$playing;observed_utc=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()}
        [IO.File]::WriteAllText((Join-Path $rollback 'preflight.json'),($proof|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
        if($oldcert -cne $newcert){Write-Output 'FLOW3_DUAL_TV_HOLD_SIGNER_MISMATCH';return}
        if($newver -lt $oldver){Write-Output 'FLOW3_DUAL_TV_HOLD_VERSION_DOWNGRADE';return}
        if($playing){Write-Output 'FLOW3_DUAL_TV_HOLD_ACTIVE_PLAYBACK';return}
        Write-Output 'FLOW3_DUAL_TV_PREFLIGHT_PASS_ARM32_SIGNER_VERSION_ROLLBACK'
        Write-Output ('FLOW3_DUAL_OLD_APK_SHA256='+$oldsha)
        return
    }

    if ($receipt.operation -ceq 'owner-g2-production-once') {
        $f=Join-Path $outbox ('odyssey-stage-'+$nonce+'.json')
        if($receipt.result -cne 'SUCCESS' -or -not (Test-Path -LiteralPath $f -PathType Leaf)){throw 'G2_PROD_OWNER_RECEIPT_MISSING'}
        $v=Get-Content -LiteralPath $f -Raw|ConvertFrom-Json
        if($v.schema -cne 'TTV-ODYSSEY-STAGE-V1' -or $v.nonce -cne $nonce -or $v.reason -cnotmatch '^G2_PROD_LIBRARY_READY_AGY[0-9]+_TOTAL[0-9]+$'){
            Write-Output 'G2_PROD_NO_LAUNCH_RECONCILE_OWNER_RECEIPT'
            return
        }
        $dir=Join-Path $env:RUNNER_TEMP ('g2-production-'+$nonce)
        New-Item -ItemType Directory -Path $dir -ErrorAction Stop|Out-Null
        $files=[ordered]@{'owner_movie_flow.ps1'='cd5551d6d3d0d0b590e44cee9a97b4fbab7a5b09';'owner_movie_play.ps1'='3863ed82c0d81aa9c08feeca6318eac3b36c577e'}
        foreach($n in $files.Keys){
            $dest=Join-Path $dir $n
            Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/47c265fc908171ab18bb0707b2e26b014fb39d40/poc/p2-source/'+$n) -OutFile $dest -TimeoutSec 25
            $hash=(& git hash-object --no-filters -- $dest|Out-String).Trim()
            if($LASTEXITCODE -ne 0 -or $hash -cne $files[$n]){throw 'G2_PROD_PLAY_SOURCE_DRIFT'}
        }
        $lr=Get-Content -LiteralPath (Join-Path $outbox ('g2-'+$nonce+'.library.json')) -Raw|ConvertFrom-Json
        if($lr.request_id -cne $nonce -or $lr.status -cne 'LIBRARY_READY' -or $lr.play -ne $true){throw 'G2_PROD_RECEIPT_BINDING'}
        if($lr.torrent_hash -ceq 'c9e15763f722f23e98a29decdfae341b98d53056'){Write-Output 'G2_PROD_FIXTURE=COSMOS_LAUNDROMAT'}
        elseif($lr.torrent_hash -ceq 'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c'){Write-Output 'G2_PROD_FIXTURE=BIG_BUCK_BUNNY'}
        else{throw 'G2_PROD_FIXTURE_UNVERIFIED'}
        Write-Output 'G2_PROD_PLAY_SOURCE_PINNED'
        & pwsh -NoLogo -NoProfile -NonInteractive -File (Join-Path $dir 'owner_movie_flow.ps1') -RequestId $nonce
        if($LASTEXITCODE -ne 0){throw 'G2_PROD_PLAY_HOLD_NO_REPLAY'}
        return
    }


    if ($receipt.operation -ceq 'owner-g2-production-resume') {
        $f=Join-Path $outbox ('odyssey-stage-'+$nonce+'.json')
        if($receipt.result -cne 'SUCCESS' -or -not (Test-Path -LiteralPath $f -PathType Leaf)){throw 'G2_RESUME_RECEIPT_MISSING'}
        $v=Get-Content -LiteralPath $f -Raw|ConvertFrom-Json
        if($v.schema -cne 'TTV-ODYSSEY-STAGE-V1' -or $v.nonce -cne $nonce -or $v.reason -cnotmatch '^G2_RESUME_COSMOS_LIBRARY_READY_MS[0-9]+$'){Write-Output 'G2_RESUME_NO_LAUNCH';return}
        $pointer=Join-Path $outbox ('g2-resume-'+$nonce+'.json')
        $item=Get-Item -LiteralPath $pointer
        if($item.Length -gt 1024 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'G2_RESUME_POINTER'}
        $p=Get-Content -LiteralPath $pointer -Raw|ConvertFrom-Json
        if($p.schema -cne 'TTV-G2-RESUME-V1' -or $p.nonce -cne $nonce -or $p.request_id -cnotmatch '^[a-f0-9]{32}$' -or $p.fixture -cne 'COSMOS'){throw 'G2_RESUME_POINTER'}
        $lr=Get-Content -LiteralPath (Join-Path $outbox ('g2-'+$p.request_id+'.library.json')) -Raw|ConvertFrom-Json
        if($lr.request_id -cne $p.request_id -or $lr.status -cne 'LIBRARY_READY' -or $lr.play -ne $true -or $lr.torrent_hash -cne 'c9e15763f722f23e98a29decdfae341b98d53056'){throw 'G2_RESUME_LIBRARY_BINDING'}
        $dir=Join-Path $env:RUNNER_TEMP ('g2-resume-'+$nonce)
        New-Item -ItemType Directory -Path $dir -ErrorAction Stop|Out-Null
        $files=[ordered]@{'owner_movie_flow.ps1'='cd5551d6d3d0d0b590e44cee9a97b4fbab7a5b09';'owner_movie_play.ps1'='3863ed82c0d81aa9c08feeca6318eac3b36c577e'}
        foreach($n in $files.Keys){
            $dest=Join-Path $dir $n
            Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/47c265fc908171ab18bb0707b2e26b014fb39d40/poc/p2-source/'+$n) -OutFile $dest -TimeoutSec 25
            $hash=(& git hash-object --no-filters -- $dest|Out-String).Trim()
            if($LASTEXITCODE -ne 0 -or $hash -cne $files[$n]){throw 'G2_RESUME_PLAY_SOURCE_DRIFT'}
        }
        Write-Output 'G2_RESUME_ORIGINAL_REQUEST_PLAY_PINNED'
        & pwsh -NoLogo -NoProfile -NonInteractive -File (Join-Path $dir 'owner_movie_flow.ps1') -RequestId $p.request_id
        if($LASTEXITCODE -ne 0){throw 'G2_RESUME_PLAY_HOLD_NO_REPLAY'}
        return
    }

    if ($manifest.script_path -ceq 'hostops/laptop-ops/operations/g21-resume-help-readout.ps1' -and $receipt.result -ceq 'SUCCESS') {
        $file = Join-Path $outbox ('g21-agy-help-' + $nonce + '.json')
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            $item = Get-Item -LiteralPath $file -Force
            if ($item.Length -gt 0 -and $item.Length -le 8192 -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $v = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
                if ($v.schema -ceq 'G21_AGY_HELP_V1' -and $v.nonce -ceq $nonce -and @($v.lines).Count -le 24) {
                    foreach ($line in @($v.lines)) {
                        if ($line -isnot [string] -or $line.Length -gt 240 -or $line -match '[\x00-\x1F\x7F]') { throw 'G21_HELP_LINE_INVALID' }
                    }
                    foreach ($line in @($v.lines)) { Write-Output ('G21_AGY_HELP=' + $line) }
                }
            }
        }
    }
    if ($manifest.script_path -cin @('hostops/laptop-ops/operations/g21-training-full-report.ps1','hostops/laptop-ops/operations/g21-student-v2-readout.ps1') -and $receipt.result -ceq 'SUCCESS') {
        $file = Join-Path $outbox ('g21-full-report-' + $nonce + '.json')
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            $item = Get-Item -LiteralPath $file -Force
            if ($item.Length -gt 0 -and $item.Length -le 32768 -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $v = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
                if ($v.schema -ceq 'G21_TRAINING_FULL_REPORT_V1' -and $v.nonce -ceq $nonce -and @($v.lines).Count -le 100) {
                    foreach ($line in @($v.lines)) {
                        if ($line -isnot [string] -or $line -cnotmatch '^G21_FULL_R[12]_(?:SUMMARY|RECIPE|TIMING|A[0-9]{1,2}|C[0-9]{1,2})=[A-Z0-9_:+,]{1,500}$') { throw 'G21_FULL_REPORT_LINE_INVALID' }
                    }
                    foreach ($line in @($v.lines)) { Write-Output $line }
                }
            }
        }
    }
    if ($manifest.script_path -ceq 'hostops/laptop-ops/operations/tr-ttv-06-student-v3.ps1' -and $receipt.result -ceq 'SUCCESS') {
        $f=Join-Path $outbox ('brain-handoff-'+$nonce+'.json')
        $item=Get-Item -LiteralPath $f -Force
        if($item.Length -le 0 -or $item.Length -gt 262144 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'BRAIN_HANDOFF_BOUND'}
        $v=Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
        $nums=@('events','invalid','timed','elapsed','download','first_mcp_ms','last_mcp_ms','mcp_outcomes','final_chars','actions','recipe_steps','artifacts','cues','title_language','exact','sync','denied')
        $fields=@('schema','nonce','source','original_source','mode','state','model_status','model_release','recipe_codes','error_kind','result_code','trace')+$nums
        if((@($v.PSObject.Properties.Name|Sort-Object)-join ',') -cne (@($fields|Sort-Object)-join ',') -or $v.schema -cne 'TTV-BRAIN-HANDOFF-V1' -or $v.nonce -cne $nonce -or $v.source -cne $commit -or $v.original_source -cnotmatch '^[a-f0-9]{40}$'){throw 'BRAIN_HANDOFF_SCHEMA'}
        if($v.mode -cnotmatch '^(LIVE|REPLAY)$' -or $v.state -cnotmatch '^(MODEL_REPORT_PRESENT|MODEL_REPORT_MISSING)$' -or $v.error_kind -cnotmatch '^(NONE|KEYERROR|VALUEERROR|TYPEERROR|NAMEERROR|ATTRIBUTEERROR|OSERROR|PERMISSIONERROR|FILENOTFOUNDERROR|RUNTIMEERROR|TIMEOUTERROR|UNICODEERROR|JSONDECODEERROR|OTHER_ERROR)$' -or $v.result_code -cnotmatch '^[A-Z0-9_]{3,90}$'){throw 'BRAIN_HANDOFF_ENUM'}
        if($v.model_status -cnotmatch '^(CANDIDATE_DOWNLOADED|NO_PLAUSIBLE_CANDIDATE|ACCESS_BLOCKED|AUTH_REQUIRED|DOWNLOAD_FAILED|TOOL_UNAVAILABLE|UNKNOWN|NOT_REPORTED)$' -or $v.model_release -cnotmatch '^(EXACT_METADATA|EVIDENCED_COMPATIBLE|UNKNOWN|CONFLICT|NOT_REPORTED)$'){throw 'BRAIN_HANDOFF_MODEL_ENUM'}
        if($v.recipe_codes -isnot [array] -or @($v.recipe_codes).Count -gt 64){throw 'BRAIN_HANDOFF_RECIPE_COUNT'}
        foreach($x in $v.recipe_codes){if($x -isnot [string] -or $x -cnotmatch '^(LIST_TASK_TAB|NAVIGATE_PROVIDER|QUERY_TITLE_YEAR|FILTER_ENGLISH|MATCH_RELEASE|CHECK_DETAIL|BIND_CANDIDATE|DOWNLOAD_ONCE|COMPACT_DOM|AVOID_REPEAT_SNAPSHOT|STOP_ON_DENIAL|MARK_UNKNOWN_METADATA|CHECK_TIMELINE|HOST_VERIFY_FILE|FINAL_REPORT)$'){throw 'BRAIN_HANDOFF_RECIPE_CODE'}}
        if($v.mode -ceq 'REPLAY' -and ($manifest.arguments -notcontains '-ReplayBT04' -or $v.original_source -cne '4cd3124ac8c7102028ff0b1f079a5b3b522b15c9')){throw 'BRAIN_HANDOFF_REPLAY_DRIFT'}
        if($v.mode -ceq 'LIVE' -and ($manifest.arguments -contains '-ReplayBT04' -or $v.original_source -cne $commit)){throw 'BRAIN_HANDOFF_LIVE_DRIFT'}
        foreach($key in $nums){if($v.$key -isnot [ValueType] -or [long]$v.$key -lt -1 -or [long]$v.$key -gt 2147483647){throw 'BRAIN_HANDOFF_NUM'}}
        if($v.trace -isnot [array] -or @($v.trace).Count -gt 2048 -or @($v.trace).Count -gt $v.events){throw 'BRAIN_HANDOFF_COUNT'}
        foreach($line in $v.trace){if($line -isnot [string] -or $line -cnotmatch '^[0-9]{1,8}:(-1|[0-9]{1,9}):(LIST_PAGES|SELECT_PAGE|NAVIGATE_PAGE|TAKE_SNAPSHOT|CLICK|FILL|PRESS_KEY|WAIT_FOR|EVALUATE_SCRIPT|READ_FILE|WRITE_FILE|RUN_SHELL_COMMAND|EXECUTE_COMMAND|LIST_NETWORK_REQUESTS|CALL_MCP_TOOL):(ERROR|OUTPUT|CALL)$'){throw 'BRAIN_HANDOFF_ROW'}}
        Write-Output ('HOSTOPS_BRAIN_HANDOFF_JSON='+($v|ConvertTo-Json -Depth 5 -Compress))
        Write-Output 'HOSTOPS_BRAIN_REPORT_FILE_VERIFIED'
    }
    if ($receipt.result -cne 'SUCCESS') {
        Write-Output 'HOSTOPS_OWNER_OPS=FAILED_NO_RETRY_PRIVATE_LOG'
        if ($receipt.operation -ceq 'owner-srt-parser-install') {
            $diagFile=Join-Path $outbox ('srt-parser-hold-'+$nonce+'.json')
            if (Test-Path -LiteralPath $diagFile -PathType Leaf) {
                $item=Get-Item -LiteralPath $diagFile -Force
                if ($item.Length -le 512 -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                    $diag=Get-Content -LiteralPath $diagFile -Raw | ConvertFrom-Json
                    if ($diag.schema -ceq 'TTV-SRT-INSTALL-HOLD-V1' -and $diag.nonce -ceq $nonce -and $diag.reason -cmatch '^[A-Z0-9_]{3,80}$') {
                        Write-Output ('HOSTOPS_SRT_INSTALL_HOLD='+$diag.reason)
                    }
                }
            }
        }
        if ($receipt.diagnostic -cmatch '^OWNER_FULL_DIAG_FAILURE_PHASE=(REPLACE_FILES|OFFLINE_IMPORT|FRESH_OWNER_START|FULL_LOG_VERIFY)$') {
            Write-Output $receipt.diagnostic
        }
        if ($receipt.operation -ceq 'owner-g1-186-install') {
            $diagFile=Join-Path $outbox ('g1-186-hold-' + $nonce + '.json')
            if (Test-Path -LiteralPath $diagFile -PathType Leaf) {
                $item=Get-Item -LiteralPath $diagFile -Force
                if ($item.Length -le 512 -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                    $diag=Get-Content -LiteralPath $diagFile -Raw | ConvertFrom-Json
                    if ($diag.schema -ceq 'TTV-G1-INSTALL-HOLD-V1' -and $diag.nonce -ceq $nonce -and $diag.reason -cmatch '^[A-Z0-9_]{3,80}$') {
                        Write-Output ('HOSTOPS_G1_INSTALL_HOLD=' + $diag.reason)
                    }
                }
            }
        }
        if ($receipt.operation -ceq 'owner-current-film-retest-reset') {
            $diagFile=Join-Path $outbox ('retest-hold-'+$nonce+'.json')
            if (Test-Path -LiteralPath $diagFile -PathType Leaf) {
                $item=Get-Item -LiteralPath $diagFile -Force
                if ($item.Length -le 512 -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                    $diag=Get-Content -LiteralPath $diagFile -Raw | ConvertFrom-Json
                    if ($diag.schema -ceq 'TTV-RETEST-HOLD-V1' -and $diag.nonce -ceq $nonce -and $diag.reason -cmatch '^[A-Z0-9_]{3,100}$') {
                        Write-Output ('HOSTOPS_RETEST_HOLD='+$diag.reason)
                    }
                }
            }
        }
        throw 'HOSTOPS_OWNER_OPS_OWNER_TASK_FAILED'
    }
    if ($receipt.operation -ceq 'report-bridge-api-bt18') {
        $file=Join-Path $outbox ('report-bridge-api-'+$nonce+'.json')
        $item=Get-Item -LiteralPath $file -Force
        if($item.Length -le 0 -or $item.Length -gt 2048 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'RB_API_RECEIPT_INVALID'}
        $v=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json
        if($v.schema -cne 'TTV-RB02-API-OWNER-V1' -or $v.nonce -cne $nonce -or $v.source_commit -cne $commit -or $v.original_source -cne 'ad010d992cd69cec1dc28185d538392efe8e04fe' -or $v.original_nonce -cne '25e73e80cfce49728e4f6c1402e6cefb' -or $v.state -cnotin @('HOLD','API_UPLOAD_VERIFIED') -or $v.reason -cnotmatch '^[A-Z0-9_]{3,80}$' -or $v.tests -cnotin @('NOT_RUN','PASS','FAIL') -or $v.desktop_before -lt 0 -or $v.desktop_after -lt 0){throw 'RB_API_RECEIPT_BINDING'}
        if($v.state -ceq 'API_UPLOAD_VERIFIED'){
            if($v.tests -cne 'PASS' -or $v.reason -cne 'NONE' -or $v.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $v.file_count -lt 6 -or $v.file_count -gt 100 -or $v.bytes -le 0 -or $v.bytes -gt 5242880){throw 'RB_API_RECEIPT_RESULT'}
            if($v.probe_sha256 -cnotmatch '^[a-f0-9]{64}$' -or $v.desktop_before -ne 0 -or $v.desktop_after -ne 0){throw 'RB_API_DESKTOP_OFF_PROOF_INVALID'}
            Write-Output ('RB_API_PROBE_NONCE='+$nonce)
            Write-Output ('RB_API_PROBE_SHA256='+$v.probe_sha256)
            Write-Output ('RB_API_ZIP_SHA256='+$v.sha256)
            Write-Output ('RB_API_FILE_COUNT='+[int]$v.file_count)
            Write-Output ('RB_API_ZIP_BYTES='+[long]$v.bytes)
        } elseif($v.reason -ceq 'NONE'){throw 'RB_API_RECEIPT_HOLD_REASON'}
        Write-Output ('RB_API_TESTS='+$v.tests)
        Write-Output ('RB_API_DESKTOP_BEFORE='+[int]$v.desktop_before)
        Write-Output ('RB_API_DESKTOP_AFTER='+[int]$v.desktop_after)
        Write-Output ('RB_API_STATE='+$v.state)
        Write-Output ('RB_API_REASON='+$v.reason)
    }
    if ($receipt.operation -ceq 'report-bridge-bt18') {
        $file=Join-Path $outbox ('report-bridge-'+$nonce+'.json')
        $item=Get-Item -LiteralPath $file -Force
        if($item.Length -le 0 -or $item.Length -gt 2048 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'RB_RECEIPT_INVALID'}
        $v=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json
        if($v.schema -cne 'TTV-REPORT-BRIDGE-OWNER-V1' -or $v.nonce -cne $nonce -or $v.source_commit -cne $commit -or $v.original_source -cne 'ad010d992cd69cec1dc28185d538392efe8e04fe' -or $v.original_nonce -cne '25e73e80cfce49728e4f6c1402e6cefb' -or $v.state -cnotin @('HOLD','LOCAL_EXPORT_PASS') -or $v.reason -cnotin @('INBOX_NOT_VISIBLE','INBOX_AMBIGUOUS','EXPORT_FAILED','NONE')){throw 'RB_RECEIPT_BINDING'}
        if($v.state -ceq 'LOCAL_EXPORT_PASS'){
            if($v.reason -cne 'NONE' -or $v.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $v.file_count -lt 6 -or $v.file_count -gt 100 -or $v.bytes -le 0 -or $v.bytes -gt 201326592){throw 'RB_RECEIPT_RESULT'}
            Write-Output ('RB_OWNER_ZIP_SHA256='+$v.sha256)
            Write-Output ('RB_OWNER_FILE_COUNT='+[int]$v.file_count)
            Write-Output ('RB_OWNER_ZIP_BYTES='+[long]$v.bytes)
        } elseif($v.reason -ceq 'NONE'){throw 'RB_RECEIPT_HOLD_REASON'}
        Write-Output ('RB_OWNER_STATE='+$v.state)
        Write-Output ('RB_OWNER_REASON='+$v.reason)
    }
    Write-Output 'HOSTOPS_OWNER_OPS=SUCCESS_OWNER_PRIVATE_LOG'
    Write-Output ('HOSTOPS_OWNER_OPS_OPERATION=' + $receipt.operation)
    if ($receipt.operation -ceq 'owner-g2-flow-submit') {
        $path=Join-Path $outbox ('g2-flow-submit-'+$nonce+'.json')
        $item=Get-Item -LiteralPath $path -ErrorAction Stop
        if($item.Length -le 0 -or $item.Length -gt 512 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'G2_SUBMIT_RECEIPT_INVALID'}
        $v=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
        if($v.schema -cne 'TTV-G2-HOSTOPS-SUBMIT-V1' -or $v.nonce -cne $nonce -or $v.request_id -cnotmatch '^[a-f0-9]{32}$'){throw 'G2_SUBMIT_RECEIPT_INVALID'}
        $flow=Join-Path $env:GITHUB_WORKSPACE 'poc\p2-source\owner_movie_flow.ps1'
        $play=Join-Path $env:GITHUB_WORKSPACE 'poc\p2-source\owner_movie_play.ps1'
        if ((& git hash-object -- $flow).Trim() -cne 'cd5551d6d3d0d0b590e44cee9a97b4fbab7a5b09' -or (& git hash-object -- $play).Trim() -cne '3863ed82c0d81aa9c08feeca6318eac3b36c577e'){throw 'G2_FLOW_SOURCE_DRIFT'}
        & pwsh -NoLogo -NoProfile -NonInteractive -File $flow -RequestId $v.request_id
        if($LASTEXITCODE -ne 0){throw 'G2_FLOW_HOLD_NO_REPLAY'}
        return
    }
    if ($receipt.operation -ceq 'owner-g2-199-tos-single') {
        $stagePath=Join-Path $outbox ('odyssey-stage-'+$nonce+'.json')
        $v=Get-Content -LiteralPath $stagePath -Raw|ConvertFrom-Json
        if($v.schema -cne 'TTV-ODYSSEY-STAGE-V1' -or $v.nonce -cne $nonce -or $v.reason -cnotmatch '^G2_FIXTURE_[A-Z0-9_]{1,75}$'){throw 'G2_FIXTURE_RECEIPT_INVALID'}
        Write-Output ('G2_OWNER_STAGE='+$v.reason)
        if($v.reason -ceq 'G2_FIXTURE_LIBRARY_READY'){
            $play=Join-Path $env:GITHUB_WORKSPACE 'poc\p2-source\owner_movie_play.ps1'
            if ((& git hash-object -- $play).Trim() -cne 'dccec4013ce7a9b126d47f938b141d7dac2d8943'){throw 'G2_PLAY_SOURCE_DRIFT'}
            & pwsh -NoLogo -NoProfile -NonInteractive -File $play -RequestId $nonce
            if($LASTEXITCODE -ne 0){throw 'G2_PLAY_HOLD_NO_RETRY'}
        }
        return
    }
    if ($receipt.operation -cin @('owner-vieneu-benchmark','owner-vieneu-int8-benchmark')) {
        $expectedPrecision = if ($receipt.operation -ceq 'owner-vieneu-int8-benchmark') {'INT8'} else {'FP32'}
        $file = Join-Path $outbox ('vieneu-benchmark-' + $nonce + '.json')
        $item = Get-Item -LiteralPath $file -Force
        if ($item.Length -le 0 -or $item.Length -gt 1536 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'VIENEU_BENCHMARK_RECEIPT_INVALID' }
        $v = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($v.schema -cne 'TTV-VIENEU-BENCHMARK-V1' -or $v.nonce -cne $nonce -or
            $v.status -cnotin @('BENCHMARK_COMPLETE','BENCHMARK_FAILED','BENCHMARK_TIMEOUT','ENV_MISSING','RAM_LOW','PROBE_EXCEPTION') -or
            $v.stage -cnotin @('PREFLIGHT','IMPORT','MODEL_RESOLVE','MODEL_INIT','SYNTHESIS','DONE') -or
            $v.sdk -cnotin @('NONE','3.8.5') -or $v.precision -cne $expectedPrecision -or $v.threads -ne 8 -or
            $v.model_sha -cnotmatch '^(NONE|[a-f0-9]{40})$' -or $v.codec_sha -cnotmatch '^(NONE|[a-f0-9]{40})$') { throw 'VIENEU_BENCHMARK_SCOPE_INVALID' }
        foreach($field in @('prior_error','error_kind')) {
            if ($v.$field -cnotin @('UNKNOWN','NONE','MEMORY_TELEMETRY','MEMORY_EXHAUSTED','ASSERTION','CACHE_MISSING','OTHER')) { throw 'VIENEU_BENCHMARK_ERROR_INVALID' }
        }
        foreach($name in @('init_ms','first_ms','audio_ms','synth_ms','rtf_milli','cue_count','peak_mib','sample_rate','elapsed_s')){
            if ($v.$name -lt 0 -or $v.$name -gt 6000000) { throw 'VIENEU_BENCHMARK_METRIC_INVALID' }
        }
        foreach($name in @('status','stage','sdk','precision','threads','model_sha','codec_sha','init_ms','first_ms','audio_ms','synth_ms','rtf_milli','cue_count','peak_mib','sample_rate','elapsed_s','prior_error','error_kind')){
            Write-Output ('HOSTOPS_VIENEU_BENCHMARK_' + $name.ToUpperInvariant() + '=' + $v.$name)
        }
    }
    if ($receipt.operation -ceq 'owner-vieneu-int8-benchmark') {
        $file = Join-Path $outbox ('r43-mixed-' + $nonce + '.json')
        if(Test-Path -LiteralPath $file -PathType Leaf){
            $item=Get-Item -LiteralPath $file -Force
            if($item.Length -gt 2048 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'R43_RECEIPT_INVALID'}
            $q=Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
            if($q.nonce -cne $nonce){throw 'R43_NONCE_INVALID'}
            foreach($key in @('prior_wavs','prior_bad','prior_clip_ppm_max','prior_rms_min_milli','baseline_ok','baseline_fail','baseline_max_ms','mixed_ok','mixed_fail','mixed_max_ms','mixed_min_free_mib','mixed_peak_cpu_pct','torr_pid','established_before','established_after')){
                if($q.$key -lt 0 -or $q.$key -gt 1000000){throw 'R43_METRIC_INVALID'}
                Write-Output ('HOSTOPS_R43_'+$key.ToUpperInvariant()+'='+[int]$q.$key)
            }
        } else {Write-Output 'HOSTOPS_R43_RECEIPT=MISSING'}
    }
    if ($receipt.operation -ceq 'owner-vieneu-provision') {
        $file = Join-Path $outbox ('vieneu-provision-' + $nonce + '.json')
        $item = Get-Item -LiteralPath $file -Force
        if ($item.Length -le 0 -or $item.Length -gt 1024 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'VIENEU_PROVISION_RECEIPT_INVALID' }
        $v = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($v.schema -cne 'TTV-VIENEU-PROVISION-V1' -or $v.nonce -cne $nonce -or
            $v.status -cnotin @('ENV_READY','NO_COMPATIBLE_PYTHON','TIME_BUDGET','VENV_FAILED','RESOLVE_TIMEOUT','WHEEL_RESOLUTION_FAILED','INSTALL_TIMEOUT','INSTALL_FAILED','IMPORT_FAILED','PROVISION_EXCEPTION') -or
            $v.elapsed_s -lt 0 -or $v.elapsed_s -gt 600 -or $v.model_load -cne 'NOT_ATTEMPTED') { throw 'VIENEU_PROVISION_SCOPE_INVALID' }
        foreach ($name in @('python','sdk','onnx')) {
            if ([string]$v.$name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9.+_-]{0,47}$') { throw 'VIENEU_PROVISION_VERSION_INVALID' }
        }
        foreach ($name in @('status','python','sdk','onnx','elapsed_s','model_load')) { Write-Output ('HOSTOPS_VIENEU_PROVISION_' + $name.ToUpperInvariant() + '=' + $v.$name) }
    }
    if ($receipt.operation -ceq 'owner-vieneu-readiness') {
        $file = Join-Path $outbox ('vieneu-readiness-' + $nonce + '.json')
        $item = Get-Item -LiteralPath $file -Force
        if ($item.Length -le 0 -or $item.Length -gt 1024 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'VIENEU_RECEIPT_INVALID' }
        $v = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$v.observed_utc_epoch
        if ($v.schema -cne 'TTV-VIENEU-OWNER-READINESS-V1' -or $v.nonce -cne $nonce -or $age -lt 0 -or $age -gt 180 -or
            $v.python_scope -cnotin @('NONE','RUNNING_OWNER_EXECUTABLE','OWNER_PY_LAUNCHER_FALLBACK') -or
            $v.owner_task -cnotin @('Ready','Running','Disabled','Queued','Unknown','UNKNOWN') -or
            $v.installed_voice_adapter -cnotin @('PRESENT','MISSING') -or
            $v.free_ram_mib -lt 0 -or $v.free_ram_mib -gt 1048576) { throw 'VIENEU_RECEIPT_SCOPE_INVALID' }
        foreach ($name in @('python','vieneu','onnxruntime','numpy','soundfile')) {
            if ([string]$v.$name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9.+_-]{0,47}$') { throw 'VIENEU_RECEIPT_VERSION_INVALID' }
        }
        foreach ($name in @('owner_task','python_scope','python','vieneu','onnxruntime','numpy','soundfile','installed_voice_adapter','free_ram_mib')) {
            Write-Output ('HOSTOPS_VIENEU_' + $name.ToUpperInvariant() + '=' + $v.$name)
        }
        Write-Output 'HOSTOPS_VIENEU_MODEL_LOAD=NOT_ATTEMPTED'
    }
    if ($receipt.operation -ceq 'owner-srt-install-diagnostic') {
        $file=Join-Path $outbox ('srt-install-diag-'+$nonce+'.json')
        $item=Get-Item -LiteralPath $file -Force
        if ($item.Length -gt 1024 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'SRT_INSTALL_DIAG_INVALID'}
        $r=Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
        if ($r.schema -cne 'TTV-SRT-INSTALL-DIAG-V1' -or $r.nonce -cne $nonce -or $r.reason -cnotmatch '^[A-Z0-9_]{3,80}$' -or $r.phase -cnotin @('UNKNOWN','BEFORE_BACKUP','PREFLIGHT_PASSED','BACKUP_CREATED','RECOVERY_ATTEMPTED','ROLLED_BACK') -or $r.parser -cnotin @('OLD','NEW','OTHER','MISSING') -or $r.brain -cnotin @('OLD','NEW','OTHER','MISSING') -or $r.task -cnotin @('Running','Ready','Disabled','Unknown','Queued') -or $r.health -cnotin @('READY_FRESH','NOT_VERIFIED')) {throw 'SRT_INSTALL_DIAG_INVALID'}
        foreach ($field in @('reason','phase','parser','brain','task','health','pending','inflight','locks')) {Write-Output ('HOSTOPS_SRT_DIAG_'+$field.ToUpperInvariant()+'='+$r.$field)}
    }
    if ($receipt.operation -ceq 'owner-hydrogen-benchmark') {
        $f=Join-Path $outbox ('hydrogen-benchmark-'+$nonce+'.json')
        $item=Get-Item -LiteralPath $f -Force
        if ($item.Length -gt 16384 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'HYDROGEN_BENCHMARK_INVALID'}
        $v=Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
        if ($v.schema -cne 'TTV-HYDROGEN-BENCH-V1' -or $v.nonce -cne $nonce -or $v.configured -cnotin @('gemini-4-hydrogen-high','gemini-4-hydrogen-medium','OTHER') -or $v.rows.Count -notin @(1,2)) {throw 'HYDROGEN_BENCHMARK_INVALID'}
        Write-Output ('HOSTOPS_HYDROGEN_CONFIGURED='+$v.configured)
        foreach ($row in $v.rows) {
            if ($row.level -cnotin @('high','medium','hydrogen','neon') -or $row.status -cnotmatch '^[A-Z0-9_]{3,75}$' -or $row.ms -lt 0 -or $row.ms -gt 220000 -or $row.cues -notin @(0,50) -or $row.examples.Count -gt 8) {throw 'HYDROGEN_BENCHMARK_ROW_INVALID'}
            Write-Output ('HOSTOPS_HYDROGEN_RESULT='+($row | ConvertTo-Json -Compress -Depth 5))
        }
    }
    if ($receipt.operation -ceq 'owner-srt-parser-install') {
        $file = Join-Path $outbox ('srt-parser-' + $nonce + '.json')
        $item = Get-Item -LiteralPath $file -Force
        if ($item.Length -le 0 -or $item.Length -gt 512 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'SRT_PARSER_INSTALL_RECEIPT_INVALID' }
        $r = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
        if ($r.schema -cne 'TTV-SRT-PARSER-INSTALL-V1' -or $r.nonce -cne $nonce -or $r.status -cne 'INSTALLED' -or $r.modules -ne 2 -or $r.owner -cne 'READY_FRESH' -or $r.source -cne 'UNCHANGED') { throw 'SRT_PARSER_INSTALL_RECEIPT_INVALID' }
        foreach ($field in @('status','modules','owner','source')) { Write-Output ('HOSTOPS_SRT_PARSER_' + $field.ToUpperInvariant() + '=' + $r.$field) }
    }
    if ($receipt.operation -ceq 'owner-spiderman-en-stage') {
        $file = Join-Path $outbox ('en-stage-' + $nonce + '.json')
        $item = Get-Item -LiteralPath $file -Force
        if ($item.Length -le 0 -or $item.Length -gt 1024 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'EN_STAGE_RECEIPT_INVALID' }
        $r = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
        if ($r.schema -cne 'TTV-OWNER-EN-STAGE-V1' -or $r.nonce -cne $nonce -or $r.status -cnotin @('READY_EXISTING','READY_EXACT_MEDIA','HOLD') -or $r.media -cnotin @('EXACT_METADATA','UNVERIFIED') -or $r.reason -cnotmatch '^[A-Z][A-Z0-9_]{2,100}$' -or [int]$r.cues -lt 0 -or [int]$r.cues -gt 50000 -or [int]$r.bytes -lt 0 -or [int]$r.bytes -gt 10000000) { throw 'EN_STAGE_RECEIPT_INVALID' }
        foreach ($field in @('status','media','cues','bytes','reason')) { Write-Output ('HOSTOPS_EN_STAGE_' + $field.ToUpperInvariant() + '=' + $r.$field) }
    }
    if ($receipt.operation -ceq 'owner-lan-rebind-and-neutral-install') {
        $file = Join-Path $outbox ('lan-rebind-' + $nonce + '.json')
        $item = Get-Item -LiteralPath $file -Force
        if ($item.Length -le 0 -or $item.Length -gt 768 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'LAN_REBIND_RECEIPT_INVALID' }
        $r = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
        if ($r.schema -cne 'TTV-LAN-REBIND-RECEIPT-V1' -or $r.nonce -cne $nonce -or $r.pc -cnotin @('REBIND_APPLIED','EXISTING_ENDPOINT') -or $r.owner -cne 'READY_FRESH' -or $r.modules -cne 'TWO_NEW_VERIFIED' -or $r.tv -cnotin @('NOT_NEEDED','ADB_NOT_READY','STAGED_PENDING_PLAYER_IMPORT','STAGE_FAILED_ROLLED_BACK','STAGE_FAILED_RECONCILE')) { throw 'LAN_REBIND_RECEIPT_INVALID' }
        foreach ($field in @('pc','owner','modules','tv')) {
            Write-Output ('HOSTOPS_LAN_REBIND_' + $field.ToUpperInvariant() + '=' + $r.$field)
        }
    }
    if ($receipt.operation -ceq 'owner-brain-r2-startup-trace') {
        $file = Join-Path $outbox ('owner-brain-startup-' + $nonce + '.json')
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw 'HOSTOPS_BRAIN_STARTUP_RECEIPT_MISSING'
        }
        $item = Get-Item -LiteralPath $file -Force
        if ($item.Length -le 0 -or $item.Length -gt 768 -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'HOSTOPS_BRAIN_STARTUP_RECEIPT_INVALID'
        }
        $diag = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
        $fields = @('schema','nonce','observed_utc_epoch','status',
                    'stage','kind','code','boots','failures','worker','progressive','bind_state','listener')
        if ($diag.schema -cne 'TTV-OWNER-BRAIN-R2-STARTUP-DIAG-V1' -or
            $diag.nonce -cne $nonce -or
            (@($diag.PSObject.Properties.Name | Sort-Object) -join ',') -cne
                (@($fields | Sort-Object) -join ',') -or
            $diag.status -cnotin @('NO_MATCHING_STARTUP','LOG_MISSING',
                'LOG_NOT_READABLE','BOOT_OBSERVED',
                'FAILURE_TRACE_OBSERVED','BOUNDS_INVALID') -or
            $diag.bind_state -cnotin @('UNKNOWN','LOCAL_ADDRESS_PRESENT','LOCAL_ADDRESS_MISSING') -or
            $diag.listener -cnotin @('UNKNOWN','NONE','OTHER','TORRENT_TV_OWNED') -or
            $diag.stage -cnotmatch '^[A-Z][A-Z0-9_]{2,75}$' -or
            $diag.kind -cnotmatch '^[A-Za-z][A-Za-z0-9_]{2,50}$' -or
            $diag.code -cnotmatch '^[A-Z][A-Z0-9_]{2,90}$' -or
            $diag.worker -cnotin @('MISSING','INVALID','SUPPORTS_FIRST50','NO_FIRST50_CONSTRUCTOR') -or
            $diag.progressive -cnotin @('MISSING','INVALID','SUPPORTS_FIRST50','NO_FIRST50_CONSTRUCTOR') -or
            ($diag.boots -isnot [int] -and $diag.boots -isnot [long]) -or
            ($diag.failures -isnot [int] -and $diag.failures -isnot [long])) {
            throw 'HOSTOPS_BRAIN_STARTUP_SCHEMA_INVALID'
        }
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -
            [long]$diag.observed_utc_epoch
        if ($age -lt 0 -or $age -gt 180 -or
            $diag.boots -lt 0 -or $diag.boots -gt 20 -or
            $diag.failures -lt 0 -or $diag.failures -gt 20) {
            throw 'HOSTOPS_BRAIN_STARTUP_BOUNDS_INVALID'
        }
        Write-Output ('HOSTOPS_BRAIN_STARTUP_STATUS=' + $diag.status)
        Write-Output ('HOSTOPS_BRAIN_STARTUP_STAGE=' + $diag.stage)
        Write-Output ('HOSTOPS_BRAIN_STARTUP_KIND=' + $diag.kind)
        Write-Output ('HOSTOPS_BRAIN_STARTUP_CODE=' + $diag.code)
        Write-Output ('HOSTOPS_BRAIN_BIND_STATE=' + $diag.bind_state)
        Write-Output ('HOSTOPS_BRAIN_LISTENER=' + $diag.listener)
        Write-Output ('HOSTOPS_BRAIN_STARTUP_BOOT_COUNT=' + $diag.boots)
        Write-Output ('HOSTOPS_BRAIN_STARTUP_FAILURE_COUNT=' + $diag.failures)
        Write-Output ('HOSTOPS_BRAIN_P2_WORKER_FIRST50=' + $diag.worker)
        Write-Output ('HOSTOPS_BRAIN_P2_PROGRESSIVE_FIRST50=' + $diag.progressive)
    }
    if ($receipt.operation -ceq 'owner-brain-r2-diagnostic') {
        $path = Join-Path $outbox ('owner-brain-r2-diagnostic-' + $nonce + '.json')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw 'HOSTOPS_BRAIN_DIAG_MISSING'
        }
        $item = Get-Item -LiteralPath $path -Force
        if ($item.Length -le 0 -or $item.Length -gt 768 -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'HOSTOPS_BRAIN_DIAG_RECEIPT_INVALID'
        }
        $result = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $fields = @('schema','nonce','observed_utc_epoch','prior_log',
                    'reason','phase','error_kind','source_line','overlay_status','overlay_at','overlay_error','overlay_missing','task','heartbeat','matched','missing','invalid')
        $reasonCode = [string]$result.reason
        if ($result.schema -cne 'TTV-OWNER-BRAIN-R2-DIAG-V1' -or
            $result.nonce -cne $nonce -or
            (@($result.PSObject.Properties.Name | Sort-Object) -join ',') -cne
                (@($fields | Sort-Object) -join ',') -or
            $result.prior_log -isnot [bool] -or
            ($reasonCode -cnotmatch '^HOLD_[A-Z0-9_]{3,75}$' -and
                $reasonCode -cnotin @('NO_PRIOR_BRAIN_INSTALL_LOG',
                                     'FAILED_ROLLED_BACK','INSTALL_SUCCEEDED_IN_LOG',
                                     'UNCLASSIFIED_PRIVATE_FAILURE')) -or
            $result.phase -cnotin @('NOT_OBSERVED','BEFORE_PREFLIGHT',
                                      'PREFLIGHT_COMPLETE','BACKUP_CREATED') -or
            $result.error_kind -cnotin @('NONE','PS_MISSING_PROPERTY',
                'PS_COMMAND_NOT_FOUND','PS_PARSE','PS_ARGUMENT',
                'FILE_NOT_FOUND','PS_RUNTIME','OTHER_PRIVATE_EXCEPTION') -or
            ($result.source_line -isnot [int] -and $result.source_line -isnot [long]) -or
            $result.source_line -lt 0 -or $result.source_line -gt 999 -or
            $result.overlay_status -cnotin @('PASS','FAIL','NO_PYTHON_RESULT',
                'PYTHON_LAUNCH_FAILED') -or
            $result.overlay_at -cnotmatch '^[A-Za-z0-9_]{2,80}$' -or
            $result.overlay_error -cnotmatch '^[A-Za-z0-9_]{2,80}$' -or
            $result.overlay_missing -cnotmatch '^[A-Za-z0-9_]{2,80}$' -or
            $result.task -cnotin @('Running','Ready','Disabled') -or
            $result.heartbeat -cnotin @('FRESH_PID_BOUND','NOT_VERIFIED') -or
            ($result.matched -isnot [int] -and $result.matched -isnot [long]) -or
            ($result.missing -isnot [int] -and $result.missing -isnot [long]) -or
            ($result.invalid -isnot [int] -and $result.invalid -isnot [long])) {
            throw 'HOSTOPS_BRAIN_DIAG_SCHEMA_INVALID'
        }
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -
            [long]$result.observed_utc_epoch
        if ($age -lt 0 -or $age -gt 180 -or
            $result.matched -lt 0 -or $result.matched -gt 14 -or
            $result.missing -lt 0 -or $result.missing -gt 14 -or
            $result.invalid -lt 0 -or $result.invalid -gt 14 -or
            $result.matched + $result.missing + $result.invalid -gt 14) {
            throw 'HOSTOPS_BRAIN_DIAG_BOUNDS_INVALID'
        }
        Write-Output ('HOSTOPS_BRAIN_R2_PRIOR_LOG=' + [string]$result.prior_log)
        Write-Output ('HOSTOPS_BRAIN_R2_REASON=' + $reasonCode)
        Write-Output ('HOSTOPS_BRAIN_R2_PHASE=' + $result.phase)
        Write-Output ('HOSTOPS_BRAIN_R2_ERROR_KIND=' + $result.error_kind)
        Write-Output ('HOSTOPS_BRAIN_R2_SOURCE_LINE=' + $result.source_line)
        Write-Output ('HOSTOPS_BRAIN_R2_OVERLAY_STATUS=' + $result.overlay_status)
        Write-Output ('HOSTOPS_BRAIN_R2_OVERLAY_AT=' + $result.overlay_at)
        Write-Output ('HOSTOPS_BRAIN_R2_OVERLAY_ERROR=' + $result.overlay_error)
        Write-Output ('HOSTOPS_BRAIN_R2_OVERLAY_MISSING=' + $result.overlay_missing)
        Write-Output ('HOSTOPS_BRAIN_R2_TASK=' + $result.task)
        Write-Output ('HOSTOPS_BRAIN_R2_HEARTBEAT=' + $result.heartbeat)
        Write-Output ('HOSTOPS_BRAIN_R2_INSTALLED_MATCH=' + $result.matched)
        Write-Output ('HOSTOPS_BRAIN_R2_INSTALLED_MISSING=' + $result.missing)
        Write-Output ('HOSTOPS_BRAIN_R2_INSTALLED_INVALID=' + $result.invalid)
    }
    if ($receipt.operation -ceq 'owner-brain-neutral-diagnostic') {
        $p = Join-Path $outbox ('owner-neutral-diag-' + $nonce + '.json')
        $item = Get-Item -LiteralPath $p -Force
        if ($item.Length -le 0 -or $item.Length -gt 1024 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'NEUTRAL_DIAG_RECEIPT_INVALID' }
        $r = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
        if ($r.schema -cne 'TTV-OWNER-NEUTRAL-DIAG-V1' -or $r.nonce -cne $nonce -or
            $r.reason -cnotin @('NO_LOG',
    'UNCLASSIFIED',
    'NOT_FOUND',
    'PINNED_SOURCE_HASH_MISMATCH',
    'PINNED_SOURCE_PATH_INVALID',
    'TRUSTED_SOURCE_BRANCH_DRIFT',
    'NETWORK_FETCH_FAILED',
    'PS_RUNTIME_ERROR',
    'ROLLED_BACK',
    'HOLD_DIRECTORY_INVALID',
    'HOLD_FILE_INVALID',
    'HOLD_OWNER_TASK_IDENTITY_DRIFT',
    'HOLD_PENDING_OWNER_EVENTS',
    'HOLD_OWNER_TASK_STATE_UNKNOWN',
    'HOLD_RESIDUAL_WORKER_SET_UNEXPECTED',
    'HOLD_RESIDUAL_IDENTITY_UNVERIFIED',
    'HOLD_RESIDUAL_TASK_REENABLED',
    'HOLD_RESIDUAL_CHANGED',
    'HOLD_RESIDUAL_NOT_STOPPED',
    'HOLD_INTERACTIVE_OWNER_REQUIRED',
    'HOLD_OWNER_TASK_NOT_RUNNING_OR_READY',
    'HOLD_OWNER_HEARTBEAT_NOT_VERIFIED',
    'HOLD_STOPPED_TASK_RESIDUAL_WORKERS',
    'HOLD_PINNED_DOWNLOAD_HASH_DRIFT',
    'HOLD_INSTALLED_ENTRYPOINT_SHA_DRIFT',
    'HOLD_STAGED_SOURCE_SHA_DRIFT',
    'HOLD_STAGED_OVERLAY_IMPORT_FAILED_OWNER_UNCHANGED',
    'HOLD_BACKUP_HASH_INVALID',
    'HOLD_OWNER_NOT_STOPPED_DURING_APPLY',
    'HOLD_SOURCE_CHANGED_DURING_APPLY',
    'HOLD_NEW_MODULE_PATH_CONFLICT',
    'HOLD_INSTALLED_BASELINE_CHANGED',
    'HOLD_TEMP_COPY_DRIFT',
    'HOLD_POST_REPLACE_HASH_CHANGED',
    'HOLD_OFFLINE_IMPORT_FAILED',
    'HOLD_FRESH_OWNER_NOT_VERIFIED',
    'HOLD_ROLLBACK_NEW_FILE_DRIFT',
    'HOLD_ROLLBACK_BACKUP_DRIFT',
    'HOLD_ROLLBACK_INSTALLED_DRIFT',
    'HOLD_ROLLBACK_ORIGINAL_HASH_CHANGED',
    'HOLD_ROLLBACK_OWNER_HEARTBEAT_FAILED_TASK_HOLD') -or
            $r.prior -cnotin @('NOT_FOUND','OTHER','FAILED_NO_RETRY','SUCCESS') -or
            $r.task -cnotin @('Ready','Disabled','Running','Queued','Unknown') -or
            $r.agy -cnotin @('OLD','NEW','DRIFT','MISSING') -or
            $r.inbox -cnotin @('OLD','NEW','DRIFT','MISSING')) { throw 'NEUTRAL_DIAG_RECEIPT_INVALID' }
        foreach ($f in @('reason','prior','task','agy','inbox')) {
            Write-Output ('HOSTOPS_NEUTRAL_DIAG_' + $f.ToUpperInvariant() + '=' + $r.$f)
        }
    }
    if ($receipt.operation -ceq 'owner-runtime-audit') {
        $auditPath = Join-Path $outbox ('owner-runtime-' + $nonce + '.json')
        if (-not (Test-Path -LiteralPath $auditPath -PathType Leaf)) {
            throw 'HOSTOPS_OWNER_AUDIT_RECEIPT_MISSING'
        }
        $auditItem = Get-Item -LiteralPath $auditPath -Force
        if ($auditItem.Length -le 0 -or $auditItem.Length -gt 4096 -or
            ($auditItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'HOSTOPS_OWNER_AUDIT_RECEIPT_INVALID'
        }
        $audit = Get-Content -LiteralPath $auditPath -Raw -Encoding UTF8 |
            ConvertFrom-Json
        $names = @(
            'owner_p3_p4_entrypoint.py',
            'owner_p3_p4_runtime.py',
            'p3_signed_signal_to_owner.py',
            'owner_session_bridge.py',
            'automatic_vietsub_flow.py',
            'brain_english_inbox.py',
            'owner_r2_progressive_registry.py',
            'owner_full_flow_snapshot_v4.py',
            'dual_subtitle_catalog.py',
            'p3_p4_shared_https_route_r0.py'
        )
        if (@($audit.PSObject.Properties.Name | Sort-Object) -join ',' -cne
                'heartbeat,inflight_count,modules,nonce,observed_utc_epoch,schema,task_state' -or
            $audit.schema -cne 'TTV-OWNER-RUNTIME-AUDIT-V1' -or
            $audit.nonce -cne $nonce -or
            $audit.task_state -cnotin @('Running','Ready','Disabled','UNKNOWN') -or
            $audit.heartbeat -cnotin @('FRESH_PID_BOUND','NOT_VERIFIED') -or
            ($audit.inflight_count -isnot [int] -and $audit.inflight_count -isnot [long])) {
            throw 'HOSTOPS_OWNER_AUDIT_SCHEMA_INVALID'
        }
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -
            [long]$audit.observed_utc_epoch
        if ($age -lt 0 -or $age -gt 180 -or
            $audit.inflight_count -lt -1 -or $audit.inflight_count -gt 10000 -or
            (@($audit.modules.PSObject.Properties.Name | Sort-Object) -join ',') -cne
                (@($names | Sort-Object) -join ',')) {
            throw 'HOSTOPS_OWNER_AUDIT_BOUNDS_INVALID'
        }
        Write-Output ('HOSTOPS_OWNER_AUDIT_TASK=' + $audit.task_state)
        Write-Output ('HOSTOPS_OWNER_AUDIT_HEARTBEAT=' + $audit.heartbeat)
        Write-Output ('HOSTOPS_OWNER_AUDIT_INFLIGHT=' + $audit.inflight_count)
        foreach ($name in $names) {
            $value = [string]$audit.modules.$name
            if ($value -cnotmatch '^[0-9a-f]{64}$' -and
                $value -cnotin @('MISSING','INVALID','UNREADABLE')) {
                throw 'HOSTOPS_OWNER_AUDIT_MODULE_RESULT_INVALID'
            }
            $key = ($name.Replace('.','_')).ToUpperInvariant()
            Write-Output ("HOSTOPS_OWNER_AUDIT_$key=$value")
        }
    }
    if ($receipt.operation -ceq 'agy-website-srt-diagnostic') {
        $summaryFile = Join-Path $outbox ('agy-website-diag-' + $nonce + '.json')
        if (-not (Test-Path -LiteralPath $summaryFile -PathType Leaf)) {
            throw 'HOSTOPS_AGY_WEBSITE_DIAG_SUMMARY_MISSING'
        }
        $summaryItem = Get-Item -LiteralPath $summaryFile -Force
        if ($summaryItem.Length -le 0 -or $summaryItem.Length -gt 1024 -or
            ($summaryItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'HOSTOPS_AGY_WEBSITE_DIAG_SUMMARY_INVALID'
        }
        $summary = Get-Content -LiteralPath $summaryFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $fields = @('schema','nonce','prior','owner_log','error','agy_output',
                    'srt','bytes','cues','sha_match')
        $allowedErrors = @('UNDETERMINED','OWNER_OPS_OPERATION_EXIT',
            'OWNER_OPS_PINNED_SOURCE_FAILURE',
            'AGY_WEBSITE_SMOKE_CLI_NOT_AVAILABLE',
            'AGY_WEBSITE_SMOKE_NOT_STARTED','AGY_WEBSITE_SMOKE_TIMEOUT',
            'AGY_WEBSITE_SMOKE_COMMAND_FAILED',
            'AGY_WEBSITE_SMOKE_SRT_NOT_SAVED',
            'AGY_WEBSITE_SMOKE_SRT_SIZE_INVALID',
            'AGY_WEBSITE_SMOKE_NOT_SRT','AGY_WEBSITE_SMOKE_DIFFERENT_BYTES')
        if ($summary.schema -cne 'TTV-AGY-WEBSITE-DIAG-V1' -or
            $summary.nonce -cne $nonce -or
            (@($summary.PSObject.Properties.Name | Sort-Object) -join ',') -cne
                (@($fields | Sort-Object) -join ',') -or
            $summary.prior -cnotin @('NOT_FOUND','FAILED_NO_RETRY','OTHER') -or
            $summary.owner_log -cnotin @('FOUND','NOT_FOUND') -or
            $summary.error -cnotin $allowedErrors -or
            $summary.agy_output -cnotin @('PRESENT','EMPTY','NOT_FOUND') -or
            $summary.srt -cnotin @('NOT_FOUND','EXACT_VALID_SRT',
                'VALID_DIFFERENT_HASH','INVALID_SRT','INVALID_SIZE_OR_LINK') -or
            $summary.sha_match -cnotin @('UNKNOWN','YES','NO') -or
            $summary.bytes -isnot [ValueType] -or
            [int]$summary.bytes -lt 0 -or [int]$summary.bytes -gt 2000000 -or
            $summary.cues -isnot [ValueType] -or
            [int]$summary.cues -lt 0 -or [int]$summary.cues -gt 50000) {
            throw 'HOSTOPS_AGY_WEBSITE_DIAG_CONTRACT_INVALID'
        }
        foreach ($field in @('prior','owner_log','error','agy_output',
                             'srt','bytes','cues','sha_match')) {
            $value = [string]$summary.PSObject.Properties[$field].Value
            Write-Output ('AGY_WEBSITE_DIAG_' + $field.ToUpperInvariant() + '=' + $value)
        }
    }
    if ($receipt.operation -ceq 'owner-ts-ebml-owner-readonly') {
        $summaryFile = Join-Path $outbox ('owner-ebml-cues-' + $nonce + '.json')
        if (-not (Test-Path -LiteralPath $summaryFile -PathType Leaf)) {
            throw 'HOSTOPS_OWNER_EBML_SUMMARY_MISSING'
        }
        $summaryItem = Get-Item -LiteralPath $summaryFile -Force
        if ($summaryItem.Length -le 0 -or $summaryItem.Length -gt 512 -or
            ($summaryItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'HOSTOPS_OWNER_EBML_SUMMARY_INVALID'
        }
        $row = Get-Content -LiteralPath $summaryFile -Raw | ConvertFrom-Json
        $metrics = @('state','identity','en_ffp','en_mkv','cues_indexed',
                     'cues_relative','cues_verified','bytes','requests','ms','first_ten_ms')
        $expected = @('schema','nonce') + $metrics
        if ($row.schema -cne 'TTV-OWNER-EBML-CUES-V1' -or
            $row.nonce -cne $nonce -or
            (@($row.PSObject.Properties.Name | Sort-Object) -join ',') -cne
                (@($expected | Sort-Object) -join ',') -or
            [string]$row.state -cnotmatch '^[A-Z0-9_]{3,50}$' -or
            $row.identity -cnotin @('UNVERIFIED','OWNER_EVENT_MATCH')) {
            throw 'HOSTOPS_OWNER_EBML_FIELDS_INVALID'
        }
        $maxima = @{en_ffp=128;en_mkv=128;cues_indexed=30000;
                    cues_relative=30000;cues_verified=120;bytes=8388608;
                    requests=300;ms=160000;first_ten_ms=160000}
        foreach ($field in @($metrics | Where-Object { $_ -notin @('state','identity') })) {
            if ($row.$field -isnot [ValueType] -or
                [long]$row.$field -lt 0 -or [long]$row.$field -gt $maxima[$field]) {
                throw 'HOSTOPS_OWNER_EBML_COUNTER_INVALID'
            }
        }
        foreach ($field in $metrics) {
            Write-Output ('HOSTOPS_OWNER_EBML_' + $field.ToUpperInvariant() + '=' + $row.$field)
        }
        Write-Output 'HOSTOPS_OWNER_EBML_READONLY_PASS'
    }
    if ($receipt.operation -ceq 'owner-ts-en-sidecar-readonly') {
        $summaryFile = Join-Path $outbox 'owner-ts-en-sidecar.json'
        if (Test-Path -LiteralPath $summaryFile -PathType Leaf) {
            $item = Get-Item -LiteralPath $summaryFile -Force
            if ($item.Length -gt 0 -and $item.Length -le 1024 -and
                -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $row = Get-Content -LiteralPath $summaryFile -Raw | ConvertFrom-Json
                $required = @('schema','nonce','state','metadata','endpoint',
                              'en_tracks','installed_reader','download','cues','byte_count')
                if ($row.schema -ceq 'TTV-OWNER-TS-EN-SIDECAR-V1' -and
                    $row.nonce -ceq $nonce -and
                    (@($row.PSObject.Properties.Name | Sort-Object) -join ',') -ceq
                        (@($required | Sort-Object) -join ',') -and
                    [string]$row.state -cmatch '^[A-Z0-9_]{3,70}$' -and
                    $row.metadata -cin @('NOT_RUN','MATCH','MISMATCH','UNAVAILABLE') -and
                    [string]$row.endpoint -cmatch '^[A-Z0-9_]{3,35}$' -and
                    $row.installed_reader -cin @('NOT_RUN','MISSING','FAILED','PRESENT') -and
                    $row.download -cin @('NOT_RUN','FAILED','VALID_SRT') -and
                    $row.en_tracks -is [ValueType] -and [int]$row.en_tracks -ge 0 -and
                    [int]$row.en_tracks -le 64 -and
                    $row.cues -is [ValueType] -and [int]$row.cues -ge 0 -and
                    [int]$row.cues -le 30000 -and
                    $row.byte_count -is [ValueType] -and [int]$row.byte_count -ge 0 -and
                    [int]$row.byte_count -le 262144) {
                    foreach ($field in @('state','metadata','endpoint','en_tracks',
                               'installed_reader','download','cues','byte_count')) {
                        Write-Output ('HOSTOPS_TS_EN_' + $field.ToUpperInvariant() +
                                      '=' + $row.$field)
                    }
                }
            }
        }
    }
    if ($receipt.operation -ceq 'owner-ts-embedded-en-readonly') {
        $summaryFile = Join-Path $outbox 'owner-ts-embedded-en.json'
        if (Test-Path -LiteralPath $summaryFile -PathType Leaf) {
            $item = Get-Item -LiteralPath $summaryFile -Force
            if ($item.Length -gt 0 -and $item.Length -le 1024 -and
                -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $row = Get-Content -LiteralPath $summaryFile -Raw | ConvertFrom-Json
                $required = @('schema','nonce','state','metadata','ffp','en_text',
                              'en_bitmap','unlabeled_text','other_subs','elapsed_ms','ffmpeg',
                              'en_default','track_choice','prefix_result','prefix_cues',
                              'prefix_elapsed_ms','prefix_bytes','en_forced',
                              'play_status','play_elapsed_ms','play_bytes',
                              'prefix_error','prefix_exit','prefix_progress_s')
                if ($row.schema -ceq 'TTV-OWNER-EMBEDDED-EN-V1' -and
                    $row.nonce -ceq $nonce -and
                    (@($row.PSObject.Properties.Name | Sort-Object) -join ',') -ceq
                        (@($required | Sort-Object) -join ',') -and
                    [string]$row.state -cmatch '^[A-Z0-9_]{3,60}$' -and
                    $row.metadata -cin @('NOT_RUN','MATCH') -and
                    [string]$row.ffp -cmatch '^[A-Z0-9_]{3,30}$' -and
                    $row.ffmpeg -cin @('NOT_CHECKED','AVAILABLE','MISSING') -and
                    $row.track_choice -cin @('NOT_RUN','UNIQUE_DEFAULT','UNIQUE_NONFORCED','SAMPLE_ONLY') -and
                    [string]$row.play_status -cmatch '^(NOT_RUN|HTTP_[0-9]{3}|HTTP_OTHER|READ_TIMEOUT|UNAVAILABLE)$' -and
                    $row.prefix_error -cin @('NONE','HTTP_AUTH','HTTP_NOT_FOUND','TIMEOUT',
                                            'STREAM_MAP_INVALID','INVALID_MEDIA','CONNECTION_REFUSED',
                                            'INPUT_OPEN_FAILED','OTHER_FFMPEG_ERROR') -and
                    $row.prefix_exit -cin @('NOT_RUN','KILLED_AT_LIMIT','ZERO','NONZERO') -and
                    $row.prefix_result -cin @('NOT_RUN','FFMPEG_LAUNCH_FAILED',
                                               'CUES_120_REACHED','PARTIAL_CUES',
                                               'NO_CUES_BEFORE_DEADLINE','OUTPUT_CAP_REACHED') -and
                    $row.en_text -is [ValueType] -and [int]$row.en_text -ge 0 -and
                    [int]$row.en_text -le 128 -and
                    $row.en_bitmap -is [ValueType] -and [int]$row.en_bitmap -ge 0 -and
                    [int]$row.en_bitmap -le 128 -and
                    $row.unlabeled_text -is [ValueType] -and [int]$row.unlabeled_text -ge 0 -and
                    [int]$row.unlabeled_text -le 128 -and
                    $row.other_subs -is [ValueType] -and [int]$row.other_subs -ge 0 -and
                    [int]$row.other_subs -le 128 -and
                    $row.elapsed_ms -is [ValueType] -and [int]$row.elapsed_ms -ge 0 -and
                    [int]$row.elapsed_ms -le 120000 -and
                    $row.en_default -is [ValueType] -and [int]$row.en_default -ge 0 -and
                    [int]$row.en_default -le 128 -and
                    $row.prefix_cues -is [ValueType] -and [int]$row.prefix_cues -ge 0 -and
                    [int]$row.prefix_cues -le 120 -and
                    $row.prefix_elapsed_ms -is [ValueType] -and [int]$row.prefix_elapsed_ms -ge 0 -and
                    [int]$row.prefix_elapsed_ms -le 120000 -and
                    $row.prefix_bytes -is [ValueType] -and [int]$row.prefix_bytes -ge 0 -and
                    [int]$row.prefix_bytes -le 262144 -and
                    $row.en_forced -is [ValueType] -and [int]$row.en_forced -ge 0 -and
                    [int]$row.en_forced -le 128 -and
                    $row.play_elapsed_ms -is [ValueType] -and [int]$row.play_elapsed_ms -ge 0 -and
                    [int]$row.play_elapsed_ms -le 120000 -and
                    $row.play_bytes -is [ValueType] -and [int]$row.play_bytes -ge 0 -and
                    [int]$row.play_bytes -le 1048576 -and
                    $row.prefix_progress_s -is [ValueType] -and [int]$row.prefix_progress_s -ge 0 -and
                    [int]$row.prefix_progress_s -le 86400) {
                    foreach ($field in @('state','metadata','ffp','en_text',
                                         'en_bitmap','unlabeled_text','other_subs',
                                         'elapsed_ms','ffmpeg','en_default',
                                         'track_choice','prefix_result','prefix_cues',
                                         'prefix_elapsed_ms','prefix_bytes','en_forced',
                                         'play_status','play_elapsed_ms',
                                         'play_bytes','prefix_error','prefix_exit','prefix_progress_s')) {
                        Write-Output ('HOSTOPS_EMBEDDED_' + $field.ToUpperInvariant() +
                                      '=' + $row.$field)
                    }
                }
            }
        }
    }
    if ($receipt.operation -ceq 'owner-en406-recovery-diagnostic') {
        $summaryFile = Join-Path $outbox 'en406-recovery-diag.json'
        if (Test-Path -LiteralPath $summaryFile -PathType Leaf) {
            $item = Get-Item -LiteralPath $summaryFile -Force
            if ($item.Length -gt 0 -and $item.Length -le 512 -and
                -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $summary = Get-Content -LiteralPath $summaryFile -Raw | ConvertFrom-Json
                $fields = @('schema','nonce','quarantine','restore','task','marker','p2')
                $causes = @('RECEIPT_NOT_UNIQUE','PRIVATE_LOG_MISSING','PRIVATE_LOG_INVALID',
                    'UNCLASSIFIED_PRIVATE_ERROR','MARKER_ARCHIVED_THEN_FAILED',
                    'TASK_DISABLED_MARKER_ORIGINAL','INTERACTIVE_OWNER_REQUIRED',
                    'ROOT_MISSING','ROOT_REPARSE_POINT','OWNER_TASK_IDENTITY_DRIFT',
                    'OWNER_TASK_NOT_RUNNING','PENDING_OWNER_EVENT',
                    'P2_UNKNOWN_OR_ACTIVE_EFFECT','MARKER_NOT_UNIQUE','FILE_MISSING',
                    'FILE_UNTRUSTED','MARKER_CONTENT_CHANGED','BLOCKED_EVENT_NOT_FOUND',
                    'BLOCKED_EVENT_NOT_RECENT','MULTIPLE_RECENT_BLOCKED_EVENTS',
                    'LATEST_BLOCKED_EVENT_NOT_BOUND','OWNER_EVENT_CLAIM_INVALID',
                    'MARKER_NEWER_THAN_EVENT','CURRENT_AI_EN_ALREADY_CACHED',
                    'CURRENT_LEGACY_EN_ALREADY_CACHED','CURRENT_FAILURE_TRACE_NOT_PROVEN',
                    'HEALTH_NOT_READABLE','UNEXPECTED_WORKER_COUNT',
                    'OWNER_WORKER_IDENTITY_UNVERIFIED','WORKERS_STILL_RUNNING',
                    'PREMOVE_CLAIM_DRIFT','ARCHIVED_BYTES_MISMATCH',
                    'RESTART_NEW_OWNER_NOT_VERIFIED','OWNER_INTERACTIVE_REQUIRED',
                    'OWNER_INSTALL_ROOT_INVALID','POST_QUARANTINE_TASK_NOT_DISABLED',
                    'OWNER_WORKERS_PRESENT','P2_STATE_MISSING',
                    'EXACT_B11_ARCHIVE_NOT_VERIFIED','REPARSE_PATH',
                    'B11_NO_RETRY_LEDGER_INVALID','P2_INFLIGHT_OR_ACTIVE_LOCK',
                    'PREVIOUS_HEALTH_UNREADABLE','INSTALLED_SOURCE_DRIFT',
                    'SOURCE_HASH_MISMATCH','POST_QUARANTINE_CONCURRENCY_DRIFT',
                    'BACKUP_HASH_MISMATCH','INSTALLED_HASH_MISMATCH',
                    'OFFLINE_IMPORT_FAILED','FRESH_OWNER_HEALTH_NOT_VERIFIED',
                    'POST_RESTART_SOURCE_HASH_DRIFT')
                if ($summary.schema -ceq 'TTV-OWNER-EN406-RECOVERY-DIAG-V1' -and
                    $summary.nonce -ceq $nonce -and
                    (@($summary.PSObject.Properties.Name | Sort-Object) -join ',') -ceq
                        (@($fields | Sort-Object) -join ',') -and
                    $summary.quarantine -cin $causes -and
                    $summary.restore -cin $causes -and
                    $summary.task -cin @('Running','Ready','Disabled','OTHER') -and
                    $summary.marker -cin @('UNKNOWN','ONE_ARCHIVED_NONE_ACTIVE',
                        'ONE_ACTIVE_NONE_ARCHIVED','MULTIPLE_ACTIVE','NO_MARKER_SEEN',
                        'MIXED_MARKER_STATE') -and
                    $summary.p2 -cin @('UNKNOWN','CLEAR','BUSY_OR_UNCERTAIN')) {
                    Write-Output ('HOSTOPS_EN406_DIAG_QUARANTINE=' + $summary.quarantine)
                    Write-Output ('HOSTOPS_EN406_DIAG_RESTORE=' + $summary.restore)
                    Write-Output ('HOSTOPS_EN406_DIAG_TASK=' + $summary.task)
                    Write-Output ('HOSTOPS_EN406_DIAG_MARKER=' + $summary.marker)
                    Write-Output ('HOSTOPS_EN406_DIAG_P2=' + $summary.p2)
                }
            }
        }
    }
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
                    'route','download','cached','en_source','p2_outcome','p4_reject')
                $safeP4Rejects = @('NOT_OBSERVED','OTHER','UNCLASSIFIED',
                    'P4_ACTIVATE_SCHEMA_INVALID','P4_ACTIVATE_AUTH_INVALID',
                    'P4_ACTIVATE_REPLAY','P4_TOO_MANY_SESSIONS',
                    'P4_ASSUMED_SOURCE_MISSING','P4_PROGRESSIVE_FEED_BIND_FAILED',
                    'P4_READY_FEED_PUBLISH_FAILED','P4_TRANSLATION_START_FAILED',
                    'P3_READY_NO_CURRENT_ACCEPTED_SOURCE',
                    'P3_READY_CURRENT_MEDIA_OR_CONSENT_CHANGED',
                    'P3_READY_PRIVATE_SOURCE_NOT_READY',
                    'P4_ROLLING_CURRENT_TV_UNAVAILABLE','P4_ROLLING_TV_SESSION_CHANGED',
                    'P4_ROLLING_CHECKPOINT_INVALID','P4_ROLLING_CHECKPOINT_NOT_VERIFIED',
                    'P4_ROLLING_CHECKPOINT_HASH_CHANGED','P4_ROLLING_CHECKPOINT_GAP',
                    'P4_ROLLING_SOURCE_NOT_VERIFIED','P4_ROLLING_SOURCE_RECEIPT_INVALID',
                    'P4_ROLLING_SOURCE_INDEX_INVALID','P4_ROLLING_ABANDONED_JOB_HOLD',
                    'P4_ROLLING_SOURCE_CHANGED','P4_ROLLING_REVISION_IDENTITY_INVALID')
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
                        'VIETSUB_READY','REVIEW_REQUIRED') -and
                    $summary.p4_reject -cin $safeP4Rejects) {
                    Write-Output ('HOSTOPS_OWNER_SOURCE_SCOPE=' + $summary.scope)
                    Write-Output ('HOSTOPS_OWNER_SOURCE_TITLE=' + $summary.title_source)
                    Write-Output ('HOSTOPS_OWNER_SOURCE_SEARCH=' + $summary.search)
                    Write-Output ('HOSTOPS_OWNER_SOURCE_ROUTE=' + $summary.route)
                    Write-Output ('HOSTOPS_OWNER_SOURCE_DOWNLOAD=' + $summary.download)
                    Write-Output ('HOSTOPS_OWNER_SOURCE_CACHED=' + $summary.cached)
                    Write-Output ('HOSTOPS_OWNER_SOURCE_EN_SOURCE=' + $summary.en_source)
                    Write-Output ('HOSTOPS_OWNER_SOURCE_P2_OUTCOME=' + $summary.p2_outcome)
                    Write-Output ('HOSTOPS_OWNER_SOURCE_P4_REJECT=' + $summary.p4_reject)
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
    if ($receipt.operation -ceq 'owner-p2-installed-hashes-readonly') {
        $summaryFile = Join-Path $outbox 'p2-baseline.json'
        if (Test-Path -LiteralPath $summaryFile -PathType Leaf) {
            $item = Get-Item -LiteralPath $summaryFile -Force
            if ($item.Length -gt 0 -and $item.Length -le 512 -and
                -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $summary = Get-Content -LiteralPath $summaryFile -Raw | ConvertFrom-Json
                $fields = @('schema','nonce','opensubtitles','owner_bridge','p4_registry','owner')
                if ($summary.schema -cne 'TTV-P2-BASELINE-HASH-V1' -or
                    $summary.nonce -cne $nonce -or
                    (@($summary.PSObject.Properties.Name | Sort-Object) -join ',') -cne
                        (@($fields | Sort-Object) -join ',') -or
                    $summary.opensubtitles -cnotmatch '^(NOT_OBSERVED|[0-9a-f]{64})$' -or
                    $summary.owner_bridge -cnotmatch '^(NOT_OBSERVED|[0-9a-f]{64})$' -or
                    $summary.p4_registry -cnotmatch '^(NOT_OBSERVED|[0-9a-f]{64})$' -or
                    $summary.owner -cnotin @('NOT_OBSERVED','RUNNING','READY','OTHER')) {
                    throw 'HOSTOPS_P2_BASELINE_INVALID'
                }
                Write-Output ('HOSTOPS_P2_BASELINE_OPENSUBTITLES=' + $summary.opensubtitles)
                Write-Output ('HOSTOPS_P2_BASELINE_OWNER_BRIDGE=' + $summary.owner_bridge)
                Write-Output ('HOSTOPS_P2_BASELINE_P4_REGISTRY=' + $summary.p4_registry)
                Write-Output ('HOSTOPS_P2_BASELINE_OWNER=' + $summary.owner)
            }
        }
    }
    if ($receipt.operation -ceq 'owner-p2-block-trace-readonly') {
        $summaryFile = Join-Path $outbox 'block-trace.json'
        if (Test-Path -LiteralPath $summaryFile -PathType Leaf) {
            $item = Get-Item -LiteralPath $summaryFile -Force
            if ($item.Length -gt 0 -and $item.Length -le 1024 -and
                -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $summary = Get-Content -LiteralPath $summaryFile -Raw | ConvertFrom-Json
                $fields = @('schema','nonce','scope','p3','route','claimed',
                    'blocked','reason','exception_type','exception_code',
                    'fault_site','provider_claim','cache','p4')
                $valid = $summary.schema -ceq 'TTV-OWNER-P2-BLOCK-TRACE-V1' -and
                    $summary.nonce -ceq $nonce -and
                    (@($summary.PSObject.Properties.Name | Sort-Object) -join ',') -ceq
                        (@($fields | Sort-Object) -join ',') -and
                    $summary.scope -cin @('NOT_OBSERVED','LOG_UNAVAILABLE','HEALTH_STALE',
                        'SESSION_NOT_IN_TAIL','NO_DISPATCH','CURRENT_OWNER_SESSION','LOCAL_READ_ERROR') -and
                    $summary.p3 -cin @('NOT_OBSERVED','DISPATCHED') -and
                    $summary.route -cin @('NOT_OBSERVED','VI_READY','EN_TRANSLATE',
                        'REVIEW_REQUIRED','NO_MATCH') -and
                    $summary.claimed -cin @('YES','NO') -and
                    $summary.blocked -cin @('YES','NO') -and
                    $summary.provider_claim -cin @('YES','NO') -and
                    $summary.cache -cin @('YES','NO') -and
                    $summary.p4 -cin @('NOT_OBSERVED','REVISION_READY','P4_ACTIVATE_HTTP_200','P4_ACTIVATE_REJECTED_P4_ACTIVATE_AUTH_INVALID','P4_ACTIVATE_REJECTED_P4_ACTIVATE_HTTP_200','P4_ACTIVATE_REJECTED_P4_ACTIVATE_REJECTED_','P4_ACTIVATE_REJECTED_P4_ACTIVATE_REPLAY','P4_ACTIVATE_REJECTED_P4_ACTIVATE_SCHEMA_INVALID','P4_ACTIVATE_REJECTED_P4_ACTIVATION_REQUEST_INVALID','P4_ACTIVATE_REJECTED_P4_ASSUMED_SOURCE_MAP_INVALID','P4_ACTIVATE_REJECTED_P4_ASSUMED_SOURCE_MISSING','P4_ACTIVATE_REJECTED_P4_DERIVATION_SCOPE_INVALID','P4_ACTIVATE_REJECTED_P4_DEVICE_SECRET_INVALID','P4_ACTIVATE_REJECTED_P4_EVENT_CALLBACK_INVALID','P4_ACTIVATE_REJECTED_P4_HTTPS_TLS_CONTEXT_REQUIRED','P4_ACTIVATE_REJECTED_P4_MOCK_FACTORY_MEDIA_MISMATCH','P4_ACTIVATE_REJECTED_P4_MOCK_ONE_MEDIA_ONLY','P4_ACTIVATE_REJECTED_P4_MOCK_SOURCE_FACTORY_SCOPE_INVALID','P4_ACTIVATE_REJECTED_P4_PAIRED_PORT_INVALID','P4_ACTIVATE_REJECTED_P4_PROGRESSIVE_FACTORY_SCOPE_INVALID','P4_ACTIVATE_REJECTED_P4_PROGRESSIVE_FEED_BIND_FAILED','P4_ACTIVATE_REJECTED_P4_PROGRESSIVE_SOURCE_MISMATCH','P4_ACTIVATE_REJECTED_P4_READY_FACTORY_MEDIA_MISMATCH','P4_ACTIVATE_REJECTED_P4_READY_FEED_PUBLISH_FAILED','P4_ACTIVATE_REJECTED_P4_REVISION_CURRENT_SOURCE_HOLD','P4_ACTIVATE_REJECTED_P4_REVISION_HTTP_200','P4_ACTIVATE_REJECTED_P4_REVISION_HTTP_204','P4_ACTIVATE_REJECTED_P4_ROLLING_ABANDONED_JOB_HOLD','P4_ACTIVATE_REJECTED_P4_ROLLING_CHECKPOINT_GAP','P4_ACTIVATE_REJECTED_P4_ROLLING_CHECKPOINT_HASH_CHANGED','P4_ACTIVATE_REJECTED_P4_ROLLING_CHECKPOINT_INVALID','P4_ACTIVATE_REJECTED_P4_ROLLING_CHECKPOINT_NOT_VERIFIED','P4_ACTIVATE_REJECTED_P4_ROLLING_CURRENT_TV_UNAVAILABLE','P4_ACTIVATE_REJECTED_P4_ROLLING_REVISION_IDENTITY_INVALID','P4_ACTIVATE_REJECTED_P4_ROLLING_SELECTED_MEDIA_CHANGED','P4_ACTIVATE_REJECTED_P4_ROLLING_SOURCE_CHANGED','P4_ACTIVATE_REJECTED_P4_ROLLING_SOURCE_INDEX_INVALID','P4_ACTIVATE_REJECTED_P4_ROLLING_SOURCE_NOT_VERIFIED','P4_ACTIVATE_REJECTED_P4_ROLLING_SOURCE_RECEIPT_INVALID','P4_ACTIVATE_REJECTED_P4_ROLLING_TORRSERVER_FILE_CHANGED','P4_ACTIVATE_REJECTED_P4_ROLLING_TV_SESSION_CHANGED','P4_ACTIVATE_REJECTED_P4_SOURCE_FACTORY_INVALID','P4_ACTIVATE_REJECTED_P4_SOURCE_FACTORY_MEDIA_MISMATCH','P4_ACTIVATE_REJECTED_P4_TOO_MANY_SESSIONS','P4_ACTIVATE_REJECTED_P4_TOO_MANY_SOURCES','P4_ACTIVATE_REJECTED_P4_TRANSLATION_START_FAILED','P4_ACTIVATE_REJECTED_P4_VARIANT_FACTORY_SCOPE_INVALID','P4_ACTIVATE_REJECTED_P4_VARIANT_SOURCE_MISMATCH','P4_ACTIVATE_REJECTED_P4_VARIANT_UNSUPPORTED','P4_ACTIVATE_REJECTED_P4_VERIFIED_VI_FACTORY_SCOPE_INVALID','P4_ACTIVATE_REJECTED_UNCLASSIFIED','P4_ACTIVATE_REJECTED_OTHER','P4_REVISION_CURRENT_SOURCE_HOLD') -and
                    $summary.exception_type -cmatch '^(NOT_OBSERVED|OTHER|SubtitleApiError|ValueError|OSError|RuntimeError|FileNotFoundError|TimeoutError)$' -and
                    $summary.exception_code -cmatch '^[A-Z0-9_]{3,100}$' -and
                    $summary.reason -cmatch '^[A-Z0-9_]{3,100}$' -and
                    $summary.fault_site -cmatch '^[a-zA-Z0-9_]{3,80}$'
                if (-not $valid) { throw 'HOSTOPS_BLOCK_TRACE_INVALID' }
                foreach ($field in @('scope','p3','route','claimed','blocked',
                    'reason','exception_type','exception_code','fault_site',
                    'provider_claim','cache','p4')) {
                    Write-Output ('HOSTOPS_BLOCK_TRACE_' +
                        $field.ToUpperInvariant() + '=' + $summary.$field)
                }
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
                $moduleCount = if ($receipt.operation -ceq 'owner-p2-coverage-178-install') { 1 } else { 2 }
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
                    [int]$summary.installed_modules -in @(0,$moduleCount) -and
                    $summary.owner -cin @('RUNNING_READY','NOT_PROVEN')) {
                    Write-Output ('HOSTOPS_OWNER_SELECTOR_INSTALL=' + $summary.result)
                    Write-Output ('HOSTOPS_OWNER_SELECTOR_MODULES=' + [int]$summary.installed_modules + '/' + $moduleCount)
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
# A Teacher wait is only an observation window. Keep the original request/nonce.
if ($manifest.operation -ceq 'agy-native-browser-readout-1124' -and
    $manifest.script_path -cin @('hostops/laptop-ops/operations/tr-ttv-04b-teacher-no-deadline.ps1','hostops/laptop-ops/operations/tr-ttv-06-student-v3.ps1')) {
    Write-Output ('HOSTOPS_TEACHER_SOURCE=' + $commit)
    Write-Output ('HOSTOPS_TEACHER_NONCE=' + $nonce)
    Write-Output 'HOSTOPS_TEACHER_STATE=PENDING_RECEIPT_NO_RETRY'
    return
}
throw 'HOSTOPS_OWNER_OPS_TIMEOUT_UNKNOWN_EFFECT_NO_RETRY'
