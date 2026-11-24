# Owner approved: remove the 10-minute execution ceiling from the isolated HostOps task only.
# No elevation, no restart, no changes to Owner production, Chrome or AGY global settings.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('tr-ttv-task-limit-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$name='TorrentTV-Vietsub-Laptop-HostOps'
$prod='TorrentTV-Vietsub-OwnerAgent'
function Listener([int]$port){
 @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique | Sort-Object)
}
function WritePrivate([string]$p,[string]$s){
 [IO.File]::WriteAllText($p,$s,[Text.UTF8Encoding]::new($false))
}
function OtherDefinition([string]$xmlText){
 [xml]$x=$xmlText
 $ns=[Xml.XmlNamespaceManager]::new($x.NameTable)
 $ns.AddNamespace('t',$x.DocumentElement.NamespaceURI)
 $nodes=@($x.SelectNodes('/t:Task/t:Settings/t:ExecutionTimeLimit',$ns))
 foreach($n in $nodes){[void]$n.ParentNode.RemoveChild($n)}
 return $x.OuterXml
}
$before9444=@(Listener 9444)
$before9555=@(Listener 9555)
$prodBefore=Export-ScheduledTask -TaskName $prod -TaskPath '\'
$prodState=[string](Get-ScheduledTask -TaskName $prod -TaskPath '\').State
$task=Get-ScheduledTask -TaskName $name -TaskPath '\'
$before=Export-ScheduledTask -TaskName $name -TaskPath '\'
WritePrivate (Join-Path $run 'hostops-task-before.xml') $before
$code='TR04L_UNKNOWN'
$old=[string]$task.Settings.ExecutionTimeLimit
$changed=0
try {
 if([string]$task.Description -cne 'TTV_LAPTOP_HOSTOPS_OWNER_INTERACTIVE_ROUTINE_V1' -or [string]$task.Principal.LogonType -ine 'Interactive' -or [string]$task.Principal.RunLevel -ine 'Limited' -or [string]$task.Settings.MultipleInstances -ine 'IgnoreNew' -or @($task.Actions).Count -ne 1 -or ($null -ne $task.Triggers -and @($task.Triggers).Count -ne 0)){throw 'HOSTOPS_IDENTITY_DRIFT'}
 $action=@($task.Actions)[0]
 if([IO.Path]::GetFileName([string]$action.Execute) -ine 'pwsh.exe' -or [string]$action.Arguments -notmatch 'owner-laptop-ops-helper\.ps1"\z'){throw 'HOSTOPS_ACTION_DRIFT'}
 if($old -eq 'PT0S'){$code='TR04L_ALREADY_UNLIMITED'}
 elseif($old -ne 'PT10M'){$code='TR04L_UNEXPECTED_PRIOR'}
 else {
   $settings=$task.Settings
   $settings.ExecutionTimeLimit='PT0S'
   Set-ScheduledTask -TaskName $name -TaskPath '\' -Settings $settings -ErrorAction Stop|Out-Null
   $changed=1
   $code='TR04L_APPLIED'
 }
 $after=Export-ScheduledTask -TaskName $name -TaskPath '\'
 WritePrivate (Join-Path $run 'hostops-task-after.xml') $after
 $new=[string](Get-ScheduledTask -TaskName $name -TaskPath '\').Settings.ExecutionTimeLimit
 $other=[int]((OtherDefinition $before) -ceq (OtherDefinition $after))
 if($new -ne 'PT0S' -and $code -in @('TR04L_APPLIED','TR04L_ALREADY_UNLIMITED')){$code='TR04L_READBACK_MISMATCH'}
 if($other -ne 1){$code='TR04L_OTHER_DEFINITION_DRIFT'}
} catch {
 WritePrivate (Join-Path $run 'task-change-error.txt') ($_.Exception.GetType().FullName+': '+$_.Exception.Message)
 $code=if($_.Exception.Message -match 'access is denied|access denied|0x80070005|unauthorized|AccessDenied'){'TR04L_ACCESS_DENIED'}else{'TR04L_LOCAL_ERROR'}
}
$readback=Get-ScheduledTask -TaskName $name -TaskPath '\'
$after=Export-ScheduledTask -TaskName $name -TaskPath '\'
$new=[string]$readback.Settings.ExecutionTimeLimit
$other=[int]((OtherDefinition $before) -ceq (OtherDefinition $after))
$prodAfter=Export-ScheduledTask -TaskName $prod -TaskPath '\'
$prodSame=[int]($prodBefore -ceq $prodAfter)
$prodStateSame=[int]($prodState -ceq [string](Get-ScheduledTask -TaskName $prod -TaskPath '\').State)
$w=[int](($before9444 -join ',') -ceq (@(Listener 9444) -join ','))
$b=[int](($before9555 -join ',') -ceq (@(Listener 9555) -join ','))
$code=$code+'_U'+[int]($new -eq 'PT0S')+'D'+$other+'P'+$prodSame+'O'+$prodStateSame+'W'+$w+'B'+$b+'C'+$changed
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
WritePrivate (Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')) ($doc|ConvertTo-Json -Compress)
Write-Output $code
