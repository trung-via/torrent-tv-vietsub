# Owner-session, reusable exact-commit STAGE ONLY. This fixed Scheduled Task
# never changes installed Owner/P2 files, stops a task or invokes a provider.
# The HostOps runner can create a bounded ProgramData request and start this
# task, but cannot read the Owner's private staging directory.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$requestFile = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\ReleaseRequests\request.json'
$receiptFile = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\ReleaseReceipts\stage.json'
$nonce = 'NONE'
$commit = 'NONE'
function EmitReceipt([string]$result) {
    $record = [ordered]@{
        schema = 'TTV-OWNER-RELEASE-STAGE-RECEIPT-V1'
        source_commit = $commit
        nonce = $nonce
        result = $result
        snapshot_utc_epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    }
    $temp = $receiptFile + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temp, ($record | ConvertTo-Json -Compress),
        [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temp, $receiptFile, $true)
    Write-Output ('OWNER_RELEASE_STAGE=' + $result)
}
function CheckFile([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band
            [IO.FileAttributes]::ReparsePoint)) {
        throw 'RELEASE_STAGE_FILE_UNTRUSTED'
    }
}
function CheckDirectory([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Container) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band
            [IO.FileAttributes]::ReparsePoint)) {
        throw 'RELEASE_STAGE_DIRECTORY_UNTRUSTED'
    }
}
function ExactSHA([string]$path) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function OneDownload([string]$base, [string]$path, [string]$dest,
                     [string]$sha, [long]$limit) {
    if (-not [regex]::IsMatch($sha, '\A[0-9a-f]{64}\z')) {
        throw 'RELEASE_STAGE_SHA_INVALID'
    }
    Invoke-WebRequest -Uri ($base + '/' + $path) -OutFile $dest -ErrorAction Stop
    CheckFile $dest
    $item = Get-Item -LiteralPath $dest
    if ($item.Length -le 0 -or $item.Length -gt $limit -or
        (ExactSHA $dest) -cne $sha) {
        throw 'RELEASE_STAGE_DOWNLOAD_HASH_OR_SIZE_MISMATCH'
    }
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $interactive = (Get-CimInstance Win32_ComputerSystem).UserName
    if ($env:GITHUB_ACTIONS -ceq 'true' -or
        -not [Environment]::UserInteractive -or
        [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
        $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
        [string]::IsNullOrWhiteSpace($interactive) -or
        -not $identity.Name.Equals($interactive,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'RELEASE_STAGE_INTERACTIVE_OWNER_REQUIRED'
    }
    $ownerTask = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'
    $taskSid = [string]$ownerTask.Principal.UserId
    if ($taskSid -notmatch '^S-\d+(?:-\d+){2,}$') {
        $taskSid = ([Security.Principal.NTAccount]::new($taskSid).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    }
    if ($taskSid -cne $identity.User.Value) {
        throw 'RELEASE_STAGE_OWNER_TASK_IDENTITY_CHANGED'
    }
    CheckFile $requestFile
    if ((Get-Item -LiteralPath $requestFile).Length -gt 512) {
        throw 'RELEASE_STAGE_REQUEST_TOO_LARGE'
    }
    $request = Get-Content -LiteralPath $requestFile -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    if (@($request.Keys | Sort-Object) -join ',' -cne
        'manifest_path,manifest_sha256,nonce,requested_utc_epoch,schema,source_commit' -or
        $request.schema -cne 'TTV-OWNER-RELEASE-STAGE-REQUEST-V1' -or
        $request.source_commit -cnotmatch '\A[0-9a-f]{40}\z' -or
        $request.nonce -cnotmatch '\A[0-9a-f]{32}\z' -or
        $request.manifest_path -cnotmatch '\Ahostops/releases/owner-[a-z0-9-]+\.json\z' -or
        $request.manifest_sha256 -cnotmatch '\A[0-9a-f]{64}\z' -or
        $request.requested_utc_epoch -isnot [ValueType]) {
        throw 'RELEASE_STAGE_REQUEST_INVALID'
    }
    $nonce = $request.nonce
    $commit = $request.source_commit
    $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$request.requested_utc_epoch
    if ($age -lt 0 -or $age -gt 180) {
        throw 'RELEASE_STAGE_REQUEST_STALE'
    }

    $root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
    $releases = Join-Path $root 'staged-releases'
    CheckDirectory $root
    if (-not (Test-Path -LiteralPath $releases)) {
        New-Item -ItemType Directory -Path $releases -ErrorAction Stop | Out-Null
    }
    CheckDirectory $releases
    $base = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' + $commit
    $scratch = Join-Path $releases ('.prepare-' + $nonce)
    New-Item -ItemType Directory -Path $scratch -ErrorAction Stop | Out-Null
    $manifestTemp = Join-Path $scratch 'manifest.json'
    OneDownload $base $request.manifest_path $manifestTemp $request.manifest_sha256 8192
    $manifest = Get-Content -LiteralPath $manifestTemp -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    if (@($manifest.Keys | Sort-Object) -join ',' -cne
        'files,mode,release_id,schema,source_tree' -or
        $manifest.schema -cne 'TTV-OWNER-RELEASE-STAGE-V1' -or
        $manifest.mode -cne 'STAGE_ONLY' -or
        $manifest.release_id -cnotmatch '\A[a-z0-9-]{3,50}\z' -or
        $manifest.source_tree -cnotmatch '\A[0-9a-f]{40}\z' -or
        $manifest.files -isnot [array] -or
        $manifest.files.Count -lt 1 -or $manifest.files.Count -gt 32) {
        throw 'RELEASE_STAGE_MANIFEST_INVALID'
    }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $staged = Join-Path $releases ('owner-' + $manifest.release_id + '-' + $commit.Substring(0,12))
    if (-not (Test-Path -LiteralPath $staged)) {
        New-Item -ItemType Directory -Path $staged -ErrorAction Stop | Out-Null
    }
    CheckDirectory $staged
    foreach ($file in $manifest.files) {
        if ($file -isnot [System.Collections.IDictionary] -or
            @($file.Keys | Sort-Object) -join ',' -cne 'path,sha256' -or
            $file.path -cnotmatch '\Apoc/(p2-aisub|p2-sub-discovery)/(?!test_)[a-z0-9_]+\.py\z' -or
            $file.sha256 -cnotmatch '\A[0-9a-f]{64}\z' -or
            -not $seen.Add([string]$file.path)) {
            throw 'RELEASE_STAGE_MANIFEST_FILE_INVALID'
        }
        $destination = Join-Path $staged ($file.path.Replace('/', '\'))
        $parent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
        }
        CheckDirectory $parent
        if (Test-Path -LiteralPath $destination) {
            CheckFile $destination
            if ((ExactSHA $destination) -cne $file.sha256) {
                throw 'RELEASE_STAGE_EXISTING_CONTENT_DRIFT'
            }
            continue
        }
        $temp = Join-Path $scratch ([Guid]::NewGuid().ToString('N') + '.py')
        OneDownload $base $file.path $temp $file.sha256 1048576
        [IO.File]::Move($temp, $destination)
    }
    EmitReceipt 'STAGED_VERIFIED_INSTALLED_UNCHANGED'
} catch {
    # Only fixed status and opaque nonce/commit cross the HostOps boundary.
    EmitReceipt 'HOLD_NO_INSTALLED_CHANGE'
    throw
}
