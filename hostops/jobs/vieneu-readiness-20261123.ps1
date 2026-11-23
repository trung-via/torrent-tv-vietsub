# Read-only VieNeu/ONNX prerequisite snapshot, never initialize a model.
# Trusted existing Torrent TV HostOps runner, not a proof of Owner user environment.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows') {
    throw 'VIENEU_READINESS_RUNNER_IDENTITY_INVALID'
}
Write-Output 'VIENEU_PROBE_SCOPE=RUNNER_SERVICE_READ_ONLY'
Write-Output 'VIENEU_PROBE_MODEL_DOWNLOAD=NO'
Write-Output 'VIENEU_PROBE_OWNER_PROFILE=NOT_ACCESSED'
$pythonExe = 'C:\Program Files\Python314\python.exe'
if (-not (Test-Path -LiteralPath $pythonExe -PathType Leaf)) {
    Write-Output 'VIENEU_SYSTEM_PYTHON=MISSING'
    exit 0
}
$version = (& $pythonExe --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'VIENEU_PYTHON_VERSION_FAILED' }
Write-Output "VIENEU_SYSTEM_PYTHON=$version"
$probe = @'
from importlib import metadata, util
import json
import platform
packages = (
  ("vieneu", "vieneu"),
  ("onnxruntime", "onnxruntime"),
  ("numpy", "numpy"),
  ("soundfile", "soundfile"),
  ("huggingface_hub", "huggingface_hub"),
  ("vieneu_utils", "vieneu-utils"),
)
for module, distribution in packages:
    present = util.find_spec(module) is not None
    try:
        version = metadata.version(distribution)
    except metadata.PackageNotFoundError:
        version = "NOT_INSTALLED"
    print("VIENEU_MODULE_{}={}".format(module.upper(), "PRESENT" if present else "MISSING"))
    print("VIENEU_PACKAGE_{}={}".format(module.upper(), version))
if util.find_spec("onnxruntime") is not None:
    import onnxruntime as ort
    print("VIENEU_ONNX_PROVIDERS={}".format(",".join(ort.get_available_providers())))
else:
    print("VIENEU_ONNX_PROVIDERS=NOT_INSTALLED")
print("VIENEU_ARCH={}".format(platform.machine()))
'@
$probeOutput = & $pythonExe -c $probe 2>&1
if ($LASTEXITCODE -ne 0) {
    $safe = ($probeOutput | Out-String)
    if ($safe -match 'Traceback') {
        Write-Output 'VIENEU_PROBE_PYTHON_IMPORT_FAILED'
    } else {
        Write-Output 'VIENEU_PROBE_PYTHON_COMMAND_FAILED'
    }
    exit 1
}
$probeOutput | ForEach-Object { Write-Output $_ }
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop
    $freeGb = [Math]::Round(([double]$os.FreePhysicalMemory / 1MB), 2)
    $totalGb = [Math]::Round(([double]$os.TotalVisibleMemorySize / 1MB), 2)
    $logical = @($cpu | Measure-Object -Property NumberOfLogicalProcessors -Sum)[0].Sum
    Write-Output "VIENEU_HOST_RAM_TOTAL_GB=$totalGb"
    Write-Output "VIENEU_HOST_RAM_FREE_GB=$freeGb"
    Write-Output "VIENEU_HOST_LOGICAL_CPUS=$logical"
} catch {
    Write-Output 'VIENEU_HOST_RESOURCES=NOT_OBSERVED'
}
try {
    $task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -ErrorAction Stop
    Write-Output "VIENEU_OWNER_TASK_STATE=$($task.State)"
} catch {
    Write-Output 'VIENEU_OWNER_TASK_STATE=UNKNOWN'
}
Write-Output 'VIENEU_READINESS_PROBE_COMPLETE_NOT_OWNER_TTS_BENCHMARK'
