# Read the exact completed private stage; prepare launcher and rollback ledger, without installing.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$app=Join-Path $owner 'app'
$code='V13_READY_HOLD'
try {
 $hits=@(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -Filter 'receipt-*.json' -File|ForEach-Object{
   $v=Get-Content -LiteralPath $_.FullName -Raw|ConvertFrom-Json
   if($v.source_commit -ceq 'b1c1fa23dd0234554bb8b9b8d284c2f2d45aea67' -and $v.result -ceq 'SUCCESS' -and $v.nonce -cmatch '^[a-f0-9]{32}$'){$v.nonce}
 })
 if($hits.Count -ne 1){throw 'STAGE_RECEIPT'}
 $stage=Join-Path $owner ('staged-releases\v13-e1749ae-'+$hits[0])
 $task=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'
 if(@($task.Actions).Count -ne 1 -or [string]$task.Actions[0].Arguments -notmatch '(?i)-File\s+"([^"]+start-owner-session-agent\.ps1)"'){throw 'LAUNCHER'}
 $launcher=[IO.Path]::GetFullPath($Matches[1])
 if(-not $launcher.StartsWith($owner+'\',[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $launcher -PathType Leaf)){throw 'LAUNCHER_SCOPE'}
 $py=@'
import hashlib,json,pathlib,sys
stage,app,launcher=map(pathlib.Path,sys.argv[1:4])
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
v=json.loads((stage/"gate-comparison.json").read_text(encoding="utf-8"))
a=v["installed"]+v["installed_sequence"];b=v["candidate"]+v["candidate_sequence"]
assert len(a)==len(b)==19
status=sum(x[0]==y[0] for x,y in zip(a,b)); reason=sum(x[1]==y[1] for x,y in zip(a,b)); fp=sum(x[2]==y[2] for x,y in zip(a,b))
gate=app/"poc/p3-vietsub-trigger/activation_gate.py"
assert sha(gate)==v["installed_gate_sha256"]
assert sha(stage/"rollback/poc/p3-vietsub-trigger/activation_gate.py")==sha(gate)
print("G"+str(status)+"R"+str(reason)+"F"+str(fp)+"D"+str(len(v["changed_ast_definitions"])))
'@
 $lines=@(& py -3 -I -B -c $py $stage $app $launcher 2> (Join-Path $stage 'stage-review-stderr.txt'))
 if($LASTEXITCODE -ne 0 -or $lines.Count -ne 1 -or [string]$lines[0] -cnotmatch '^G\d+R\d+F\d+D\d+$'){throw 'COMPARE_RECEIPT'}
 $result=[string]$lines[0]
 $raw=[IO.File]::ReadAllText($launcher)
 $anchor='    $env:PYTHONUTF8 = ''1'''
 if($raw -match '(?i)TTV_NATIVE_V13' -or [regex]::Matches($raw,[regex]::Escape($anchor)).Count -ne 1){throw 'LAUNCHER_CONFIG'}
 $saved=Join-Path $stage 'rollback\start-owner-session-agent.ps1'
 $new=Join-Path $stage 'candidate\start-owner-session-agent.ps1'
 [IO.File]::Copy($launcher,$saved,$false)
 $changed=$raw.Replace($anchor,$anchor+[Environment]::NewLine+'    $env:TTV_NATIVE_V13 = ''1''')
 [IO.File]::WriteAllText($new,$changed,[Text.UTF8Encoding]::new($false))
 $tokens=$null;$errors=$null
 [Management.Automation.Language.Parser]::ParseFile($new,[ref]$tokens,[ref]$errors)|Out-Null
 if(@($errors).Count -ne 0){throw 'LAUNCHER_PARSE'}
 $prior=(Get-FileHash -LiteralPath $launcher -Algorithm SHA256).Hash.ToLowerInvariant()
 if((Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash.ToLowerInvariant() -cne $prior){throw 'LAUNCHER_BACKUP'}
 $target=(Get-FileHash -LiteralPath $new -Algorithm SHA256).Hash.ToLowerInvariant()
 $ledger=@{schema='TTV-V13-STAGED-ACTIVATION-V1';source='e1749ae60515731168bd554fe12a05031f50d040';stage_nonce=$hits[0];gate_result=$result;launcher_prior=$prior;launcher_target=$target;activation='NOT_APPLIED'}
 [IO.File]::WriteAllText((Join-Path $stage 'activation-ledger.json'),($ledger|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
 $code='V13_READY_'+$result+'_L1'
}catch{
 $code='V13_READY_HOLD'
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
