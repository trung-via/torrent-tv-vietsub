# Read-only post-start identity/socket inventory for Torrent TV OwnerAgent.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:GITHUB_ACTIONS -cne 'true' -or
    [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne 'S-1-5-20') {
    throw 'TTV_POSTSTART_UNTRUSTED_RUNNER'
}
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$task = @(Get-ScheduledTask -TaskName $taskName -ErrorAction Stop)
if ($task.Count -ne 1 -or $task[0].TaskPath -cne [string][char]92) {
    throw 'TTV_POSTSTART_TASK_PATH_MISMATCH'
}
$task = $task[0]
$info = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction Stop
Write-Host 'TTV_POSTSTART_MODE=READ_ONLY'
Write-Host ('TTV_POSTSTART_TASK_STATE=' + [string]$task.State)
Write-Host ('TTV_POSTSTART_LAST_TASK_RESULT=' + [string]$info.LastTaskResult)
$procs = @(Get-CimInstance Win32_Process -ErrorAction Stop |
    Where-Object {
        [int]$_.SessionId -eq 1 -and
        $_.Name -in @('pwsh.exe','python.exe','py.exe')
    })
Write-Host ('TTV_POSTSTART_SESSION1_RELEVANT_COUNT=' + $procs.Count)
foreach ($p in $procs) {
    $listeners = @(Get-NetTCPConnection -OwningProcess ([int]$p.ProcessId) -State Listen -ErrorAction SilentlyContinue)
    Write-Host ('TTV_POSTSTART_PROCESS=' + $p.Name + '/' + [string]$p.ProcessId +
        '/parent=' + [string]$p.ParentProcessId + '/listeners=' + $listeners.Count)
}
$old = @(Get-NetTCPConnection -OwningProcess 2500 -State Listen -ErrorAction SilentlyContinue)
Write-Host ('TTV_POSTSTART_OLD_PID_2500_LISTENERS=' + $old.Count)
$other = @($procs | Where-Object { $_.Name -eq 'python.exe' -and [int]$_.ProcessId -ne 2500 })
Write-Host ('TTV_POSTSTART_OTHER_SESSION1_PYTHON_COUNT=' + $other.Count)
Write-Host 'TTV_POSTSTART_PROCESS_KILL=NO'
Write-Host 'TTV_POSTSTART_TASK_START=NO'
Write-Host 'TTV_POSTSTART_TV_PROVIDER=NOT_VERIFIED'
Write-Host 'TTV_POSTSTART=READ_ONLY_COMPLETE'