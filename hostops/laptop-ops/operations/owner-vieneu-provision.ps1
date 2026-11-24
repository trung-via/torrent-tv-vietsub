# Isolated Owner benchmark environment. No installed Owner/TV changes.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = [string](Get-CimInstance Win32_ComputerSystem).UserName
if ([Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $id.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    -not $id.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'VIENEU_OWNER_CONTEXT_REQUIRED'
}
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$request = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $request.nonce -cnotmatch '^[0-9a-f]{32}$') { throw 'VIENEU_REQUEST_INVALID' }
$base = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\VieNeuBenchmark'
New-Item -ItemType Directory -Path $base -Force | Out-Null
$root = Join-Path $base ('sdk385-' + $request.nonce)
New-Item -ItemType Directory -Path $root -ErrorAction Stop | Out-Null
$rec = [ordered]@{schema='TTV-VIENEU-PROVISION-V1';nonce=[string]$request.nonce;status='NO_COMPATIBLE_PYTHON';python='NONE';sdk='NONE';onnx='NONE';elapsed_s=0;model_load='NOT_ATTEMPTED'}
$clock = [Diagnostics.Stopwatch]::StartNew()
function RunBounded([string]$exe,[string[]]$argv,[string]$tag,[int]$seconds) {
    $si = [Diagnostics.ProcessStartInfo]::new()
    $si.FileName = $exe
    $si.WorkingDirectory = $root
    $si.UseShellExecute = $false
    $si.RedirectStandardOutput = $true
    $si.RedirectStandardError = $true
    $si.Environment['PYTHONNOUSERSITE'] = '1'
    $si.Environment['PIP_CONFIG_FILE'] = 'NUL'
    $si.Environment['PIP_DISABLE_PIP_VERSION_CHECK'] = '1'
    $si.Environment['PIP_NO_INPUT'] = '1'
    $si.Environment.Remove('PYTHONPATH') | Out-Null
    foreach ($arg in $argv) { $si.ArgumentList.Add($arg) }
    $p = [Diagnostics.Process]::Start($si)
    try {
        $stdout = $p.StandardOutput.ReadToEndAsync()
        $stderr = $p.StandardError.ReadToEndAsync()
        $finished = $p.WaitForExit($seconds * 1000)
        if (-not $finished) { $p.Kill($true); $p.WaitForExit() }
        [IO.File]::WriteAllText((Join-Path $root ($tag+'.stdout.txt')), $stdout.GetAwaiter().GetResult())
        [IO.File]::WriteAllText((Join-Path $root ($tag+'.stderr.txt')), $stderr.GetAwaiter().GetResult())
        if (-not $finished) { return 124 }
        return [int]$p.ExitCode
    } finally { $p.Dispose() }
}
try {
    # Scheduled task PATH may omit the py launcher. Resolve the running
    # Owner's executable first, then known installed Python directories.
    $candidates = [Collections.Generic.List[string]]::new()
    $workers = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -match '^python(?:w)?\.exe$' -and
        [string]$_.CommandLine -match '(?i)owner_p3_p4_entrypoint\.py' -and
        [string]$_.CommandLine -match '(?i)TorrentTVVietsub'
    })
    foreach ($worker in $workers) {
        $sid = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
        if ($sid.ReturnValue -eq 0 -and $sid.Sid -ceq $id.User.Value -and $worker.ExecutablePath) {
            $candidates.Add([string]$worker.ExecutablePath)
        }
    }
    foreach ($tag in @('314','313','312','311')) {
        $candidates.Add((Join-Path $env:ProgramFiles ('Python'+$tag+'\python.exe')))
        $candidates.Add((Join-Path $env:LOCALAPPDATA ('Programs\Python\Python'+$tag+'\python.exe')))
    }
    $candidates = @($candidates | Select-Object -Unique | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if ($candidates.Count -gt 0) {
        $ordinal=0
        foreach ($python in $candidates) {
            $ordinal++

            if ($clock.Elapsed.TotalSeconds -gt 300) { $rec.status='TIME_BUDGET'; break }
            $tag = [string]$ordinal
            $probe = RunBounded $python @('-c','import sys; print(sys.version.split()[0])') ('probe'+$tag) 8
            if ($probe -ne 0) { continue }
            $rec.python = (Get-Content -LiteralPath (Join-Path $root ('probe'+$tag+'.stdout.txt')) -Raw).Trim()
            $venv = Join-Path $root ('py'+$tag)
            $rc = RunBounded $python @('-m','venv',$venv) ('venv'+$tag) 45
            if ($rc -ne 0) { $rec.status='VENV_FAILED'; continue }
            $exe = Join-Path $venv 'Scripts\python.exe'
            $pipArgs = @('-m','pip','--isolated','install','--only-binary=:all:','--index-url','https://pypi.org/simple','--timeout','15','--retries','1','--no-input','vieneu==3.8.5')
            # Resolve wheels without touching global Python or compiling source.
            $rc = RunBounded $exe ($pipArgs+@('--dry-run','--report',(Join-Path $root ('plan'+$tag+'.json')))) ('resolve'+$tag) 70
            if ($rc -ne 0) { $rec.status=if($rc -eq 124){'RESOLVE_TIMEOUT'}else{'WHEEL_RESOLUTION_FAILED'}; continue }
            $rec.python = (Get-Content -LiteralPath (Join-Path $root ('probe'+$tag+'.stdout.txt')) -Raw).Trim()
            $rc = RunBounded $exe $pipArgs ('install'+$tag) 150
            if ($rc -ne 0) { $rec.status=if($rc -eq 124){'INSTALL_TIMEOUT'}else{'INSTALL_FAILED'}; break }
            $rc = RunBounded $exe @('-c','from importlib.metadata import version; import numpy, soundfile, onnxruntime; from vieneu import Vieneu; print(version("vieneu")); print(version("onnxruntime")); assert "CPUExecutionProvider" in onnxruntime.get_available_providers()') ('import'+$tag) 25
            if ($rc -ne 0) { $rec.status='IMPORT_FAILED'; break }
            $versions = @(Get-Content -LiteralPath (Join-Path $root ('import'+$tag+'.stdout.txt')))
            $rec.sdk='3.8.5'
            $rec.onnx=($versions | Where-Object { $_ -match '^\d+\.\d+\.\d+(?:[A-Za-z0-9.+_-]*)$' } | Select-Object -Last 1)
            if (-not $rec.onnx) { $rec.onnx='UNKNOWN' }
            $rec.status='ENV_READY'
            & $exe -m pip freeze | Set-Content -LiteralPath (Join-Path $root 'requirements.lock.txt') -Encoding utf8
            # Store only a local pointer to the isolated verified environment.
            [IO.File]::WriteAllText((Join-Path $base 'sdk385-ready.txt'), $exe)
            break
        }
    }
} catch {
    $rec.status='PROVISION_EXCEPTION'
}
$rec.elapsed_s=[int]$clock.Elapsed.TotalSeconds
$out=Join-Path $spool ('Receipts\vieneu-provision-'+$request.nonce+'.json')
if(Test-Path -LiteralPath $out){throw 'VIENEU_RECEIPT_EXISTS'}
[IO.File]::WriteAllText($out+'.tmp',($rec|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
[IO.File]::Move($out+'.tmp',$out)
Write-Output 'VIENEU_ISOLATED_PROVISION_RECEIPT_RECORDED'
