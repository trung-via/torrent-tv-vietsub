# Read-only diagnostic for the one AGY website SRT smoke test.
# No provider call, download, TV/OwnerAgent action, or private text disclosure.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$previousCommit = 'be49e34490a653f5b5ed185e95a9213d73c912e5'
$expectedHash = 'fe793b7267170a016c01dcd597604afd9ce99414af374a95748f245acc0e7159'
$subtitleName = 'The.Odyssey.2026.1080p.AMZN.WEB-DL.DDP5.1.H.264-KyoGo.srt'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$inbox = Join-Path $spool 'Requests\request.json'
$history = Join-Path $spool 'History'
$outbox = Join-Path $spool 'Receipts'
$private = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\LaptopHostOps'
$runRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\AGYWebsiteSmoke'

$request = Get-Content -LiteralPath $inbox -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    $request.nonce -cnotmatch '\A[0-9a-f]{32}\z') {
    throw 'AGY_DIAG_CURRENT_REQUEST_INVALID'
}
$nonce = [string]$request.nonce
$prior = $null
if (Test-Path -LiteralPath $history -PathType Container) {
    $receipts = @(Get-ChildItem -LiteralPath $history -Filter 'receipt-*.json' -File |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 100)
    foreach ($item in $receipts) {
        if ($item.Length -le 0 -or $item.Length -gt 512 -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        try {
            $row = Get-Content -LiteralPath $item.FullName -Raw -Encoding UTF8 |
                ConvertFrom-Json -AsHashtable
        } catch { continue }
        if ($row.schema -ceq 'TTV-LAPTOP-HOSTOPS-RECEIPT-V1' -and
            $row.source_commit -ceq $previousCommit -and
            $row.nonce -cmatch '\A[0-9a-f]{32}\z') {
            $prior = $row
            break
        }
    }
}

$priorState = 'NOT_FOUND'
$logState = 'NOT_FOUND'
$errorCode = 'UNDETERMINED'
$outputState = 'NOT_FOUND'
$srtState = 'NOT_FOUND'
$bytes = 0
$cues = 0
$hashMatch = 'UNKNOWN'

if ($null -ne $prior) {
    $priorState = if ($prior.result -ceq 'FAILED_NO_RETRY') { 'FAILED_NO_RETRY' } else { 'OTHER' }
    $log = Join-Path $private ('run-' + $prior.nonce + '\full-owner-output.log')
    if (Test-Path -LiteralPath $log -PathType Leaf) {
        $item = Get-Item -LiteralPath $log -Force
        if ($item.Length -gt 0 -and $item.Length -le 1048576 -and
            -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $logState = 'FOUND'
            $tail = (Get-Content -LiteralPath $log -Tail 160 -ErrorAction Stop) -join "`n"
            $knownCodes = @(
                'AGY_WEBSITE_SMOKE_CLI_NOT_AVAILABLE',
                'AGY_WEBSITE_SMOKE_NOT_STARTED',
                'AGY_WEBSITE_SMOKE_TIMEOUT',
                'AGY_WEBSITE_SMOKE_COMMAND_FAILED',
                'AGY_WEBSITE_SMOKE_SRT_NOT_SAVED',
                'AGY_WEBSITE_SMOKE_SRT_SIZE_INVALID',
                'AGY_WEBSITE_SMOKE_NOT_SRT',
                'AGY_WEBSITE_SMOKE_DIFFERENT_BYTES'
            )
            foreach ($code in $knownCodes) {
                if ($tail.Contains($code)) { $errorCode = $code; break }
            }
            if ($errorCode -ceq 'UNDETERMINED' -and
                $tail.Contains('OWNER_OPS_OPERATION_EXIT_')) {
                $errorCode = 'OWNER_OPS_OPERATION_EXIT'
            }
            if ($errorCode -ceq 'UNDETERMINED' -and
                $tail.Contains('OWNER_OPS_PINNED_SOURCE_')) {
                $errorCode = 'OWNER_OPS_PINNED_SOURCE_FAILURE'
            }
        }
    }
}

if ($null -ne $prior -and (Test-Path -LiteralPath $runRoot -PathType Container)) {
    $receiptTime = [DateTimeOffset]::FromUnixTimeSeconds([long]$prior.utc_epoch)
    $candidates = @(Get-ChildItem -LiteralPath $runRoot -Directory |
        Where-Object {
            -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
            [Math]::Abs(($_.CreationTimeUtc - $receiptTime.UtcDateTime).TotalSeconds) -le 3600
        } | Sort-Object CreationTimeUtc -Descending)
    if ($candidates.Count -ge 1) {
        $runDir = $candidates[0].FullName
        $agyOutput = Join-Path $runDir 'agy-private-output.txt'
        if (Test-Path -LiteralPath $agyOutput -PathType Leaf) {
            $outputItem = Get-Item -LiteralPath $agyOutput -Force
            $outputState = if ($outputItem.Length -gt 0) { 'PRESENT' } else { 'EMPTY' }
        }
        $srt = Join-Path $runDir $subtitleName
        if (Test-Path -LiteralPath $srt -PathType Leaf) {
            $info = Get-Item -LiteralPath $srt -Force
            if ($info.Length -gt 0 -and $info.Length -le 2000000 -and
                -not ($info.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $bytes = [int]$info.Length
                $text = [IO.File]::ReadAllText($srt)
                $cues = [regex]::Matches($text,
                    '(?m)^\d{2}:\d{2}:\d{2},\d{3} --> \d{2}:\d{2}:\d{2},\d{3}').Count
                $actualHash = (Get-FileHash -LiteralPath $srt -Algorithm SHA256).Hash.ToLowerInvariant()
                $hashMatch = if ($actualHash -ceq $expectedHash) { 'YES' } else { 'NO' }
                $srtState = if ($cues -ge 1000 -and $hashMatch -ceq 'YES') {
                    'EXACT_VALID_SRT'
                } elseif ($cues -ge 1000) { 'VALID_DIFFERENT_HASH' } else { 'INVALID_SRT' }
            } else { $srtState = 'INVALID_SIZE_OR_LINK' }
        }
    }
}

$summary = [ordered]@{
    schema = 'TTV-AGY-WEBSITE-DIAG-V1'
    nonce = $nonce
    prior = $priorState
    owner_log = $logState
    error = $errorCode
    agy_output = $outputState
    srt = $srtState
    bytes = $bytes
    cues = $cues
    sha_match = $hashMatch
}
$encoded = [Text.UTF8Encoding]::new($false).GetBytes(($summary | ConvertTo-Json -Compress))
if ($encoded.Length -gt 1024) { throw 'AGY_DIAG_SUMMARY_TOO_LARGE' }
$destination = Join-Path $outbox ('agy-website-diag-' + $nonce + '.json')
$temp = Join-Path $outbox ('agy-website-diag-' + $nonce + '.tmp')
[IO.File]::WriteAllBytes($temp, $encoded)
[IO.File]::Move($temp, $destination)
Write-Output 'AGY_WEBSITE_DIAG=PRIVATE_EVIDENCE_CLASSIFIED'
