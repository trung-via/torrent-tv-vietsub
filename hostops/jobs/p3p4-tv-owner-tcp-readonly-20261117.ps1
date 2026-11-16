# Read-only correlation: exact authorized Redmi -> Owner task's private TLS port.
# Reports only coarse presence; no IP/port/serial/PID/path/commandline or payloads.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:GITHUB_ACTIONS -cne 'true' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne 'S-1-5-20') {
    throw 'TTV_TVPC_PROBE_UNTRUSTED_CONTEXT'
}

function IsPrivateIPv4([string]$value) {
    $parsed = $null
    if (-not [Net.IPAddress]::TryParse($value, [ref]$parsed)) { return $false }
    $bytes = $parsed.GetAddressBytes()
    return $bytes.Length -eq 4 -and (
        $bytes[0] -eq 10 -or
        ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
        ($bytes[0] -eq 192 -and $bytes[1] -eq 168))
}

$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    throw 'TTV_TVPC_PROBE_PINNED_ADB_MISSING'
}

if (@(Get-NetTCPConnection -LocalPort 5037 -State Listen -ErrorAction SilentlyContinue).Count -lt 1) {
    Write-Host 'TTV_TVPC_ADB=NOT_RUNNING'
    exit 0
}

$devices = @(& $adb devices 2>&1 | ForEach-Object { $_.ToString() } |
    Where-Object { $_ -match '^\S+\s+device\s*$' })
if ($devices.Count -ne 1) {
    Write-Host 'TTV_TVPC_ADB=NOT_EXACT_ONE_AUTHORIZED'
    exit 0
}
$deviceId = ($devices[0] -split '\s+')[0]
if ($deviceId -notmatch '^([0-9]{1,3}(?:\.[0-9]{1,3}){3}):[0-9]{2,5}$' -or
    -not (IsPrivateIPv4 $Matches[1])) {
    Write-Host 'TTV_TVPC_ADB=NO_VERIFIED_TCP_IP'
    exit 0
}
$tvIp = $Matches[1]
$identity = @(& $adb -s $deviceId shell getprop ro.product.model 2>&1 |
    ForEach-Object { $_.ToString() })
if ($LASTEXITCODE -ne 0 -or $identity.Count -ne 1 -or
    ([string]$identity[0]).Trim() -cne 'MiTV-ASTR0') {
    Write-Host 'TTV_TVPC_ADB=WRONG_OR_UNKNOWN_DEVICE'
    exit 0
}
Write-Host 'TTV_TVPC_ADB=EXACT_REDMi_TCP'

$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$task = @(Get-ScheduledTask -TaskName $taskName -ErrorAction Stop)
if ($task.Count -ne 1 -or [string]$task[0].State -cne 'Running' -or
    @($task[0].Actions).Count -ne 1 -or
    ([string]$task[0].Actions[0].Arguments).IndexOf(
        'start-owner-session-agent.ps1', [StringComparison]::OrdinalIgnoreCase) -lt 0) {
    Write-Host 'TTV_TVPC_OWNER=NOT_RUNNING_OR_IDENTITY_MISMATCH'
    exit 0
}

# Trust only the exact Scheduled Task COM instance as process root, not generic Python.
$service = New-Object -ComObject 'Schedule.Service'
$service.Connect()
$registered = $service.GetFolder('\').GetTask($taskName)
$instances = $registered.GetInstances(0)
$all = @(Get-CimInstance Win32_Process -ErrorAction Stop)
$byId = @{}
foreach ($p in $all) { $byId[[int]$p.ProcessId] = $p }
$rootPids = @{}
for ($i = 1; $i -le [int]$instances.Count; $i++) {
    $pidCandidate = [int]$instances.Item($i).EnginePID
    if ($byId.ContainsKey($pidCandidate) -and
        $byId[$pidCandidate].Name -in @('pwsh.exe', 'powershell.exe')) {
        $rootPids[$pidCandidate] = $true
    }
}
if ($rootPids.Count -ne 1) {
    Write-Host 'TTV_TVPC_OWNER=NO_EXACT_TASK_ROOT'
    exit 0
}

function IsOwnerChild([object]$candidate, [hashtable]$processes, [hashtable]$roots) {
    $seen = @{}
    $parent = [int]$candidate.ParentProcessId
    for ($n = 0; $n -lt 7; $n++) {
        if ($roots.ContainsKey($parent)) { return $true }
        if ($parent -le 0 -or $seen.ContainsKey($parent) -or
            -not $processes.ContainsKey($parent)) { return $false }
        $seen[$parent] = $true
        $parent = [int]$processes[$parent].ParentProcessId
    }
    return $false
}
$ownerChildren = @($all | Where-Object {
    $_.Name -in @('python.exe', 'pythonw.exe') -and
    [int]$_.SessionId -gt 0 -and
    (IsOwnerChild $_ $byId $rootPids)
})
if ($ownerChildren.Count -ne 1) {
    Write-Host 'TTV_TVPC_OWNER=NO_EXACT_PYTHON_CHILD'
    exit 0
}
$listeners = @(Get-NetTCPConnection -State Listen -OwningProcess ([int]$ownerChildren[0].ProcessId) -ErrorAction SilentlyContinue)
if ($listeners.Count -ne 1 -or
    -not (IsPrivateIPv4 ([string]$listeners[0].LocalAddress))) {
    Write-Host 'TTV_TVPC_OWNER=NO_EXACT_PRIVATE_TLS_LISTENER'
    exit 0
}
Write-Host 'TTV_TVPC_OWNER=EXACT_PRIVATE_LISTENER'

# Include TIME_WAIT (connections may close too fast for a single snapshot).
# Zero observations is inconclusive, not proof that the TV never attempted.
$port = [int]$listeners[0].LocalPort
$observed = $false
$watch = [Diagnostics.Stopwatch]::StartNew()
while ($watch.Elapsed.TotalSeconds -lt 20) {
    $matches = @(Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue |
        Where-Object {
            $_.RemoteAddress -ceq $tvIp -or
            $_.RemoteAddress -ceq ('::ffff:' + $tvIp)
        })
    if ($matches.Count -gt 0) {
        $observed = $true
        break
    }
    Start-Sleep -Milliseconds 200
}
Write-Host ('TTV_TVPC_TCP=' + $(if ($observed) { 'OBSERVED_TV_TO_OWNER' } else { 'NOT_OBSERVED_IN_20S_INCONCLUSIVE' }))
Write-Host 'TTV_TVPC_AUTH_P3=NOT_MEASURED'
Write-Host 'TTV_TVPC_P4_REVISION=NOT_MEASURED'
Write-Host 'TTV_TVPC_PROBE=READ_ONLY_COMPLETE_NO_PRIVATE_VALUES'
