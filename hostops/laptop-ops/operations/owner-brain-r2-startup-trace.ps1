# Read-only Owner log classifier for the EXACT R2 restart attempt.
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
        # Exactly the second failed R2 installation: 2026-11-23 07:42-07:46 UTC.
        $start = [DateTimeOffset]::Parse('2026-11-23T07:42:00Z').ToUnixTimeSeconds()
        $end = [DateTimeOffset]::Parse('2026-11-23T07:46:00Z').ToUnixTimeSeconds()
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
