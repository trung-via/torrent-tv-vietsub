# Classify the last Owner-accepted P3 request from its private flight recorder.
# No raw title, media key, URL, subtitle text or provider response leaves Owner.
# No playback, provider, P2 work, restart or retry is initiated.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$request = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw |
    ConvertFrom-Json
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    [string]$request.nonce -cnotmatch '^[0-9a-f]{32}$') {
    throw 'OWNER_SOURCE_TRACE_REQUEST_INVALID'
}
$owner = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$healthPath = Join-Path $owner 'agent-health.json'
$logPath = Join-Path $owner 'diagnostics\owner-full.log'
$scope = 'NOT_OBSERVED'
$titleSource = 'NOT_OBSERVED'
$route = 'NOT_OBSERVED'
$search = 'NOT_OBSERVED'
$download = 'NO'
$cached = 'NO'
$enSource = 'NOT_OBSERVED'
$outcome = 'NOT_OBSERVED'
$p4Reject = 'NOT_OBSERVED'
$safeP4Reasons = @(
    'UNCLASSIFIED', 'P4_ACTIVATE_SCHEMA_INVALID', 'P4_ACTIVATE_AUTH_INVALID',
    'P4_ACTIVATE_REPLAY', 'P4_TOO_MANY_SESSIONS',
    'P4_ASSUMED_SOURCE_MISSING', 'P4_PROGRESSIVE_FEED_BIND_FAILED',
    'P4_READY_FEED_PUBLISH_FAILED', 'P4_TRANSLATION_START_FAILED',
    'P3_READY_NO_CURRENT_ACCEPTED_SOURCE',
    'P3_READY_CURRENT_MEDIA_OR_CONSENT_CHANGED',
    'P3_READY_PRIVATE_SOURCE_NOT_READY',
    'P4_ROLLING_CURRENT_TV_UNAVAILABLE', 'P4_ROLLING_TV_SESSION_CHANGED',
    'P4_ROLLING_CHECKPOINT_INVALID', 'P4_ROLLING_CHECKPOINT_NOT_VERIFIED',
    'P4_ROLLING_CHECKPOINT_HASH_CHANGED', 'P4_ROLLING_CHECKPOINT_GAP',
    'P4_ROLLING_SOURCE_NOT_VERIFIED', 'P4_ROLLING_SOURCE_RECEIPT_INVALID',
    'P4_ROLLING_SOURCE_INDEX_INVALID', 'P4_ROLLING_ABANDONED_JOB_HOLD',
    'P4_ROLLING_SOURCE_CHANGED', 'P4_ROLLING_REVISION_IDENTITY_INVALID'
)

