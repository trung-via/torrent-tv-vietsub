# Install fixed interactive lifecycle actions only. Never stop or start Owner during enrollment.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$phase='CONTEXT'
$count=0
try{
 $id=[Security.Principal.WindowsIdentity]::GetCurrent()
 if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0){throw 'OWNER_CONTEXT'}
 $old=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'
 function SidOf([string]$s){if($s -match '^S-\d'){return $s};([Security.Principal.NTAccount]::new($s).Translate([Security.Principal.SecurityIdentifier])).Value}
 if((SidOf $old.Principal.UserId) -cne $id.User.Value -or [string]$old.Principal.LogonType -ine 'Interactive'){throw 'OWNER_TASK'}
 $phase='DOWNLOAD'
 $local=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge\Maintenance\owner-control.ps1'
 $tmp=Join-Path $env:TEMP ('ttv-control-'+$rq.nonce+'.ps1')
 $url='https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/'+$rq.source_commit+'/hostops/laptop-ops/operations/owner-control-v2.ps1'
 Invoke-WebRequest -Uri $url -OutFile $tmp -TimeoutSec 25
 $expected='cb2fafc65b37e62671df1a4765814c107158711806913a0d84c849a3477e7a31'
 if((Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected){throw 'HASH'}
 $tokens=$null;$errors=$null
 [Management.Automation.Language.Parser]::ParseFile($tmp,[ref]$tokens,[ref]$errors)|Out-Null
 if(@($errors).Count){throw 'PARSE'}
 $phase='LOCAL'
 if(Test-Path -LiteralPath $local){
   if((Get-FileHash -LiteralPath $local -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected){throw 'LOCAL_CONFLICT'}
 }else{[IO.File]::Copy($tmp,$local,$false)}
 $root=Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerControl'
 [IO.Directory]::CreateDirectory($root)|Out-Null
 if((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'REPARSE'}
 & icacls.exe $root /inheritance:r /grant:r "*$($id.User.Value):(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' '*S-1-5-20:(OI)(CI)RX'|Out-Null
 if($LASTEXITCODE -ne 0){throw 'RECEIPT_ACL'}
 $phase='TASKS'
 $pwsh=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
 $svc=New-Object -ComObject 'Schedule.Service';$svc.Connect()
 foreach($action in @('Status','Stop','Start')){
  $name='TorrentTV-Vietsub-Owner-'+$action
  $switch=if($action -eq 'Status'){'-Status'}elseif($action -eq 'Stop'){'-StopOwner'}else{'-StartOwner'}
  $args='-NoLogo -NoProfile -NonInteractive -File "'+$local+'" '+$switch
  $t=Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue
  if($null -eq $t){
   $act=New-ScheduledTaskAction -Execute $pwsh -Argument $args
   $principal=New-ScheduledTaskPrincipal -UserId $id.Name -LogonType Interactive -RunLevel Limited
   $settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 3) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
   Register-ScheduledTask -TaskName $name -TaskPath '\' -InputObject (New-ScheduledTask -Action $act -Principal $principal -Settings $settings -Description 'TTV_FIXED_OWNER_CONTROL_V2') -ErrorAction Stop|Out-Null
   $t=Get-ScheduledTask -TaskName $name -TaskPath '\'
  }
  if($t.Description -cne 'TTV_FIXED_OWNER_CONTROL_V2' -or (SidOf $t.Principal.UserId) -cne $id.User.Value -or [string]$t.Principal.LogonType -ine 'Interactive' -or [string]$t.Principal.RunLevel -ine 'Limited' -or @($t.Actions).Count -ne 1 -or $null -ne $t.Triggers -or [string]$t.Actions[0].Execute -ine $pwsh -or [string]$t.Actions[0].Arguments -cne $args){throw 'TASK_DRIFT'}
  $registered=$svc.GetFolder('\').GetTask($name)
  $sddl=[string]$registered.GetSecurityDescriptor(4)
  $sd=[Security.AccessControl.RawSecurityDescriptor]::new($sddl)
  $ace=@($sd.DiscretionaryAcl|Where-Object{$_.SecurityIdentifier.Value -ceq 'S-1-5-20'})
  if($ace.Count -eq 0){$registered.SetSecurityDescriptor($sddl+'(A;;GRGX;;;NS)',0)}
  elseif($ace.Count -ne 1 -or $ace[0].AccessMask -notin @(-1610612736,0x001200a9)){throw 'TASK_ACL'}
  $count++
 }
 $code='OWNER_CONTROL_ENROLLED_T3'
}catch{$code='OWNER_CONTROL_HOLD_'+$phase+'_T'+$count+'_'+$_.Exception.GetType().Name.ToUpperInvariant()}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
