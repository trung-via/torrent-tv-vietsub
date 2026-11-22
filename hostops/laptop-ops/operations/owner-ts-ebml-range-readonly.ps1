# NETWORK_SERVICE read-only, limited-byte Matroska seek-index feasibility test.
# Does not launch the Owner task and does not create local media/cache files.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$reader = Join-Path $PSScriptRoot 'owner-ts-ebml-range-readonly.py'
$relative = 'hostops/laptop-ops/operations/owner-ts-ebml-range-readonly.py'
$expectedBlob = (& git rev-parse ('HEAD:' + $relative)).Trim()
$actualBlob = (& git hash-object --path=$relative $reader).Trim()
if (-not (Test-Path -LiteralPath $reader -PathType Leaf) -or
    $expectedBlob -cnotmatch '^[0-9a-f]{40}$' -or $expectedBlob -cne $actualBlob) {
    throw 'EBML_PROBE_SCRIPT_NOT_PINNED'
}
if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
    throw 'EBML_PROBE_PYTHON_MISSING'
}
$lines = @(& py -3 -I -B $reader 2>$null)
$line = if ($lines.Count -eq 1) { [string]$lines[0] } else { '' }
if ($LASTEXITCODE -ne 0 -or $lines.Count -ne 1 -or
    $line -cnotmatch '^HOSTOPS_EBML_\{.{1,700}\}$') {
    throw 'EBML_PROBE_RESULT_INVALID'
}
$row = $line.Substring('HOSTOPS_EBML_'.Length) | ConvertFrom-Json
$fields = @('state','identity','en_ffp','en_mkv','cues_indexed',
            'cues_relative','cues_verified','bytes','requests','ms','first_ten_ms')
if ((@($row.PSObject.Properties.Name | Sort-Object) -join ',') -cne
    (@($fields | Sort-Object) -join ',') -or
    [string]$row.state -cnotmatch '^[A-Z0-9_]{3,50}$' -or
    $row.identity -cnotin @('UNVERIFIED','UNIQUE_EN_CANDIDATE')) {
    throw 'EBML_PROBE_FIELDS_INVALID'
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
        throw 'EBML_PROBE_COUNTER_INVALID'
    }
}
foreach ($field in $fields) {
    Write-Output ('HOSTOPS_EBML_' + $field.ToUpperInvariant() + '=' + $row.$field)
}
Write-Output 'HOSTOPS_EBML_READONLY_PASS'
