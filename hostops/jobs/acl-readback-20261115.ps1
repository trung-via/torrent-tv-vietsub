# Read-only Windows Task Scheduler ACL readback after owner-side grant attempt.
# No task starts, process kills, ACL writes, paths, secrets, or SDDL are emitted.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$taskFullName = '\\TorrentTV-Vietsub-OwnerAgent'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
Write-Host ('TTV_HOSTOPS_IDENTITY_NETWORK_SERVICE=' + [string]($identity.User.Value -ceq 'S-1-5-20'))
Write-Host ('TTV_ACL_READBACK_MODE=READ_ONLY')
$null = & schtasks.exe /Query /TN $taskFullName /FO LIST 2>&1
$taskQueryCode = $LASTEXITCODE
Write-Host ('TTV_ACL_SCHTASKS_QUERY_EXIT=' + $taskQueryCode)
try {
    $scheduled = @(Get-ScheduledTask -TaskName $taskName -ErrorAction Stop)
    Write-Host ('TTV_ACL_SCHEDULED_TASK_VISIBLE=' + [string]($scheduled.Count -eq 1))
} catch {
    Write-Host 'TTV_ACL_SCHEDULED_TASK_VISIBLE=NO'
    Write-Host ('TTV_ACL_SCHEDULED_TASK_ERROR_TYPE=' + $_.Exception.GetType().Name)
}
try {
    $svc = New-Object -ComObject 'Schedule.Service'
    $svc.Connect()
    $registered = $svc.GetFolder('\\').GetTask($taskName)
    Write-Host 'TTV_ACL_COM_TASK_OPEN=PASS'
    try {
        $sddl = [string]$registered.GetSecurityDescriptor(7)
        $sd = [Security.AccessControl.RawSecurityDescriptor]::new($sddl)
        $aces = @($sd.DiscretionaryAcl | Where-Object {
            $_ -is [Security.AccessControl.CommonAce] -and
            $_.SecurityIdentifier.Value -ceq 'S-1-5-20'
        })
        Write-Host ('TTV_ACL_NETWORK_SERVICE_ACE_COUNT=' + $aces.Count)
        foreach ($ace in $aces) {
            $bits = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$ace.AccessMask), 0)
            Write-Host ('TTV_ACL_NETWORK_SERVICE_ACE=' + $ace.AceQualifier.ToString() + ':' + ('0x{0:X8}' -f $bits))
        }
    } catch {
        Write-Host ('TTV_ACL_COM_SDDL_READ_ERROR=' + $_.Exception.GetType().Name)
    }
} catch {
    Write-Host ('TTV_ACL_COM_TASK_OPEN_ERROR=' + $_.Exception.GetType().Name)
}
Write-Host 'TTV_ACL_READBACK_COMPLETE=YES'
Write-Host 'TTV_ACL_TASK_STARTED=NO'
Write-Host 'TTV_ACL_PROCESS_KILLED=NO'
Write-Host 'TTV_ACL_WINDOWS_PERMISSIONS_CHANGED=NO'