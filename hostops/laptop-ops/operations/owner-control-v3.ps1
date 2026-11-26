# Reusable Owner lifecycle, local or pinned HostOps. Does not stop TorrServer or Chrome.
param([switch]$Status,[switch]$StopOwner,[switch]$StartOwner)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(@(@($Status,$StopOwner,$StartOwner)|Where-Object{$_}).Count -ne 1){throw 'CHOOSE_ONE_ACTION'}
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0){throw 'OWNER_CONTEXT_REQUIRED'}
$base=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$owner=Join-Path $base 'OwnerBridge'
$app=Join-Path $owner 'app'
$taskName='TorrentTV-Vietsub-OwnerAgent'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
function Task{
 $t=Get-ScheduledTask -TaskName $taskName -TaskPath '\'
 $s=[string]$t.Principal.UserId
 if($s -notmatch '^S-\d'){$s=([Security.Principal.NTAccount]::new($s).Translate([Security.Principal.SecurityIdentifier])).Value}
 if($s -cne $sid -or [string]$t.Principal.LogonType -ine 'Interactive' -or @($t.Actions).Count -ne 1 -or [string]$t.Actions[0].Arguments -notmatch 'start-owner-session-agent\.ps1'){throw 'TASK_IDENTITY'}
 $t
}
function Workers{
 $paths=@((Join-Path $app 'poc\p2-sub-discovery\owner_p3_p4_entrypoint.py'),(Join-Path $app 'poc\p2-sub-discovery\owner_session_bridge.py'))
 foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe' OR Name='py.exe'")){
   if([string]$p.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'){continue}
   $hits=@($paths|Where-Object{([string]$p.CommandLine).IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0})
   $who=Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid
   if($hits.Count -ne 1 -or $who.ReturnValue -ne 0 -or $who.Sid -cne $sid -or -not $p.CreationDate){throw 'WORKER_IDENTITY'}
   $p
 }
}
function Ready([long]$old,[long]$since){
 try{
   $h=Get-Content -LiteralPath (Join-Path $owner 'agent-health.json') -Raw|ConvertFrom-Json
   $age=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-[long]$h.observed_utc_epoch
   if($h.schema -cne 'TTV-OWNER-AGENT-HEALTH-V1' -or $h.state -cne 'READY' -or $age -lt 0 -or $age -gt 30 -or [long]$h.pid -eq $old -or [long]$h.observed_utc_epoch -lt $since){return 0}
   if(@(Workers|Where-Object{[long]$_.ProcessId -eq [long]$h.pid}).Count -ne 1){return 0}
   return [long]$h.pid
 }catch{return 0}
}
function Stop-Control{
 $t=Task
 if([string]$t.State -ceq 'Disabled' -and @(Workers).Count -eq 0){return 'STOPPED'}
 $before=@(Workers)
 Disable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
 try{Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop}catch{}
 foreach($w in @(Workers)){
   $known=@($before|Where-Object{[int]$_.ProcessId -eq [int]$w.ProcessId -and $_.CreationDate -eq $w.CreationDate -and $_.CommandLine -ceq $w.CommandLine})
   if($known.Count -ne 1 -or [string](Task).State -cne 'Disabled'){return 'HOLD_STOP_IDENTITY'}
   Stop-Process -Id ([int]$w.ProcessId) -Force -ErrorAction Stop
 }
 for($i=0;$i -lt 5 -and @(Workers).Count -gt 0;$i++){Start-Sleep -Milliseconds 300}
 if(@(Workers).Count -ne 0 -or [string](Task).State -cne 'Disabled'){return 'HOLD_STOP_UNVERIFIED'}
 return 'STOPPED'
}
function Start-Control{
 $t=Task
 if([string]$t.State -ceq 'Running' -and (Ready 0 0) -gt 0){return 'RUNNING'}
 if(@(Workers).Count -ne 0){return 'HOLD_RESIDUAL'}
 $since=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-1
 Enable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
 Start-ScheduledTask -TaskName $taskName -TaskPath '\'
 for($i=0;$i -lt 30;$i++){Start-Sleep -Seconds 1;if([string](Task).State -ceq 'Running' -and (Ready 0 $since) -gt 0){return 'RUNNING'}}
 return 'HOLD_START_UNVERIFIED'
}

# Fixed lifecycle tasks use a dedicated receipt folder, not the maintenance spool.
$receiptRoot=Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerControl'
$action=if($StopOwner){'Stop'}elseif($StartOwner){'Start'}else{'Status'}
$began=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$code='HOLD_UNKNOWN'
$mutex=[Threading.Mutex]::new($false,'Local\TorrentTVVietsubOwnerControl')
$owned=$false
try{
 $owned=$mutex.WaitOne(0)
 if(-not $owned){$code='HOLD_CONTROL_BUSY'}
 elseif(($StopOwner -or $StartOwner) -and [string](Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-Laptop-HostOps' -TaskPath '\').State -eq 'Running'){$code='HOLD_MAINTENANCE_RUNNING'}
 elseif($StopOwner){$code=Stop-Control}
 elseif($StartOwner){$code=Start-Control}
 else{$t=Task;$code='STATUS_'+([string]$t.State).ToUpperInvariant()+'_W'+@(Workers).Count}
}catch{$code='HOLD_EXCEPTION_'+$_.Exception.GetType().Name.ToUpperInvariant()}
finally{if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}
$rec=@{schema='TTV-OWNER-CONTROL-V2';action=$action;started_ms=$began;completed_ms=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();result=$code}
$target=Join-Path $receiptRoot ($action+'.json')
$temp=$target+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
[IO.File]::WriteAllText($temp,($rec|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
[IO.File]::Move($temp,$target,$true)
Write-Output ('OWNER_CONTROL_'+$code)
