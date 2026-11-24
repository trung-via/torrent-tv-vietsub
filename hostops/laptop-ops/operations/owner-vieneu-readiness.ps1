# Read-only package metadata in the actual interactive Owner context.
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
$record = [ordered]@{
    schema = 'TTV-VIENEU-OWNER-READINESS-V1'
    nonce = [string]$request.nonce
    observed_utc_epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    owner_task = 'UNKNOWN'
    python_scope = 'NONE'
    python = 'UNKNOWN'
    vieneu = 'UNKNOWN'
    onnxruntime = 'UNKNOWN'
    numpy = 'UNKNOWN'
    soundfile = 'UNKNOWN'
    installed_voice_adapter = 'MISSING'
    free_ram_mib = 0
}
$task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'
$record.owner_task = [string]$task.State
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$adapter = Join-Path $root 'app\poc\p2-aisub\voiceover_vieneu.py'
if (Test-Path -LiteralPath $adapter -PathType Leaf) { $record.installed_voice_adapter = 'PRESENT' }
$pythonExe = $null
$workers = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match '^python(?:w)?\.exe$' -and
    [string]$_.CommandLine -match '(?i)owner_p3_p4_entrypoint\.py' -and
    [string]$_.CommandLine -match '(?i)TorrentTVVietsub'
})
foreach ($worker in $workers) {
    $ownerSid = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
    if ($ownerSid.ReturnValue -eq 0 -and $ownerSid.Sid -ceq $id.User.Value -and
        $worker.ExecutablePath -and (Test-Path -LiteralPath $worker.ExecutablePath -PathType Leaf)) {
        $pythonExe = [string]$worker.ExecutablePath
        $record.python_scope = 'RUNNING_OWNER_EXECUTABLE'
        break
    }
}
if (-not $pythonExe) {
    $py = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($py) {
        $exe = (& $py.Source -3 -c 'import sys; print(sys.executable)' 2>$null | Select-Object -Last 1)
        if ($LASTEXITCODE -eq 0 -and $exe -and (Test-Path -LiteralPath $exe -PathType Leaf)) {
            $pythonExe = [string]$exe
            $record.python_scope = 'OWNER_PY_LAUNCHER_FALLBACK'
        }
    }
}
if ($pythonExe) {
    $code = @'
import json, sys
from importlib import metadata
def version(name):
    try:
        return metadata.version(name)
    except metadata.PackageNotFoundError:
        return "MISSING"
print(json.dumps(dict(python=".".join(map(str, sys.version_info[:3])),
    vieneu=version("vieneu"), onnxruntime=version("onnxruntime"),
    numpy=version("numpy"), soundfile=version("soundfile"))))
'@
    $raw = & $pythonExe -c $code 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'VIENEU_METADATA_PROBE_FAILED' }
    $data = ($raw | Out-String) | ConvertFrom-Json
    foreach ($name in @('python','vieneu','onnxruntime','numpy','soundfile')) {
        $value = [string]$data.$name
        if ($value -cnotmatch '^[A-Za-z0-9][A-Za-z0-9.+_-]{0,47}$') { throw 'VIENEU_METADATA_INVALID' }
        $record[$name] = $value
    }
}
$record.free_ram_mib = [int][Math]::Floor((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024)
$out = Join-Path $spool ('Receipts\vieneu-readiness-' + $request.nonce + '.json')
if (Test-Path -LiteralPath $out) { throw 'VIENEU_RECEIPT_EXISTS' }
$bytes = [Text.UTF8Encoding]::new($false).GetBytes(($record | ConvertTo-Json -Compress))
[IO.File]::WriteAllBytes($out + '.tmp',$bytes)
[IO.File]::Move($out + '.tmp',$out)
Write-Output 'VIENEU_OWNER_READINESS_RECORDED_NO_MODEL_LOAD'
