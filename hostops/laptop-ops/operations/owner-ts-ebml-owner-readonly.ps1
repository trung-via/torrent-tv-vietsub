# Owner-interactive, read-only TorrServer MKV English cue measurement.
# The helper already pins this script and verifies the trusted source SHA.
# Subtitle bytes, media identities and full output never enter CI logs.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$requestFile = Join-Path $spool 'Requests\request.json'
$request = Get-Content -LiteralPath $requestFile -Raw -Encoding UTF8 |
    ConvertFrom-Json
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    [string]$request.nonce -cnotmatch '^[0-9a-f]{32}$' -or
    [string]$request.source_commit -cnotmatch '^[0-9a-f]{40}$') {
    throw 'OWNER_EBML_REQUEST_INVALID'
}
$expectedSha256 = '3df265ac30a2297e7ed6f51aa2eaa861f3653ed769a4e8278fcbf880db80ce4b'
$pythonFile = Join-Path $PSScriptRoot 'owner-ts-ebml-range-readonly.py'
$uri = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' +
    $request.source_commit +
    '/hostops/laptop-ops/operations/owner-ts-ebml-range-readonly.py'
Invoke-WebRequest -Uri $uri -OutFile $pythonFile -ErrorAction Stop
$source = Get-Item -LiteralPath $pythonFile -Force
if ($source.Length -le 0 -or $source.Length -gt 65536 -or
    ($source.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
    (Get-FileHash -LiteralPath $pythonFile -Algorithm SHA256).Hash.ToLowerInvariant() -cne
        $expectedSha256) {
    throw 'OWNER_EBML_PYTHON_SOURCE_MISMATCH'
}
if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
    throw 'OWNER_EBML_PYTHON_MISSING'
}
$lines = @(& py -3 -I -B $pythonFile 2>$null)
$line = if ($lines.Count -eq 1) { [string]$lines[0] } else { '' }
if ($LASTEXITCODE -ne 0 -or $lines.Count -ne 1 -or
    $line -cnotmatch '^HOSTOPS_EBML_\{.{1,700}\}$') {
    throw 'OWNER_EBML_RESULT_INVALID'
}
$row = $line.Substring('HOSTOPS_EBML_'.Length) | ConvertFrom-Json
$fields = @('state','identity','en_ffp','en_mkv','cues_indexed',
            'cues_relative','cues_verified','bytes','requests','ms','first_ten_ms')
if ((@($row.PSObject.Properties.Name | Sort-Object) -join ',') -cne
    (@($fields | Sort-Object) -join ',') -or
    [string]$row.state -cnotmatch '^[A-Z0-9_]{3,50}$' -or
    $row.identity -cnotin @('UNVERIFIED','OWNER_EVENT_MATCH')) {
    throw 'OWNER_EBML_FIELDS_INVALID'
}
foreach ($field in @('en_ffp','en_mkv','cues_indexed','cues_relative',
                     'cues_verified','bytes','requests','ms','first_ten_ms')) {
    $max = switch ($field) {
        'en_ffp' { 128 }
        'en_mkv' { 128 }
        'cues_indexed' { 30000 }
        'cues_relative' { 30000 }
        'cues_verified' { 120 }
        'bytes' { 8388608 }
        'requests' { 300 }
        'ms' { 160000 }
        'first_ten_ms' { 160000 }
    }
    if ($row.$field -isnot [ValueType] -or
        [long]$row.$field -lt 0 -or [long]$row.$field -gt $max) {
        throw 'OWNER_EBML_COUNTER_INVALID'
    }
}
$record = [ordered]@{
    schema = 'TTV-OWNER-EBML-CUES-V1'
    nonce = [string]$request.nonce
}
foreach ($field in $fields) { $record[$field] = $row.$field }
$receiptDir = Join-Path $spool 'Receipts'
$destination = Join-Path $receiptDir ('owner-ebml-cues-' + $request.nonce + '.json')
$payload = [Text.UTF8Encoding]::new($false).GetBytes(($record | ConvertTo-Json -Compress))
if ($payload.Length -gt 512 -or (Test-Path -LiteralPath $destination)) {
    throw 'OWNER_EBML_RECEIPT_NOT_UNIQUE'
}
$temporary = $destination + '.tmp'
[IO.File]::WriteAllBytes($temporary,$payload)
[IO.File]::Move($temporary,$destination)
Write-Output 'OWNER_EBML_PRIVATE_RECEIPT_WRITTEN'
