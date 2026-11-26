# Fixed Owner Control action: no maintenance spool request, no dynamic payload.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne 'S-1-5-20'){throw 'WRONG_RUNNER'}
$action='Stop'
$name='TorrentTV-Vietsub-Owner-'+$action
$t=Get-ScheduledTask -TaskName $name -TaskPath '\'
if($t.Description -cne 'TTV_FIXED_OWNER_CONTROL_V2' -or [string]$t.Principal.LogonType -ine 'Interactive' -or [string]$t.State -cne 'Ready'){throw 'CONTROL_TASK_UNAVAILABLE'}
$root=Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerControl'
$f=Join-Path $root ($action+'.json')
$since=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
Start-ScheduledTask -TaskName $name -TaskPath '\'
for($i=0;$i -lt 95;$i++){
 Start-Sleep -Seconds 1
 if(-not (Test-Path -LiteralPath $f -PathType Leaf)){continue}
 $r=Get-Content -LiteralPath $f -Raw|ConvertFrom-Json
 if($r.schema -cne 'TTV-OWNER-CONTROL-V2' -or $r.action -cne $action -or [long]$r.started_ms -lt $since -or [long]$r.completed_ms -lt [long]$r.started_ms -or $r.result -cnotmatch '^[A-Z0-9_]{3,100}$'){continue}
 Write-Output ('OWNER_CONTROL_ACTION='+$action.ToUpperInvariant())
 Write-Output ('OWNER_CONTROL_RESULT='+$r.result)
 if($action -eq 'Stop' -and $r.result -cne 'STOPPED'){throw 'OWNER_STOP_HOLD'}
 if($action -eq 'Start' -and $r.result -cne 'RUNNING'){throw 'OWNER_START_HOLD'}
 return
}
throw 'OWNER_CONTROL_RECEIPT_MISSING_NO_RETRY'
