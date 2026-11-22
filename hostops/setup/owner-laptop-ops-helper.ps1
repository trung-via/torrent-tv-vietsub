# Fixed Owner-interactive HostOps helper. The GitHub runner writes a small
# request; only this Owner process downloads SHA-pinned routine operations.
# Full output stays in LOCALAPPDATA, never in a public GitHub Actions log.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = 'TorrentTV-Vietsub-Laptop-HostOps'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$requestFile = Join-Path $spool 'Requests\request.json'
$receiptFile = Join-Path $spool 'Receipts\receipt.json'
$private = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\LaptopHostOps'
$nonce = 'NONE'
$sourceCommit = 'NONE'
$operation = 'NONE'
$runLog = $null
$diagnostic = 'NONE'

function AssertFile([string]$path, [long]$maximum) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'OWNER_OPS_FILE_MISSING' }
    $item = Get-Item -LiteralPath $path -Force
    if ($item.Length -le 0 -or $item.Length -gt $maximum -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'OWNER_OPS_FILE_UNTRUSTED'
    }
}
function ExactHash([string]$path) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function WriteReceipt([string]$result) {
    $record = [ordered]@{
        schema = 'TTV-LAPTOP-HOSTOPS-RECEIPT-V1'
        nonce = $nonce
        source_commit = $sourceCommit
        operation = $operation
        result = $result
        diagnostic = $diagnostic
        utc_epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($record | ConvertTo-Json -Compress))
    if ($bytes.Length -gt 512) { throw 'OWNER_OPS_RECEIPT_TOO_LARGE' }
    $temp = $receiptFile + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllBytes($temp, $bytes)
    [IO.File]::Move($temp, $receiptFile, $true)
}
function DownloadPinned([string]$path, [string]$expected,
                        [string]$destination, [long]$limit) {
    if ($path -cnotmatch '\Ahostops/laptop-ops/(?:operations/[a-z][a-z0-9-]*\.ps1|manifests/[a-z][a-z0-9-]*\.json)\z' -or
        $expected -cnotmatch '\A[0-9a-f]{64}\z') {
        throw 'OWNER_OPS_PINNED_SOURCE_PATH_INVALID'
    }
    $uri = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' +
        $sourceCommit + '/' + $path
    Invoke-WebRequest -Uri $uri -OutFile $destination -ErrorAction Stop
    AssertFile $destination $limit
    if ((ExactHash $destination) -cne $expected) {
        throw 'OWNER_OPS_PINNED_SOURCE_HASH_MISMATCH'
    }
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $loggedUser = [string](Get-CimInstance Win32_ComputerSystem).UserName
    if ($env:GITHUB_ACTIONS -ceq 'true' -or
        -not [Environment]::UserInteractive -or
        [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
        $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
        [string]::IsNullOrWhiteSpace($loggedUser) -or
        -not $identity.Name.Equals($loggedUser,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'OWNER_OPS_INTERACTIVE_OWNER_REQUIRED'
    }
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    if ([string]$task.Principal.LogonType -ine 'Interactive' -or
        [string]$task.Principal.RunLevel -ine 'Limited') {
        throw 'OWNER_OPS_TASK_IDENTITY_DRIFT'
    }
    AssertFile $requestFile 1024
    $request = Get-Content -LiteralPath $requestFile -Raw -Encoding UTF8 |
        ConvertFrom-Json -AsHashtable
    if (@($request.Keys | Sort-Object) -join ',' -cne
            'manifest_path,manifest_sha256,nonce,requested_utc_epoch,schema,source_commit' -or
        $request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
        $request.nonce -cnotmatch '\A[0-9a-f]{32}\z' -or
        $request.source_commit -cnotmatch '\A[0-9a-f]{40}\z' -or
        $request.manifest_path -cnotmatch '\Ahostops/laptop-ops/manifests/[a-z][a-z0-9-]*\.json\z' -or
        $request.manifest_sha256 -cnotmatch '\A[0-9a-f]{64}\z' -or
        $request.requested_utc_epoch -isnot [ValueType]) {
        throw 'OWNER_OPS_REQUEST_INVALID'
    }
    $nonce = $request.nonce
    $sourceCommit = $request.source_commit
    $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$request.requested_utc_epoch
    if ($age -lt 0 -or $age -gt 180) { throw 'OWNER_OPS_REQUEST_STALE' }
    # Independently verify the trusted dispatch branch from the Owner session.
    # ProgramData write access alone must not authorize arbitrary source SHA.
    $refUrl = 'https://api.github.com/repos/trung-via/torrent-tv-vietsub/' +
        'git/ref/heads/hostops/owner-laptop-ops-dispatch'
    $ref = Invoke-RestMethod -Method Get -Uri $refUrl -Headers @{
        'User-Agent' = 'torrent-tv-owner-laptop-ops'
        Accept = 'application/vnd.github+json'
    } -ErrorAction Stop
    if ($ref.object.type -cne 'commit' -or $ref.object.sha -cne $sourceCommit) {
        throw 'OWNER_OPS_TRUSTED_SOURCE_BRANCH_DRIFT'
    }

    if (-not (Test-Path -LiteralPath $private -PathType Container)) {
        [IO.Directory]::CreateDirectory($private) | Out-Null
    }
    $run = Join-Path $private ('run-' + $nonce)
    [IO.Directory]::CreateDirectory($run) | Out-Null
    $runLog = Join-Path $run 'full-owner-output.log'
    $manifestPath = Join-Path $run 'manifest.json'
    DownloadPinned $request.manifest_path $request.manifest_sha256 $manifestPath 8192
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -AsHashtable
    if (@($manifest.Keys | Sort-Object) -join ',' -cne
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
        throw 'OWNER_OPS_MANIFEST_NOT_ROUTINE'
    }
    foreach ($argument in $manifest.arguments) {
        if ($argument -isnot [string] -or
            $argument -cnotmatch '\A-[A-Za-z][A-Za-z0-9]{0,39}\z') {
            throw 'OWNER_OPS_ARGUMENT_NOT_FIXED_SWITCH'
        }
    }
    $operation = [string]$manifest.operation
    $scriptFile = Join-Path $run 'operation.ps1'
    DownloadPinned $manifest.script_path $manifest.script_sha256 $scriptFile 1048576
    # All original stdout/stderr and PowerShell exception text remain private.
    # The operation itself is reviewed source, not text from the issue comment.
    $fixedArguments = @($manifest.arguments)
    & pwsh -NoLogo -NoProfile -NonInteractive -File $scriptFile @fixedArguments *> $runLog
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw ('OWNER_OPS_OPERATION_EXIT_' + $code) }
    WriteReceipt 'SUCCESS'
    Write-Output 'OWNER_OPS=SUCCESS_PRIVATE_FULL_LOG'
} catch {
    $failure = $_
    if ($null -ne $runLog) {
        @('OWNER_OPS_FAILURE=' + $failure.Exception.ToString(),
          'OWNER_OPS_STACK=' + $failure.ScriptStackTrace) |
            Add-Content -LiteralPath $runLog -Encoding utf8 -ErrorAction SilentlyContinue
        # A small source-owned failure phase can cross the public HostOps
        # receipt boundary. The unfiltered traceback and context stay local.
        if (Test-Path -LiteralPath $runLog -PathType Leaf) {
            $phase = @(Get-Content -LiteralPath $runLog -Tail 130 -ErrorAction SilentlyContinue |
                Where-Object {
                    $_ -cmatch '^OWNER_FULL_DIAG_FAILURE_PHASE=(REPLACE_FILES|OFFLINE_IMPORT|FRESH_OWNER_START|FULL_LOG_VERIFY)$'
                } | Select-Object -Last 1)
            if ($phase.Count -eq 1) { $diagnostic = [string]$phase[0] }
        }
    }
    WriteReceipt 'FAILED_NO_RETRY'
    Write-Output 'OWNER_OPS=FAILED_NO_RETRY_PRIVATE_FULL_LOG'
    throw 'OWNER_OPS_TASK_FAILED'
}
