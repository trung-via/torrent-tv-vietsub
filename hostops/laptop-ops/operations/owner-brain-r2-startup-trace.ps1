# Read-only Owner log classifier for the EXACT November 24 source-neutral restart and rollback attempt.
# Never copies exception messages, media, secrets or private paths into HostOps.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = [string](Get-CimInstance Win32_ComputerSystem).UserName
if ($env:GITHUB_ACTIONS -ceq 'true' -or
    -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $id.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($logged) -or
    -not $id.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'OWNER_STARTUP_DIAG_INTERACTIVE_OWNER_REQUIRED'
}
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$request = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw |
    ConvertFrom-Json
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    $request.nonce -cnotmatch '^[0-9a-f]{32}$') {
    throw 'OWNER_STARTUP_DIAG_REQUEST_INVALID'
}
$logFile = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge\diagnostics\owner-full.log'
$status = 'NO_MATCHING_STARTUP'
$stage = 'NONE'
$code = 'NONE'
$kind = 'NONE'
$bootCount = 0
$failureCount = 0
if (-not (Test-Path -LiteralPath $logFile -PathType Leaf)) {
    $status = 'LOG_MISSING'
} else {
    $item = Get-Item -LiteralPath $logFile -Force
    if ($item.Length -gt 20971520 -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        $status = 'LOG_NOT_READABLE'
    } else {
        # Exact source-neutral install run 45298606485: 2026-11-24 00:37-00:40 UTC.
        $start = [DateTimeOffset]::Parse('2026-11-24T00:37:00Z').ToUnixTimeSeconds()
        $end = [DateTimeOffset]::Parse('2026-11-24T00:40:00Z').ToUnixTimeSeconds()
        $inAttempt = $false
        $afterTrace = $false
        $traceLines = 0
        $lines = @(Get-Content -LiteralPath $logFile -Tail 4500 -ErrorAction Stop)
        foreach ($raw in $lines) {
            $line = [string]$raw
            if ($line -match '^OWNER_FULL_DIAGNOSTICS_STARTED pid=[0-9]+ epoch=([0-9]{10})$') {
                $epoch = [long]$Matches[1]
                $inAttempt = $epoch -ge $start -and $epoch -le $end
                $afterTrace = $false
                if ($inAttempt) {
                    $bootCount++
                    $status = 'BOOT_OBSERVED'
                }
                continue
            }
            if (-not $inAttempt) { continue }
            if ($line -match "^OWNER_FULL_TRACE '([A-Z][A-Z0-9_]{3,75})'") {
                $stage = [string]$Matches[1]
                if ($stage -in @('OWNER_P3_P4_STARTUP_FAILED',
                    'OWNER_PROVIDER_BOOTSTRAP_FAILED',
                    'OWNER_DIAGNOSTIC_TICK_FAILED')) {
                    $failureCount++
                    $status = 'FAILURE_TRACE_OBSERVED'
                    $afterTrace = $true
                    $traceLines = 0
                }
                continue
            }
            if (-not $afterTrace) { continue }
            $traceLines++
            if ($line -match '^([A-Za-z_][A-Za-z0-9_]{1,50}):\s*(.*)$') {
                $name = [string]$Matches[1]
                $value = [string]$Matches[2]
                $known = @('ValueError','RuntimeError','TypeError','OSError',
                    'AttributeError','ImportError','ModuleNotFoundError',
                    'OwnerRuntimeBlocked','OwnerEntrypointBlocked',
                    'KeyError','AssertionError','PermissionError')
                $kind = if ($name -in $known) { $name } else { 'OTHER' }
                if ($value -match '^([A-Z][A-Z0-9_]{4,90})(?:$|\s)') {
                    $code = [string]$Matches[1]
                } elseif ($name -ceq 'TypeError' -and
                    $value.Contains('unexpected keyword argument') -and
                    $value.Contains('first_window_cues')) {
                    $code = 'P2_FIRST_WINDOW_CUES_REJECTED'
                } else {
                    $code = 'UNCLASSIFIED_EXCEPTION'
                }
            }
            if ($traceLines -ge 35) { $afterTrace = $false }
        }
        if ($bootCount -gt 20 -or $failureCount -gt 20) {
            $status = 'BOUNDS_INVALID'
            $bootCount = 0
            $failureCount = 0
            $code = 'NONE'
            $kind = 'NONE'
            $stage = 'NONE'
        }
    }
}
# Source signature only: no imports, provider calls or file mutations.
$worker = 'MISSING'
$progressive = 'MISSING'
$base = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge\app\poc\p2-aisub'
foreach ($rule in @(
    @('automatic_lean120_worker.py','AutomaticLean120Worker','worker'),
    @('progressive_handoff.py','ProgressiveSubtitleSession','progressive'))) {
    $file = Join-Path $base $rule[0]
    $result = 'MISSING'
    if (Test-Path -LiteralPath $file -PathType Leaf) {
        $item = Get-Item -LiteralPath $file -Force
        if ($item.Length -le 0 -or $item.Length -gt 524288 -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $result = 'INVALID'
        } else {
            $body = [IO.File]::ReadAllText($file, [Text.UTF8Encoding]::new($false,$true))
            $className = [regex]::Escape([string]$rule[1])
            $pattern = '(?s)class\s+' + $className +
                '\b.{0,800}?def\s+__init__\(.{0,450}?first_window_cues'
            $result = if ([regex]::IsMatch($body,$pattern)) {
                'SUPPORTS_FIRST50'
            } else { 'NO_FIRST50_CONSTRUCTOR' }
        }
    }
    if ($rule[2] -ceq 'worker') { $worker = $result }
    else { $progressive = $result }
}
$record = [ordered]@{
    schema = 'TTV-OWNER-BRAIN-R2-STARTUP-DIAG-V1'
    nonce = [string]$request.nonce
    observed_utc_epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    status = $status
    stage = $stage
    kind = $kind
    code = $code
    boots = $bootCount
    failures = $failureCount
    worker = $worker
    progressive = $progressive
}
$out = Join-Path $spool ('Receipts\owner-brain-startup-' + $request.nonce + '.json')
if (Test-Path -LiteralPath $out) { throw 'OWNER_STARTUP_DIAG_RECEIPT_EXISTS' }
$content = [Text.UTF8Encoding]::new($false).GetBytes(
    ($record | ConvertTo-Json -Compress))
if ($content.Length -gt 768) { throw 'OWNER_STARTUP_DIAG_RECEIPT_TOO_LARGE' }
$tmp = $out + '.tmp'
[IO.File]::WriteAllBytes($tmp,$content)
[IO.File]::Move($tmp,$out)
Write-Output 'OWNER_BRAIN_R2_STARTUP_DIAG=PRIVATE_CLASSIFICATION_RECORDED'
