# Read-only Python interpreter inventory for Torrent TV G2 build runner.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$found = New-Object System.Collections.Generic.List[string]

function Check-Python([string]$exe) {
    if ([string]::IsNullOrWhiteSpace($exe) -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) { return }
    $ver = & $exe --version 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -and $ver -match 'Python 3\.') {
        $found.Add($exe)
        Write-Host ('PYTHON_PROBE_FOUND=' + $exe)
        Write-Host ('PYTHON_PROBE_VERSION=' + $ver.Trim())
    }
}

foreach ($name in @('python.exe','py.exe')) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host ('PYTHON_PROBE_COMMAND=' + $name + ':' + $cmd.Source)
        if ($name -eq 'python.exe') { Check-Python $cmd.Source }
        else {
            & $cmd.Source -0p 2>&1 | ForEach-Object { Write-Host ('PYTHON_LAUNCHER=' + $_) }
            Write-Host ('PYTHON_LAUNCHER_LAST_EXIT=' + $LASTEXITCODE)
        }
    }
}
$roots = @(
    'C:\Python314',
    'C:\Python313',
    'C:\Python312',
    'C:\Python311',
    'C:\Program Files\Python314',
    'C:\Program Files\Python313',
    'C:\Program Files\Python312',
    'C:\Program Files\Python311',
    'C:\TOOL\Python',
    (Join-Path $env:LOCALAPPDATA 'Programs\Python')
)
foreach ($root in $roots) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
    Check-Python (Join-Path $root 'python.exe')
    foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        Check-Python (Join-Path $d.FullName 'python.exe')
    }
}
if ($found.Count -eq 0) {
    Write-Host 'PYTHON_PROBE_NO_INTERPRETER_FOUND_IN_BOUNDED_PATHS'
}
Write-Host 'PYTHON_PROBE_READ_ONLY_COMPLETE'
