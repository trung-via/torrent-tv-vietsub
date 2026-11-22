# Read a bounded, already Owner-sanitized source-selection classification.
# No access to Owner profile; no file edits, P2 replay or provider calls.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $sid -cne 'S-1-5-20') {
    throw 'OWNER_TRACE_TRUSTED_RUNNER_REQUIRED'
}
$root = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$files = @{
    request = Join-Path $root 'Requests\request.json'
    receipt = Join-Path $root 'Receipts\receipt.json'
    trace = Join-Path $root 'Receipts\source-trace.json'
}
foreach ($p in $files.Values) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        Write-Output 'OWNER_TRACE_READOUT=MISSING'
        return
    }
    $i = Get-Item -LiteralPath $p -Force
    if ($i.Length -lt 1 -or $i.Length -gt 2048 -or
        ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'OWNER_TRACE_READOUT_FILE_UNTRUSTED'
    }
}
$request = Get-Content -LiteralPath $files.request -Raw | ConvertFrom-Json
$receipt = Get-Content -LiteralPath $files.receipt -Raw | ConvertFrom-Json
$trace = Get-Content -LiteralPath $files.trace -Raw | ConvertFrom-Json
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$age = $now - [long]$receipt.utc_epoch
if ($request.nonce -cnotmatch '^[a-f0-9]{32}$' -or
    $trace.schema -cne 'TTV-OWNER-SOURCE-TRACE-V1' -or
    $receipt.schema -cne 'TTV-LAPTOP-HOSTOPS-RECEIPT-V1' -or
    $receipt.operation -cne 'owner-p2-source-trace-readonly' -or
    $receipt.result -cne 'SUCCESS' -or
    $request.nonce -cne $receipt.nonce -or
    $request.nonce -cne $trace.nonce -or $age -lt 0 -or $age -gt 600) {
    Write-Output 'OWNER_TRACE_READOUT=NOT_FRESH_SOURCE_TRACE'
    return
}
$allowed = [ordered]@{
    scope = @('NOT_OBSERVED','CURRENT_OWNER_REQUEST','SESSION_NOT_IN_TAIL','OWNER_HEALTH_UNVERIFIED')
    title_source = @('NOT_OBSERVED','TORRENT_ALIAS','VIDEO_FILENAME')
    search = @('NOT_OBSERVED','NO_TITLE','ROUTE_EVALUATED')
    route = @('NOT_OBSERVED','VI_READY','EN_TRANSLATE','REVIEW_REQUIRED','NO_MATCH')
    download = @('YES','NO')
    cached = @('YES','NO')
    en_source = @('NOT_OBSERVED','LOCAL_DIRECT','TORRENT_SIDECAR','CACHED')
    p2_outcome = @('NOT_OBSERVED','VI_READY','VIETSUB_READY','REVIEW_REQUIRED')
}
foreach ($name in $allowed.Keys) {
    $value = [string]$trace.$name
    if ($value -cnotin $allowed[$name]) { throw ('OWNER_TRACE_FIELD_INVALID_' + $name) }
}
if ([string]$trace.p4_reject -cnotmatch '^[A-Z0-9_]{2,100}$') {
    throw 'OWNER_TRACE_P4_CLASS_INVALID'
}
Write-Output 'OWNER_TRACE_READOUT=FRESH_SANITIZED_CLASSIFICATION'
Write-Output ('OWNER_TRACE_AGE_SECONDS=' + $age)
foreach ($name in $allowed.Keys) {
    Write-Output ('OWNER_TRACE_' + $name.ToUpperInvariant() + '=' + [string]$trace.$name)
}
Write-Output ('OWNER_TRACE_P4_REJECT=' + [string]$trace.p4_reject)
Write-Output 'OWNER_TRACE_MEDIA_AND_SECRETS=NOT_ACCESSED'