if ((Test-Path -LiteralPath $healthPath -PathType Leaf) -and
    (Test-Path -LiteralPath $logPath -PathType Leaf)) {
    $healthItem = Get-Item -LiteralPath $healthPath -Force
    $logItem = Get-Item -LiteralPath $logPath -Force
    if ($healthItem.Length -gt 0 -and $healthItem.Length -le 512 -and
        $logItem.Length -gt 0 -and
        -not ($healthItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
        -not ($logItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        $health = Get-Content -LiteralPath $healthPath -Raw | ConvertFrom-Json
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -
            [long]$health.observed_utc_epoch
        if ($health.schema -ceq 'TTV-OWNER-AGENT-HEALTH-V1' -and
            $health.state -ceq 'READY' -and [long]$health.pid -gt 0 -and
            $age -ge 0 -and $age -le 30) {
            # Read no more than 256 KiB from the tail of a private log.
            $stream = [IO.File]::Open($logPath, [IO.FileMode]::Open,
                [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try {
                $from = [Math]::Max(0L, $stream.Length - 262144L)
                [void]$stream.Seek($from, [IO.SeekOrigin]::Begin)
                $buffer = [byte[]]::new([int]($stream.Length - $from))
                $read = 0
                while ($read -lt $buffer.Length) {
                    $amount = $stream.Read($buffer, $read, $buffer.Length - $read)
                    if ($amount -le 0) { break }
                    $read += $amount
                }
            } finally { $stream.Dispose() }
            $all = [Text.Encoding]::UTF8.GetString($buffer, 0, $read)
            if ($from -gt 0) {
                $firstBreak = $all.IndexOf("`n", [StringComparison]::Ordinal)
                if ($firstBreak -ge 0) { $all = $all.Substring($firstBreak + 1) }
                else { $all = '' }
            }
            $lines = @($all -split "`r?`n")
            $start = -1
            $livePid = 0L
            for ($i=0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -cmatch '^OWNER_FULL_DIAGNOSTICS_STARTED pid=([0-9]{1,10}) epoch=[0-9]{1,12}$') {
                    $start = $i
                    $livePid = [long]$Matches[1]
                }
            }
            if ($start -ge 0 -and $livePid -eq [long]$health.pid) {
                $lastRequest = -1
                for ($i=$start+1; $i -lt $lines.Count; $i++) {
                    if ($lines[$i].Contains("OWNER_FULL_TRACE 'P3_SELECTION_ACCEPTED'") -and
                        $lines[$i].Contains("'status': 'DISPATCH'")) {
                        $lastRequest = $i
                    }
                }
                if ($lastRequest -ge 0) {
                    $scope = 'CURRENT_OWNER_REQUEST'
                    for ($i=$lastRequest+1; $i -lt $lines.Count; $i++) {
                        $line = [string]$lines[$i]
                        if ($line -cmatch '^AUTO_PROVIDER_TITLE_SOURCE=(TORRENT_ALIAS|VIDEO_FILENAME)$') {
                            $titleSource = $Matches[1]
                        } elseif ($line -cmatch '^AUTO_PROVIDER_SEARCH=NO_TITLE$') {
                            $search = 'NO_TITLE'
                        } elseif ($line -cmatch '^AUTO_SOURCE_ROUTE=(VI_READY|EN_TRANSLATE|REVIEW_REQUIRED|NO_MATCH)$') {
                            $route = $Matches[1]
                            $search = 'ROUTE_EVALUATED'
                        } elseif ($line -cmatch '^AUTO_PROVIDER_DOWNLOAD=ATTEMPTED_ONCE$') {
                            $download = 'YES'
                        } elseif ($line -cmatch '^AUTO_SUBTITLE_CACHED=YES$') {
                            $cached = 'YES'
                        } elseif ($line -cmatch '^AUTO_EN_SOURCE=(LOCAL_DIRECT|TORRENT_SIDECAR)$') {
                            $enSource = $Matches[1]
                            $cached = 'YES'
                        } elseif ($line -cmatch '^AUTO_EN_CACHED_REUSED=YES$') {
                            $enSource = 'CACHED'
                            $cached = 'YES'
                        } elseif ($line.Contains("OWNER_FULL_TRACE 'P2_EVENT_FINISHED'") -and
                                  $line -cmatch "'result': '(VI_READY|VIETSUB_READY|REVIEW_REQUIRED)'") {
                            $outcome = $Matches[1]
                        } elseif ($line.Contains("OWNER_FULL_TRACE 'P4_DELIVERY_STATUS'") -and
                                  $line -cmatch "'code': 'P4_ACTIVATE_REJECTED_([A-Z0-9_]{3,100})'") {
                            $p4Reject = if ($Matches[1] -cin $safeP4Reasons) {
                                $Matches[1]
                            } else { 'OTHER' }
                        }
                    }
                }
            } else { $scope = 'SESSION_NOT_IN_TAIL' }
        } else { $scope = 'OWNER_HEALTH_UNVERIFIED' }
    }
}
$current = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw |
    ConvertFrom-Json
if ($current.nonce -cne $request.nonce) { throw 'OWNER_SOURCE_TRACE_REQUEST_CHANGED' }
$data = [ordered]@{
    schema = 'TTV-OWNER-SOURCE-TRACE-V1'; nonce = $request.nonce
    scope = $scope; title_source = $titleSource; search = $search
    route = $route; download = $download; cached = $cached
    en_source = $enSource; p2_outcome = $outcome; p4_reject = $p4Reject
}
$payload = $data | ConvertTo-Json -Compress
if ([Text.Encoding]::UTF8.GetByteCount($payload) -gt 512) {
    throw 'OWNER_SOURCE_TRACE_SUMMARY_TOO_LONG'
}
$target = Join-Path $spool 'Receipts\source-trace.json'
$temp = $target + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
[IO.File]::WriteAllText($temp, $payload, [Text.UTF8Encoding]::new($false))
[IO.File]::Move($temp, $target, $true)
Write-Output 'OWNER_SOURCE_TRACE=PRIVATE_CLASSIFICATION_COMPLETE'
