# Read-only late result of ONE source-pinned Owner install after dispatcher timeout.
# Do not trigger/stop a task, move receipts, edit ACLs, access Owner-private logs,
# mutate Python modules, or repeat the installation.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $sid -cne 'S-1-5-20') {
    throw 'OWNER_LATE_RECEIPT_RUNNER_IDENTITY_REQUIRED'
}
$source = '9753445bb4bedd1b6662c1cc7e6656813f0f3075'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$requestFile = Join-Path $spool 'Requests\request.json'
$receiptFile = Join-Path $spool 'Receipts\receipt.json'
function ReadRecord([string]$path,[long]$limit) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $item = Get-Item -LiteralPath $path -Force
    if ($item.Length -le 0 -or $item.Length -gt $limit -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'OWNER_LATE_RECEIPT_INVALID_FILE'
    }
    return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}
$request = ReadRecord $requestFile 1024
$receipt = ReadRecord $receiptFile 512
$task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-Laptop-HostOps' -TaskPath '\'
$owner = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'
$taskState = [string]$task.State
$ownerState = [string]$owner.State
if ($taskState -cnotin @('Ready','Running','Disabled') -or
    $ownerState -cnotin @('Ready','Running','Disabled')) {
    throw 'OWNER_LATE_RECEIPT_UNEXPECTED_TASK_STATE'
}
Write-Output ('OWNER_LATE_HOSTOPS_TASK=' + $taskState.ToUpperInvariant())
Write-Output ('OWNER_LATE_OWNER_TASK=' + $ownerState.ToUpperInvariant())
if ($null -eq $request -or
    $request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    $request.source_commit -cne $source -or
    $request.nonce -cnotmatch '^[0-9a-f]{32}$') {
    Write-Output 'OWNER_LATE_RESULT=REQUEST_NOT_EXACT_NO_REPLAY'
    return
}
$age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$request.requested_utc_epoch
if ($age -lt 0) { throw 'OWNER_LATE_RECEIPT_CLOCK_UNCERTAIN' }
Write-Output ('OWNER_LATE_REQUEST_AGE_CLASS=' + $(if ($age -le 300) { 'LE_5MIN' }
    elseif ($age -le 900) { 'LE_15MIN' } else { 'GT_15MIN' }))
if ($null -eq $receipt -or
    $receipt.schema -cne 'TTV-LAPTOP-HOSTOPS-RECEIPT-V1' -or
    $receipt.nonce -cne $request.nonce -or
    $receipt.source_commit -cne $source) {
    Write-Output 'OWNER_LATE_RESULT=NO_MATCHING_RECEIPT_UNKNOWN_EFFECT'
    return
}
if ($receipt.operation -cne 'owner-title-alias-178-install') {
    throw 'OWNER_LATE_RECEIPT_OPERATION_MISMATCH'
}
if ($receipt.result -ceq 'SUCCESS') {
    Write-Output 'OWNER_LATE_RESULT=INSTALL_OWNER_TASK_SUCCESS'
} elseif ($receipt.result -ceq 'FAILED_NO_RETRY') {
    Write-Output 'OWNER_LATE_RESULT=INSTALL_OWNER_TASK_FAILED_NO_RETRY'
} else {
    Write-Output 'OWNER_LATE_RESULT=NONTERMINAL_UNVERIFIED'
}
Write-Output 'OWNER_LATE_EFFECT=READ_ONLY'
