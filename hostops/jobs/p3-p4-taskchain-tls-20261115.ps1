# Read-only owner-task process ancestry and P3/P4 TLS transport probe.
# No source/video/policy/secret reads; no raw command lines, IPs, ports or device identifiers in logs.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:GITHUB_ACTIONS -cne 'true' -or
    [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne 'S-1-5-20') {
    throw 'TTV_CHAIN_UNTRUSTED_RUNNER'
}
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$tasks = @(Get-ScheduledTask -TaskName $taskName -ErrorAction Stop)
if ($tasks.Count -ne 1 -or $tasks[0].TaskPath -cne [string][char]92) {
    throw 'TTV_CHAIN_TASK_IDENTITY_MISMATCH'
}
$task = $tasks[0]
$taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction Stop
$actions = @($task.Actions)
$launcherValid = $actions.Count -eq 1 -and
    ([string]$actions[0].Arguments).IndexOf(
        'start-owner-session-agent.ps1', [StringComparison]::OrdinalIgnoreCase) -ge 0
Write-Host 'TTV_CHAIN_MODE=READ_ONLY'
Write-Host ('TTV_CHAIN_TASK_STATE=' + [string]$task.State)
Write-Host ('TTV_CHAIN_TASK_LAUNCHER_MATCH=' + $launcherValid)
if ([string]$task.State -cne 'Running' -or -not $launcherValid) {
    Write-Host 'TTV_CHAIN_HOLD=TASK_NOT_RUNNING_OR_ACTION_INVALID'
    Write-Host 'TTV_CHAIN_TLS=NOT_RUN'
    Write-Host 'TTV_CHAIN=READ_ONLY_COMPLETE'
    exit 0
}

$all = @(Get-CimInstance Win32_Process -ErrorAction Stop)
$byId = @{}
foreach ($proc in $all) { $byId[[int]$proc.ProcessId] = $proc }
$rootCandidates = @{}
$comStatus = 'UNAVAILABLE'
try {
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $registered = $service.GetFolder([string][char]92).GetTask($taskName)
    $instances = $registered.GetInstances(0)
    $comStatus = 'NO_INSTANCE'
    for ($i=1; $i -le [int]$instances.Count; $i++) {
        $instance = $instances.Item($i)
        $engineId = [int]$instance.EnginePID
        if ($byId.ContainsKey($engineId)) {
            $candidate = $byId[$engineId]
            if ($candidate.Name -in @('pwsh.exe','powershell.exe')) {
                $rootCandidates[$engineId] = 'COM_ENGINE'
                $comStatus = 'ACTION_ROOT_CANDIDATE'
            } else {
                $comStatus = 'ENGINE_NOT_PWSH'
            }
        }
    }
} catch {
    $comStatus = 'ACCESS_OR_API_UNAVAILABLE'
}
Write-Host ('TTV_CHAIN_COM_INSTANCE=' + $comStatus)

$eventStatus = 'UNAVAILABLE'
try {
    $filter = @{
        LogName = 'Microsoft-Windows-TaskScheduler/Operational'
        Id = 129
        StartTime = (Get-Date).AddHours(-8)
    }
    $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents 160 -ErrorAction Stop)
    $eventStatus = 'NO_EXACT_ACTION_PID'
    foreach ($evt in $events) {
        $eventXml = [xml]$evt.ToXml()
        $fields = @{}
        foreach ($datum in @($eventXml.Event.EventData.Data)) {
            $fieldName = [string]$datum.Name
            if ($fieldName) { $fields[$fieldName] = [string]$datum.'#text' }
        }
        $taskPath = '\'+$taskName
        if ($fields.ContainsKey('TaskName') -and
            [string]$fields['TaskName'] -ceq $taskPath) {
            foreach ($key in @('ProcessID','ProcessId','EnginePID')) {
                if ($fields.ContainsKey($key)) {
                    $candidateId = 0
                    if ([int]::TryParse([string]$fields[$key],[ref]$candidateId) -and
                        $byId.ContainsKey($candidateId)) {
                        $candidate = $byId[$candidateId]
                        if ($candidate.Name -in @('pwsh.exe','powershell.exe')) {
                            $rootCandidates[$candidateId] = 'TASK_EVENT'
                            $eventStatus = 'ACTION_ROOT_CANDIDATE'
                        }
                    }
                }
            }
        }
    }
} catch {
    $eventStatus = 'ACCESS_OR_LOG_UNAVAILABLE'
}
Write-Host ('TTV_CHAIN_TASK_EVENT=' + $eventStatus)

