# Owner-interactive, one-shot retirement of the isolated TorrServer GStreamer test.
# Never touches the primary TorrServer, a system-wide installation or other apps.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$requestFile = Join-Path $spool 'Requests\request.json'
$requestItem = Get-Item -LiteralPath $requestFile -Force -ErrorAction Stop
if ($requestItem.Length -le 0 -or $requestItem.Length -gt 1024 -or
    ($requestItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'GST_RETIRE_REQUEST_UNTRUSTED'
}
$request = Get-Content -LiteralPath $requestFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    [string]$request.nonce -cnotmatch '^[0-9a-f]{32}$') {
    throw 'GST_RETIRE_REQUEST_INVALID'
}

$ownerRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
if (-not (Test-Path -LiteralPath $ownerRoot -PathType Container) -or
    ((Get-Item -LiteralPath $ownerRoot -Force).Attributes -band
        [IO.FileAttributes]::ReparsePoint)) {
    throw 'GST_RETIRE_ROOT_UNTRUSTED'
}
$binaryName = 'TorrServer-gst-windows-amd64.exe'
$binarySha = 'fe8542cf3ebbad4c8a612fda285c795a02abd7e4383b26df63e538d1c89d9ab8'
$processes = @(Get-CimInstance Win32_Process -Filter "Name = '$binaryName'" -ErrorAction Stop)
$trialDirs = @(Get-ChildItem -LiteralPath $ownerRoot -Directory -Force -ErrorAction Stop |
    Where-Object { $_.Name -cmatch '^gsttrial-[a-z0-9_]{6,12}$' })
if ($trialDirs.Count -gt 12 -or $processes.Count -gt 12) {
    throw 'GST_RETIRE_SCOPE_TOO_BROAD'
}
$validated = @{}
foreach ($dir in $trialDirs) {
    if ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'GST_RETIRE_TRIAL_REPARSE'
    }
    $entries = @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop)
    if ($entries.Count -gt 400 -or
        @($entries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) {
        throw 'GST_RETIRE_TRIAL_CONTENT_UNTRUSTED'
    }
    $total = [long]0
    foreach ($entry in $entries) {
        if (-not $entry.PSIsContainer) { $total += [long]$entry.Length }
    }
    if ($total -gt 268435456) { throw 'GST_RETIRE_TRIAL_TOO_LARGE' }
    $exe = Join-Path $dir.FullName $binaryName
    if (Test-Path -LiteralPath $exe -PathType Leaf) {
        $item = Get-Item -LiteralPath $exe -Force
        if ($item.Length -ne 99109888 -or
            (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -cne $binarySha) {
            throw 'GST_RETIRE_BINARY_NOT_PINNED'
        }
    } elseif ($entries.Count -gt 0) {
        throw 'GST_RETIRE_NONEMPTY_TRIAL_WITHOUT_PINNED_BINARY'
    }
    $validated[$dir.FullName.ToLowerInvariant()] = $dir.FullName
}

$matched = @()
$unrelated = 0
$ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
foreach ($process in $processes) {
    $exePath = [string]$process.ExecutablePath
    $parentDir = if ($exePath) { [IO.Path]::GetDirectoryName($exePath) } else { '' }
    $command = [string]$process.CommandLine
    $key = $parentDir.ToLowerInvariant()
    $identity = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid -ErrorAction Stop
    if ($validated.ContainsKey($key) -and
        $exePath.Equals((Join-Path $validated[$key] $binaryName),
            [StringComparison]::OrdinalIgnoreCase) -and
        $identity.ReturnValue -eq 0 -and $identity.Sid -ceq $ownerSid -and
        $command.Contains('--port 18191') -and
        $command.Contains('--ip 127.0.0.1') -and
        $command.Contains('--torrentaddr 127.0.0.1:0') -and
        $command.Contains((Join-Path $validated[$key] 'config'))) {
        $matched += $process
    } else {
        $unrelated++
    }
}

# Each process is matched to the SHA-pinned, Owner-owned, loopback-only trial
# before stopping; no kill by process name, port or directory glob.
foreach ($process in $matched) {
    Stop-Process -Id $process.ProcessId -ErrorAction Stop
    $deadline = [DateTime]::UtcNow.AddSeconds(12)
    while ([DateTime]::UtcNow -lt $deadline -and
        (Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue)) {
        Start-Sleep -Milliseconds 250
    }
    if (Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue) {
        throw 'GST_RETIRE_PROCESS_NOT_EXITED'
    }
}
$survivors = @(Get-CimInstance Win32_Process -Filter "Name = '$binaryName'" -ErrorAction Stop |
    Where-Object { $_.ExecutablePath -and
        $validated.ContainsKey(([IO.Path]::GetDirectoryName([string]$_.ExecutablePath)).ToLowerInvariant()) })
if ($survivors.Count -ne 0) { throw 'GST_RETIRE_MATCHED_PROCESS_STILL_RUNNING' }

$removed = 0
foreach ($dir in $trialDirs) {
    # Explicit, prevalidated Owner-private trial folders only. Never wildcard.
    Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
    if (Test-Path -LiteralPath $dir.FullName) { throw 'GST_RETIRE_TRIAL_REMOVE_FAILED' }
    $removed++
}

$receipt = Join-Path $spool 'Receipts\owner-ts-gst-trial.json'
$history = Join-Path $spool 'History'
if (Test-Path -LiteralPath $receipt -PathType Leaf) {
    $item = Get-Item -LiteralPath $receipt -Force
    if ($item.Length -le 0 -or $item.Length -gt 1024 -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'GST_RETIRE_TRIAL_RECEIPT_UNTRUSTED'
    }
    $archived = Join-Path $history ('gst-trial-summary-' + $request.nonce + '.json')
    if (Test-Path -LiteralPath $archived) { throw 'GST_RETIRE_SUMMARY_ALREADY_ARCHIVED' }
    Copy-Item -LiteralPath $receipt -Destination $archived -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $receipt -Algorithm SHA256).Hash -cne
        (Get-FileHash -LiteralPath $archived -Algorithm SHA256).Hash) {
        throw 'GST_RETIRE_SUMMARY_ARCHIVE_MISMATCH'
    }
    Remove-Item -LiteralPath $receipt -Force -ErrorAction Stop
}

$summary = [ordered]@{
    schema='TTV-OWNER-GST-RETIRE-V1';nonce=$request.nonce
    removed_dirs=$removed;stopped_processes=$matched.Count
    unrelated_processes=$unrelated;status='RETIRED_PROJECT_TRIAL_ONLY'
}
$outPath = Join-Path $spool ('Receipts\owner-gst-retire-' + $request.nonce + '.json')
$bytes = [Text.UTF8Encoding]::new($false).GetBytes(($summary | ConvertTo-Json -Compress))
if ($bytes.Length -gt 512 -or (Test-Path -LiteralPath $outPath)) {
    throw 'GST_RETIRE_SUMMARY_INVALID'
}
[IO.File]::WriteAllBytes($outPath, $bytes)
Write-Output 'OWNER_TS_GST_RETIRE=PROJECT_TRIAL_CLEANED'
