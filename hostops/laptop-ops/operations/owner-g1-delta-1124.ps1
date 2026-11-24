# Approved G1 candidate delta; only update stopped, idle existing Owner.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$taskName='TorrentTV-Vietsub-OwnerAgent'
$base=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$owner=Join-Path $base 'OwnerBridge'
$app=Join-Path $owner 'app'
$state=Join-Path $base 'P2\auto-lean120-state'
$inbox=Join-Path $owner 'inbox'
$health=Join-Path $owner 'agent-health.json'
$source='5e3ce11f76828daa2d5aa72cacc7514e74dc152e'
$files=@(
    @{rel='poc/p2-aisub/cue_pipeline.py';target='d63f9142fdabb0936372607e525a183fc3d7770d2903e39e6d1a57cf4dfb5126';allowed=@('caa28afbdfacf9acf2b6298fe295fc2802999a736cfceb856814e3c4b01c726f','d63f9142fdabb0936372607e525a183fc3d7770d2903e39e6d1a57cf4dfb5126')},
    @{rel='poc/p2-sub-discovery/p3_p4_ready_registry.py';target='7a11638820772d31e0ada488dc8c0410f94c294f1af469d45fc2beb72571a1e6';allowed=@('d06fb93bc186788c553253e7e1c47bdb5e11f4e091b9a945f36cc2638e444375','7a11638820772d31e0ada488dc8c0410f94c294f1af469d45fc2beb72571a1e6','7a11638820772d31e0ada488dc8c0410f94c294f1af469d45fc2beb72571a1e6')},
    @{rel='poc/p2-sub-discovery/p3_signed_signal_to_owner.py';target='e129e014efc7926d32a9f81fd515083bbdac72dfe62d42db60e317707e2689ba';allowed=@('842a900b1b0fc9ea6e670774685e47b3f02f9309c3a1f6f95bd09772f2fd4108','e129e014efc7926d32a9f81fd515083bbdac72dfe62d42db60e317707e2689ba')},
    @{rel='poc/p2-sub-discovery/trusted_playback_to_owner.py';target='f140cf5e8493cb1090780227310a35797861fbcc2e493baee9bdce35d2e43e06';allowed=@('7e8bb7d86d5395d9d3f40feb7ada3813cb7802d4e9995fc50607076728412c47','f140cf5e8493cb1090780227310a35797861fbcc2e493baee9bdce35d2e43e06')}
)
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$phase='PREFLIGHT'
function Hold([string]$reason) { throw ('G1_DELTA_'+$reason) }
function Task {
    $t=Get-ScheduledTask -TaskName $taskName -TaskPath '\'
    $s=[string]$t.Principal.UserId
    if($s -notmatch '^S-1-'){ $s=([Security.Principal.NTAccount]::new($s)).Translate([Security.Principal.SecurityIdentifier]).Value }
    if($s -cne $sid -or $t.Principal.LogonType -ine 'Interactive' -or @($t.Actions).Count -ne 1 -or $t.Actions[0].Arguments -notmatch 'start-owner-session-agent\.ps1'){Hold 'TASK_IDENTITY'}
    return $t
}
function Workers {
    @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe' OR Name='py.exe'" | Where-Object { [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py' })
}
function Idle {
    foreach($p in @($inbox,$state)){
        $d=Get-Item -LiteralPath $p -ErrorAction Stop
        if(-not $d.PSIsContainer -or ($d.Attributes -band [IO.FileAttributes]::ReparsePoint)){Hold 'STATE_ROOT'}
    }
    if(@(Get-ChildItem -LiteralPath $inbox -File -Force -Filter 'event-*.json').Count -ne 0){Hold 'PENDING_EVENTS'}
    if(@(Get-ChildItem -LiteralPath $state -Recurse -File -Force | Where-Object {$_.Name -eq 'active.lock' -or $_.Name -like '*.inflight'}).Count -ne 0){Hold 'UNKNOWN_PROVIDER_EFFECT'}
    if(@(Workers).Count -ne 0){Hold 'OWNER_WORKER_PRESENT'}
}
function Hash([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
function NormalHash([string]$p){
    $s=[IO.File]::ReadAllText($p).Replace(([string][char]13+[string][char]10),[string][char]10)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($s))).ToLowerInvariant()
}
function Receipt([string]$status,[string]$reason) {
    $spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
    $rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
    $d=@{schema='TTV-G1-DELTA-V1';nonce=$rq.nonce;status=$status;phase=$script:phase;reason=$reason;source=$source}
    [IO.File]::WriteAllText((Join-Path $spool ('Receipts\g1-delta-'+$rq.nonce+'.json')),($d|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
}
$disabled=$false
$started=$false
$changed=@()
$backup=$null
try {
    if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or $sid -in @('S-1-5-18','S-1-5-19','S-1-5-20')){Hold 'OWNER_CONTEXT'}
    if([string](Task).State -cne 'Ready'){Hold 'TASK_NOT_READY'}
    Idle
    $phase='STAGE'
    $stage=Join-Path $owner ('staged-releases\g1-delta-'+[Guid]::NewGuid().ToString('N'))
    foreach($f in $files){
        $dst=Join-Path $app $f.rel
        $item=Get-Item -LiteralPath $dst
        if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){Hold 'INSTALLED_FILE_INVALID'}
        $f.before=Hash $dst
        if($f.before -cnotin $f.allowed -and (NormalHash $dst) -cnotin $f.allowed){Hold 'INSTALLED_BASELINE_DRIFT'}
        $f.stage=Join-Path $stage $f.rel
        [IO.Directory]::CreateDirectory((Split-Path -Parent $f.stage))|Out-Null
        Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/'+$source+'/'+$f.rel) -OutFile $f.stage -TimeoutSec 30
        if((Hash $f.stage) -cne $f.target){Hold 'STAGED_HASH'}
    }
    $phase='OFFLINE_CHECK'
    $py='import ast,pathlib,sys; root=pathlib.Path(sys.argv[1]); paths=list(root.rglob("*.py")); assert len(paths)==4; [ast.parse(p.read_text("utf-8")) for p in paths]; sys.path[:0]=[str(root/"poc/p2-sub-discovery"),str(root/"poc/p2-aisub"),str(pathlib.Path(sys.argv[2])/"poc/p2-sub-discovery"),str(pathlib.Path(sys.argv[2])/"poc/p2-aisub"),str(pathlib.Path(sys.argv[2])/"poc/p3-vietsub-trigger")]; import cue_pipeline,p3_p4_ready_registry,p3_signed_signal_to_owner,trusted_playback_to_owner; assert cue_pipeline.MAX_CUES==10000; print("G1_DELTA_IMPORT_PASS")'
    $check=@(& py -3 -I -B -c $py $stage $app 2>&1)
    if($LASTEXITCODE -ne 0 -or @($check | Where-Object {[string]$_ -ceq 'G1_DELTA_IMPORT_PASS'}).Count -ne 1){Hold 'IMPORT'}
    $phase='BACKUP'
    $backup=Join-Path $owner ('backups\g1-delta-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($backup)|Out-Null
    foreach($f in $files){
        $dst=Join-Path $app $f.rel
        if((Hash $dst) -cne $f.before){Hold 'BASELINE_CHANGED'}
        $f.saved=Join-Path $backup ([IO.Path]::GetFileName($f.rel))
        [IO.File]::Copy($dst,$f.saved,$false)
        if((Hash $f.saved) -cne $f.before){Hold 'BACKUP_HASH'}
    }
    $phase='APPLY'
    Idle
    if([string](Task).State -cne 'Ready'){Hold 'TASK_STATE_CHANGED'}
    Disable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
    $disabled=$true
    Idle
    foreach($f in $files){
        $dst=Join-Path $app $f.rel
        if([string](Task).State -cne 'Disabled' -or (Hash $dst) -cne $f.before -or (Hash $f.stage) -cne $f.target){Hold 'APPLY_DRIFT'}
        if($f.before -ceq $f.target){continue}
        $tmp=Join-Path (Split-Path -Parent $dst) ('.g1-delta-'+[Guid]::NewGuid().ToString('N')+'.tmp')
        [IO.File]::Copy($f.stage,$tmp,$false)
        [IO.File]::Replace($tmp,$dst,($f.saved+'.displaced'))
        $changed+=@($f)
        if((Hash $dst) -cne $f.target){Hold 'POST_HASH'}
    }
    Idle
    $phase='START'
    $since=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
    $disabled=$false
    $started=$true
    Start-ScheduledTask -TaskName $taskName -TaskPath '\'
    $ready=$false
    for($i=0;$i -lt 45;$i++){
        Start-Sleep -Seconds 1
        if([string](Task).State -cne 'Running'){continue}
        try{
            $h=Get-Content -LiteralPath $health -Raw | ConvertFrom-Json
            if($h.state -cne 'READY' -or [long]$h.observed_utc_epoch -lt $since-1 -or [long]$h.pid -le 0){continue}
            $w=Get-CimInstance Win32_Process -Filter ('ProcessId='+[long]$h.pid)
            if($null -eq $w -or [string]$w.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py'){continue}
            $who=Invoke-CimMethod -InputObject $w -MethodName GetOwnerSid
            if($who.ReturnValue -eq 0 -and $who.Sid -ceq $sid){$ready=$true;break}
        }catch{}
    }
    if(-not $ready){Hold 'START_HEARTBEAT_UNVERIFIED'}
    foreach($f in $files){if((Hash (Join-Path $app $f.rel)) -cne $f.target){Hold 'RUNNING_HASH_DRIFT'}}
    $phase='DONE'
    Receipt 'SUCCESS' 'FOUR_HASHES_FRESH_OWNER'
    Write-Output 'G1_DELTA_INSTALL=FOUR_HASHES_FRESH_OWNER'
}catch{
    $reason=[string]$_.Exception.Message
    if($reason -notmatch '^G1_DELTA_[A-Z_]+$'){$reason='G1_DELTA_PRIVATE_EXCEPTION'}
    # Before a start attempt, restore only files this transaction replaced.
    # After a start attempt, retain checkpoints/backups and reconcile, no blind restart.
    if($disabled -and -not $started){
        try{
            Idle
            foreach($f in $changed){
                $dst=Join-Path $app $f.rel
                if((Hash $dst) -cne $f.target -or (Hash $f.saved) -cne $f.before){Hold 'ROLLBACK_DRIFT'}
                $tmp=Join-Path (Split-Path -Parent $dst) ('.g1-rollback-'+[Guid]::NewGuid().ToString('N')+'.tmp')
                [IO.File]::Copy($f.saved,$tmp,$false)
                [IO.File]::Replace($tmp,$dst,($f.saved+'.failed'))
                if((Hash $dst) -cne $f.before){Hold 'ROLLBACK_HASH'}
            }
            Enable-ScheduledTask -TaskName $taskName -TaskPath '\'|Out-Null
        }catch{$reason='G1_DELTA_ROLLBACK_HOLD'}
    }
    Receipt 'HOLD' $reason
    throw $reason
}
