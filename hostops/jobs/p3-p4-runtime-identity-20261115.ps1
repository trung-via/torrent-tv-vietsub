# Torrent TV: identify actual OwnerAgent process chain and optionally handshake the exact P3/P4 TLS listener.
# Read-only. Never reads or prints credentials, policy, media, IPs, ports or command lines.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:GITHUB_ACTIONS -cne 'true' -or
    [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne 'S-1-5-20') {
    throw 'TTV_IDENTITY_UNTRUSTED_RUNNER'
}
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$tasks = @(Get-ScheduledTask -TaskName $taskName -ErrorAction Stop)
if ($tasks.Count -ne 1 -or $tasks[0].TaskPath -cne [string][char]92) {
    throw 'TTV_IDENTITY_TASK_MISMATCH'
}
$task = $tasks[0]
$actions = @($task.Actions)
$taskLauncher = $actions.Count -eq 1 -and
    ([string]$actions[0].Arguments).IndexOf(
        'start-owner-session-agent.ps1',
        [StringComparison]::OrdinalIgnoreCase) -ge 0
Write-Host 'TTV_IDENTITY_MODE=READ_ONLY'
Write-Host ('TTV_IDENTITY_TASK_STATE=' + [string]$task.State)
Write-Host ('TTV_IDENTITY_TASK_ACTION_OWNER_LAUNCHER=' + $taskLauncher)

$processes = @(Get-CimInstance Win32_Process -ErrorAction Stop |
    Where-Object { [int]$_.SessionId -gt 0 -and
        $_.Name -in @('pwsh.exe','powershell.exe','py.exe','python.exe','pythonw.exe') })
$byId = @{}
foreach ($item in $processes) {
    $byId[[int]$item.ProcessId] = $item
}
function Has-Arg([object]$proc, [string]$needle) {
    if ($null -eq $proc -or [string]::IsNullOrEmpty([string]$proc.CommandLine)) { return $false }
    return ([string]$proc.CommandLine).IndexOf(
        $needle, [StringComparison]::OrdinalIgnoreCase) -ge 0
}
function Has-OwnerAncestor([object]$proc, [hashtable]$index) {
    if ($null -eq $proc) { return $false }
    $seen = @{}
    $parentId = [int]$proc.ParentProcessId
    for ($i=0; $i -lt 5; $i++) {
        if ($parentId -le 0 -or $seen.ContainsKey($parentId) -or -not $index.ContainsKey($parentId)) {
            return $false
        }
        $seen[$parentId] = $true
        $ancestor = $index[$parentId]
        if (Has-Arg $ancestor 'start-owner-session-agent.ps1') { return $true }
        $parentId = [int]$ancestor.ParentProcessId
    }
    return $false
}
$python = @($processes | Where-Object { $_.Name -in @('python.exe','pythonw.exe') })
$p3 = @($python | Where-Object { Has-Arg $_ 'owner_p3_p4_entrypoint.py' })
$legacy = @($python | Where-Object { Has-Arg $_ 'owner_session_bridge.py' })
$ownerP3 = @($p3 | Where-Object { Has-OwnerAncestor $_ $byId })
$visible = @($python | Where-Object { -not [string]::IsNullOrEmpty([string]$_.CommandLine) })
Write-Host ('TTV_IDENTITY_PYTHON_SESSION_COUNT=' + $python.Count)
Write-Host ('TTV_IDENTITY_PYTHON_COMMAND_VISIBLE_COUNT=' + $visible.Count)
Write-Host ('TTV_IDENTITY_P3_P4_ENTRYPOINT_COUNT=' + $p3.Count)
Write-Host ('TTV_IDENTITY_P3_P4_OWNER_CHAIN_COUNT=' + $ownerP3.Count)
Write-Host ('TTV_IDENTITY_LEGACY_OWNER_BRIDGE_COUNT=' + $legacy.Count)

$allListeningPids = @{}
foreach ($conn in @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue)) {
    $allListeningPids[[int]$conn.OwningProcess] = $true
}
$p3Listeners = @($p3 | Where-Object { $allListeningPids.ContainsKey([int]$_.ProcessId) })
$ownerP3Listeners = @($ownerP3 | Where-Object { $allListeningPids.ContainsKey([int]$_.ProcessId) })
$otherPythonListeners = @($python | Where-Object {
    $allListeningPids.ContainsKey([int]$_.ProcessId) -and
    -not (Has-Arg $_ 'owner_p3_p4_entrypoint.py')
})
Write-Host ('TTV_IDENTITY_P3_P4_LISTENER_PROCESS_COUNT=' + $p3Listeners.Count)
Write-Host ('TTV_IDENTITY_VERIFIED_OWNER_P3_P4_LISTENER_COUNT=' + $ownerP3Listeners.Count)
Write-Host ('TTV_IDENTITY_OTHER_PYTHON_LISTENER_COUNT=' + $otherPythonListeners.Count)

$tlsResult = 'NOT_RUN_NO_EXACT_OWNER_P3_P4_LISTENER'
if ($ownerP3Listeners.Count -eq 1) {
    $connections = @(Get-NetTCPConnection -State Listen -OwningProcess ([int]$ownerP3Listeners[0].ProcessId) -ErrorAction SilentlyContinue)
    if ($connections.Count -eq 1) {
        $boundAddress = [string]$connections[0].LocalAddress
        $boundPort = [int]$connections[0].LocalPort
        if ($boundAddress -ne '0.0.0.0' -and $boundAddress -ne '::' -and $boundAddress -ne '127.0.0.1' -and $boundAddress -ne '::1') {
            $tcp = New-Object Net.Sockets.TcpClient
            $tls = $null
            try {
                $pending = $tcp.BeginConnect($boundAddress, $boundPort, $null, $null)
                if (-not $pending.AsyncWaitHandle.WaitOne(2500)) {
                    $tlsResult = 'CONNECT_TIMEOUT'
                } else {
                    $tcp.EndConnect($pending)
                    # This is transport reachability only; callback does NOT establish a trusted TV certificate pin.
                    $callback = [Net.Security.RemoteCertificateValidationCallback]{ param($sender,$cert,$chain,$errors) return $true }
                    $tls = [Net.Security.SslStream]::new($tcp.GetStream(), $false, $callback)
                    $tls.ReadTimeout = 3000
                    $tls.WriteTimeout = 3000
                    $tls.AuthenticateAsClient('torrent-tv-local', $null,
                        [Security.Authentication.SslProtocols]::Tls12, $false)
                    $tlsResult = 'TLS_HANDSHAKE_PASS_UNPINNED'
                }
            } catch {
                $tlsResult = 'TLS_HANDSHAKE_OR_CONNECT_FAILED'
            } finally {
                if ($null -ne $tls) { $tls.Dispose() }
                $tcp.Dispose()
            }
        } else {
            $tlsResult = 'HOLD_NOT_PRIVATE_LAN_BIND'
        }
    } else {
        $tlsResult = 'HOLD_NOT_SINGLE_LISTENER'
    }
}
Write-Host ('TTV_IDENTITY_TLS_PROBE=' + $tlsResult)
Write-Host 'TTV_IDENTITY_HTTP_AUTH_ROUTE=NOT_TESTED'
Write-Host 'TTV_IDENTITY_TV_RENDER=NOT_TESTED'
Write-Host 'TTV_IDENTITY_PROVIDER=NOT_TESTED'
Write-Host 'TTV_IDENTITY_PROCESS_KILL=NO'
Write-Host 'TTV_IDENTITY_TASK_RESTART=NO'
Write-Host 'TTV_IDENTITY=READ_ONLY_COMPLETE'