# Only a directly identified task action PID may anchor descendants. Do not
# trust a generic shared scheduler host PID or user-session Python PID.
$trustedRoots = @{}
foreach ($entry in @($rootCandidates.Keys)) {
    $root = $byId[[int]$entry]
    $started = [datetime]$root.CreationDate
    $last = [datetime]$taskInfo.LastRunTime
    if ([int]$root.SessionId -gt 0 -and
        $started -ge $last.AddMinutes(-3) -and
        $started -le $last.AddMinutes(3)) {
        $trustedRoots[[int]$entry] = $true
    }
}
Write-Host ('TTV_CHAIN_TRUSTED_ACTION_ROOT_COUNT=' + $trustedRoots.Count)

function DescendsFromRoot([object]$candidate, [hashtable]$allById, [hashtable]$roots) {
    $seen = @{}
    $parentId = [int]$candidate.ParentProcessId
    for ($i=0; $i -lt 7; $i++) {
        if ($roots.ContainsKey($parentId)) { return $true }
        if ($parentId -le 0 -or $seen.ContainsKey($parentId) -or
            -not $allById.ContainsKey($parentId)) { return $false }
        $seen[$parentId] = $true
        $parentId = [int]$allById[$parentId].ParentProcessId
    }
    return $false
}
$python = @($all | Where-Object {
    $_.Name -in @('python.exe','pythonw.exe') -and [int]$_.SessionId -gt 0
})
$children = @($python | Where-Object { DescendsFromRoot $_ $byId $trustedRoots })
$listenerChildren = @()
foreach ($candidate in $children) {
    $listening = @(Get-NetTCPConnection -State Listen -OwningProcess ([int]$candidate.ProcessId) -ErrorAction SilentlyContinue)
    if ($listening.Count -gt 0) { $listenerChildren += $candidate }
}
Write-Host ('TTV_CHAIN_PYTHON_CHILD_COUNT=' + $children.Count)
Write-Host ('TTV_CHAIN_PYTHON_LISTENER_CHILD_COUNT=' + $listenerChildren.Count)

$tlsStatus = 'NOT_RUN_NO_UNIQUE_TASK_CHILD_LISTENER'
if ($listenerChildren.Count -eq 1) {
    $listener = $listenerChildren[0]
    $connections = @(Get-NetTCPConnection -State Listen -OwningProcess ([int]$listener.ProcessId) -ErrorAction SilentlyContinue)
    if ($connections.Count -eq 1) {
        $ipText = [string]$connections[0].LocalAddress
        $ip = $null
        if ([Net.IPAddress]::TryParse($ipText, [ref]$ip)) {
            $octets = $ip.GetAddressBytes()
            $isPrivate4 = $octets.Length -eq 4 -and (
                $octets[0] -eq 10 -or
                ($octets[0] -eq 172 -and $octets[1] -ge 16 -and $octets[1] -le 31) -or
                ($octets[0] -eq 192 -and $octets[1] -eq 168))
            if ($isPrivate4) {
                $tcp = New-Object Net.Sockets.TcpClient
                $tls = $null
                try {
                    $pending = $tcp.BeginConnect($ipText, [int]$connections[0].LocalPort, $null, $null)
                    if (-not $pending.AsyncWaitHandle.WaitOne(2500)) {
                        $tlsStatus = 'CONNECT_TIMEOUT'
                    } else {
                        $tcp.EndConnect($pending)
                        $callback = [Net.Security.RemoteCertificateValidationCallback]{
                            param($sender,$certificate,$chain,$errors) return $true
                        }
                        $tls = [Net.Security.SslStream]::new($tcp.GetStream(), $false, $callback)
                        $tls.ReadTimeout = 3000
                        $tls.WriteTimeout = 3000
                        $tls.AuthenticateAsClient('torrent-tv-local', $null,
                            [Security.Authentication.SslProtocols]::Tls12, $false)
                        $tlsStatus = 'TLS_TRANSPORT_PASS_CERT_UNPINNED'
                    }
                } catch {
                    $tlsStatus = 'CONNECT_OR_TLS_FAILED'
                } finally {
                    if ($null -ne $tls) { $tls.Dispose() }
                    $tcp.Dispose()
                }
            } else {
                $tlsStatus = 'HOLD_BIND_NOT_EXACT_PRIVATE_LAN'
            }
        } else {
            $tlsStatus = 'HOLD_BIND_INVALID'
        }
    } else {
        $tlsStatus = 'HOLD_MULTIPLE_LISTENERS'
    }
}
Write-Host ('TTV_CHAIN_TLS=' + $tlsStatus)
Write-Host 'TTV_CHAIN_AUTH_HTTP=NOT_TESTED'
Write-Host 'TTV_CHAIN_REDMi_RENDER=NOT_TESTED'
Write-Host 'TTV_CHAIN_PROVIDER=NOT_TESTED'
Write-Host 'TTV_CHAIN_NO_PROCESS_STOP_OR_TASK_MUTATION=TRUE'
Write-Host 'TTV_CHAIN=READ_ONLY_COMPLETE'
