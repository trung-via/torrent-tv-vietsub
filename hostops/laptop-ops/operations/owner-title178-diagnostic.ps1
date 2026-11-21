# Owner-private, read-only classification of ONE failed source-pinned install.
# Publish only a bounded code to the HostOps receipt folder; no private log text.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = '1d51dc5879e06d0321d7bff008807b08b02788ee'
$op = 'owner-title-alias-178-install'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$history = Join-Path $spool 'History'
$request = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    $request.nonce -cnotmatch '^[0-9a-f]{32}$') { throw 'TITLE178_DIAG_CURRENT_REQUEST_INVALID' }
$match = @()
foreach ($path in @(Get-ChildItem -LiteralPath $history -File -Filter 'receipt-*.json')) {
    if ($path.Length -le 0 -or $path.Length -gt 512 -or
        ($path.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
    try {
        $receipt = Get-Content -LiteralPath $path.FullName -Raw | ConvertFrom-Json
        if ($receipt.schema -ceq 'TTV-LAPTOP-HOSTOPS-RECEIPT-V1' -and
            $receipt.source_commit -ceq $source -and
            $receipt.operation -ceq $op -and
            $receipt.result -ceq 'FAILED_NO_RETRY' -and
            $receipt.nonce -cmatch '^[0-9a-f]{32}$') { $match += $receipt }
    } catch { continue }
}
if ($match.Count -ne 1) { throw 'TITLE178_DIAG_FAILED_RECEIPT_NOT_UNIQUE' }
$nonce = [string]$match[0].nonce
$log = Join-Path $env:LOCALAPPDATA ('TorrentTVVietsub\LaptopHostOps\run-' + $nonce + '\full-owner-output.log')
if (-not (Test-Path -LiteralPath $log -PathType Leaf)) { throw 'TITLE178_DIAG_LOG_MISSING' }
$file = Get-Item -LiteralPath $log -Force
if ($file.Length -le 0 -or $file.Length -gt 1048576 -or
    ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'TITLE178_DIAG_LOG_UNTRUSTED' }
$lines = @(Get-Content -LiteralPath $log -Tail 220)
$codes = @($lines | ForEach-Object {
    if ($_ -cmatch '^OWNER_TITLE178=(HOLD_[A-Z0-9_]+|STAGED_SIX_EXACT_HASHES|ALREADY_INSTALLED_NO_RESTART|OFFLINE_IMPORT_PASS|INSTALLED_SIX_HASHES_OWNER_READY|ROLLBACK_ATTEMPTED|ROLLBACK_UNCERTAIN_OWNER_ATTENTION_REQUIRED|OLD_OWNER_RESTORED)$') {
        $Matches[1]
    }
})
$code = 'NO_INSTALL_MARKER'
if ($codes.Count -gt 0) {
    $code = [string]$codes[-1]
    $hold = @($codes | Where-Object { $_ -clike 'HOLD_*' })
    if ($hold.Count -gt 0) { $code = [string]$hold[-1] }
}
if ($code -ceq 'NO_INSTALL_MARKER' -and
    @($lines | Where-Object { $_ -match 'ParserError|Missing.*terminator|Unexpected token' }).Count -gt 0) {
    $code = 'SCRIPT_PARSE_ERROR'
}
if ($code -ceq 'NO_INSTALL_MARKER' -and
    @($lines | Where-Object { $_ -match 'Invoke-WebRequest|HTTP [45][0-9][0-9]|Unable to connect' }).Count -gt 0) {
    $code = 'SOURCE_DOWNLOAD_FAILED'
}
if ($code -cnotmatch '^[A-Z0-9_]{3,80}$') { throw 'TITLE178_DIAG_CODE_INVALID' }
$current = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($current.nonce -cne $request.nonce) { throw 'TITLE178_DIAG_REQUEST_CHANGED' }
$result = Join-Path $spool 'Receipts\title178-diag.json'
$payload = @{ schema='TTV-OWNER-TITLE178-DIAG-V1'; nonce=$request.nonce; code=$code } | ConvertTo-Json -Compress
if ([Text.Encoding]::UTF8.GetByteCount($payload) -gt 256) { throw 'TITLE178_DIAG_PAYLOAD_LONG' }
$temp = $result + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
[IO.File]::WriteAllText($temp,$payload,[Text.UTF8Encoding]::new($false))
[IO.File]::Move($temp,$result,$true)
Write-Output 'TITLE178_DIAG=PRIVATE_CLASSIFICATION_COMPLETED'
