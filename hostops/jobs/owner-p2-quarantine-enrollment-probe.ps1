# Fixed read-only HostOps probe for a possibly partially enrolled Owner task.
# Runs as NETWORK_SERVICE. Never starts a task or opens Owner-private files.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $sid -cne 'S-1-5-20') {
    throw 'HOSTOPS_P2_ENROLL_PROBE_TRUSTED_RUNNER_REQUIRED'
}

$normal = 'TorrentTV-Vietsub-OwnerAgent'
$maintenance = 'TorrentTV-Vietsub-P2-Quarantine-Once'
try {
    $owner = Get-ScheduledTask -TaskName $normal -TaskPath '\' -ErrorAction Stop
    Write-Output ('HOSTOPS_P2_OWNER_TASK=' + [string]$owner.State.ToString().ToUpperInvariant())
} catch {
    Write-Output 'HOSTOPS_P2_OWNER_TASK=NOT_READABLE'
}
try {
    $task = Get-ScheduledTask -TaskName $maintenance -TaskPath '\' -ErrorAction Stop
} catch {
    Write-Output 'HOSTOPS_P2_MAINTENANCE_TASK=NOT_READABLE_OR_MISSING'
    Write-Output 'HOSTOPS_P2_MAINTENANCE_EXECUTION=NOT_RUN_BY_PROBE'
    exit 0
}
Write-Output 'HOSTOPS_P2_MAINTENANCE_TASK=FOUND'
Write-Output ('HOSTOPS_P2_MAINTENANCE_STATE=' + [string]$task.State.ToString().ToUpperInvariant())
$fixedDescription = [string]$task.Description -ceq 'TTV_OWNER_P2_BATCH_0001_QUARANTINE_ONCE_V1'
$fixedPrincipal = [string]$task.Principal.LogonType -ieq 'Interactive' -and
    [string]$task.Principal.RunLevel -ieq 'Limited'
$triggerCount = if ($null -eq $task.Triggers) { 0 } else { @($task.Triggers).Count }
Write-Output ('HOSTOPS_P2_MAINTENANCE_IDENTITY=' + $(if ($fixedDescription -and $fixedPrincipal -and
    $triggerCount -eq 0) { 'EXPECTED' } else { 'DRIFT' }))

try {
    $last = Get-ScheduledTaskInfo -TaskName $maintenance -TaskPath '\' -ErrorAction Stop
    $attempt = if ($last.LastRunTime -gt [datetime]'2001-01-01') { 'PRIOR_ATTEMPT' } else { 'NEVER_RUN' }
    Write-Output "HOSTOPS_P2_MAINTENANCE_ATTEMPT=$attempt"
    # Task Scheduler reports the Owner task's process exit code without
    # granting the service access to Owner-private logs or P2 state.
    # Never promote an exit code into proof that a marker was quarantined.
    if ($attempt -ceq 'PRIOR_ATTEMPT') {
        $exitCode = [Convert]::ToString([int]$last.LastTaskResult, 16).PadLeft(8, '0').ToUpperInvariant()
        Write-Output "HOSTOPS_P2_MAINTENANCE_LAST_RESULT=0x$exitCode"
        Write-Output 'HOSTOPS_P2_MAINTENANCE_LAST_RESULT_IS_QUARANTINE_PROOF=NO'
    } else {
        Write-Output 'HOSTOPS_P2_MAINTENANCE_LAST_RESULT=NOT_APPLICABLE'
    }
} catch {
    Write-Output 'HOSTOPS_P2_MAINTENANCE_ATTEMPT=NOT_READABLE'
    Write-Output 'HOSTOPS_P2_MAINTENANCE_LAST_RESULT=NOT_READABLE'
}

try {
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $registered = $service.GetFolder('\').GetTask($maintenance)
    $sddl = [string]$registered.GetSecurityDescriptor(4)
    $raw = [Security.AccessControl.RawSecurityDescriptor]::new($sddl)
    $found = 0
    foreach ($ace in $raw.DiscretionaryAcl) {
        if ($ace -is [Security.AccessControl.QualifiedAce] -and
            $ace.SecurityIdentifier.Value -ceq 'S-1-5-20') {
            $found += 1
            Write-Output ('HOSTOPS_P2_NETWORKSERVICE_ACE_QUALIFIER=' + $ace.AceQualifier.ToString().ToUpperInvariant())
            Write-Output ('HOSTOPS_P2_NETWORKSERVICE_ACE_MASK=0x' +
                [Convert]::ToString([int]$ace.AccessMask, 16).PadLeft(8, '0').ToUpperInvariant())
        }
    }
    Write-Output "HOSTOPS_P2_NETWORKSERVICE_ACE_COUNT=$found"
} catch {
    Write-Output 'HOSTOPS_P2_NETWORKSERVICE_DACL=NOT_READABLE'
}
Write-Output 'HOSTOPS_P2_MAINTENANCE_EXECUTION=NOT_RUN_BY_PROBE'
Write-Output 'HOSTOPS_P2_OWNER_PRIVATE_DATA=NOT_ACCESSED'
Write-Output 'HOSTOPS_P2_PROVIDER_AND_TV=NOT_RUN'
