# Authorized LAN rebind + two-module source-neutral update on exact R3.
# Owner-interactive only. No provider, cache deletion, APK install or firewall changes.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$app = Join-Path $root 'app\poc\p2-sub-discovery'
$p2App = Join-Path $root 'app\poc\p2-aisub'
$stage = Join-Path $root ('staged-releases\source-neutral-31abfb2-' + [Guid]::NewGuid().ToString('N'))
$p2 = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$cache = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\subtitle-trials'
$healthPath = Join-Path $root 'agent-health.json'
$backupRoot = Join-Path $root 'backups'
$ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$baseline = [ordered]@{
    'automatic_vietsub_flow.py' = '86423538c3c04a37e02d308a26edea07666693b4eae2e43281229fecd3661e27'
    'brain_english_inbox.py' = '61d64d3c170b325f587d82220b2e2b23aee196496a24d655fd3dae9b34f3f2fb'
    'owner_p3_p4_runtime.py' = 'a8af95433fc256082636440e74fa3343912f56b4a45b483948af00a9ce4898e3'
    'owner_r2_progressive_registry.py' = '91278b64505c7dc88acc93f76240290f873243ffeff4c2901c07ec6d7fa9d963'
    'owner_session_bridge.py' = '636e91b671527730a9ce59a937768d254b865ee8be8557d823af9424c3e5b0a8'
    'p3_p4_shared_https_route_r0.py' = '1e700b3f0788ce91265a627b99baff9f3874d91102d5b87088e974531f67e8e6'
    'p3_signed_signal_to_owner.py' = '842a900b1b0fc9ea6e670774685e47b3f02f9309c3a1f6f95bd09772f2fd4108'
    'agy_opensubtitles_acquisition.py' = 'dcf4282926067dce8e1e05f9be9d36aa1e96443bbe2710c134b0eaedec9debce'
    'matcher.py' = '18df6d45786caff6d5c97a11f6d463afeb21820f5766a4d944c3e2f6a1418b83'
    'opensubtitles.py' = '3711dab1d40de9751d17cb3b5d9fbe485c644e6e2488b05e7d248cf5bb93a3f0'
    'owner_selected_file_resolver.py' = '93ab4f62eded98bfad3c3b8322536fe0547ee80ac0b206c24f735499577b4247'
    'trusted_playback_to_owner.py' = '7e8bb7d86d5395d9d3f40feb7ada3813cb7802d4e9995fc50607076728412c47'
    'p3_owner_current_redmi.py' = '69f4da5b2cdc94781b672c9858d4adf2b03837580d78045becf768ec42fb96a0'
    'owner_r2_verified_processor.py' = '24d653ebe39dcf73c4b80b6b93872cd3af4c1ee4a27973bbae5b4d21031e433f'
    'automatic_lean120_worker.py' = '4eb92f5d8e8ef6191cab8ac8d68df99ff1d791ae800607d3c8f01bd02fc707dd'
    'progressive_handoff.py' = '782b4ac8b7d993405bbab37a6e1e2109ff2250c5efefb1d0da3a1b035c954cf3'
}
$expected = [ordered]@{
    'agy_opensubtitles_acquisition.py' = '6ce182d5e9bd5de4b31827203cd967c752d97aea18bdce8a7630b8ed20950c84'
    'brain_english_inbox.py' = 'dab7cfe87bb134c6ee939b62e0ee2f14ca7cee1c3744317c52c12eef3dc1cf07'
}
$p2Names = @('automatic_lean120_worker.py','progressive_handoff.py')
function StageFile([string]$name) {
    if ($name -in $p2Names) {
        return (Join-Path $stage ('poc\p2-aisub\' + $name))
    }
    return (Join-Path $stage ('poc\p2-sub-discovery\' + $name))
}
function InstalledFile([string]$name) {
    if ($name -in $p2Names) { return (Join-Path $p2App $name) }
    return (Join-Path $app $name)
}
function Hold([string]$reason) {
    Write-Output ('OWNER_BRAIN_R3=HOLD_' + $reason)
    throw 'OWNER_BRAIN_R3_INSTALL_HOLD'
}
function Hash([string]$path) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function RegularDirectory([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Container) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'DIRECTORY_INVALID'
    }
}
function RegularFile([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'FILE_INVALID'
    }
}
function CheckTask {
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    $taskSid = [string]$task.Principal.UserId
    if ($taskSid -notmatch '^S-\d+(?:-\d+){2,}$') {
        $taskSid = ([Security.Principal.NTAccount]::new($taskSid).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    }
    if ($taskSid -cne $ownerSid -or
        [string]$task.Principal.LogonType -ine 'Interactive' -or
        @($task.Actions).Count -ne 1 -or
        [string]$task.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
        Hold 'OWNER_TASK_IDENTITY_DRIFT'
    }
    return $task
}
function Workers {
    return @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function NoOpenWork {
    $inbox = Join-Path $root 'inbox'
    RegularDirectory $inbox
    if (@(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json').Count -gt 0) {
        Hold 'PENDING_OWNER_EVENTS'
    }
    if (Test-Path -LiteralPath $p2) {
        RegularDirectory $p2
        foreach ($pattern in @('batch-*.inflight','active.lock')) {
            if (@(Get-ChildItem -LiteralPath $p2 -File -Recurse -Filter $pattern).Count -gt 0) {
                Hold 'P2_INFLIGHT_OR_ACTIVE_LOCK'
            }
        }
    }
}
function VerifiedHeartbeat([long]$rejectPid, [long]$freshSince) {
    if (-not (Test-Path -LiteralPath $healthPath -PathType Leaf)) { return $false }
    try {
        RegularFile $healthPath
        if ((Get-Item -LiteralPath $healthPath).Length -gt 512) { return $false }
        $h = Get-Content -LiteralPath $healthPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($h.schema -cne 'TTV-OWNER-AGENT-HEALTH-V1' -or
            $h.state -cne 'READY' -or $h.pid -isnot [ValueType] -or
            [long]$h.pid -le 0 -or [long]$h.pid -eq $rejectPid -or
            [long]$h.observed_utc_epoch -lt $freshSince) { return $false }
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$h.observed_utc_epoch
        if ($age -lt 0 -or $age -gt 20) { return $false }
        $worker = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$h.pid)
        if (-not $worker -or
            [string]$worker.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') {
            return $false
        }
        $sid = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
        return ($sid.ReturnValue -eq 0 -and $sid.Sid -ceq $ownerSid)
    } catch { return $false }
}
function StopOwner {
    NoOpenWork
    $task = CheckTask
    if ([string]$task.State -in @('Running','Ready')) {
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
        if ([string]$task.State -eq 'Running') {
            Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
        }
    } elseif ([string]$task.State -cne 'Disabled') { Hold 'OWNER_TASK_STATE_UNKNOWN' }
    for ($n = 0; $n -lt 5; $n++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    # Exactly scoped Owner-owned residual processes: never terminate other Python.
    $workers = @(Workers)
    if ($workers.Count -gt 4) { Hold 'RESIDUAL_WORKER_SET_UNEXPECTED' }
    $allowed = @((Join-Path $app 'owner_p3_p4_entrypoint.py'),
                 (Join-Path $app 'owner_session_bridge.py'))
    foreach ($w in $workers) {
        $hits = @($allowed | Where-Object {
            [string]$w.CommandLine -and
            $w.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        $sid = Invoke-CimMethod -InputObject $w -MethodName GetOwnerSid
        if ($hits.Count -ne 1 -or -not $w.CreationDate -or
            $sid.ReturnValue -ne 0 -or $sid.Sid -cne $ownerSid) {
            Hold 'RESIDUAL_IDENTITY_UNVERIFIED'
        }
    }
    foreach ($w in $workers) {
        NoOpenWork
        if ([string](CheckTask).State -cne 'Disabled') { Hold 'RESIDUAL_TASK_REENABLED' }
        $live = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$w.ProcessId)
        if ($null -eq $live) { continue }
        $sid = Invoke-CimMethod -InputObject $live -MethodName GetOwnerSid
        if ([string]$live.CommandLine -cne [string]$w.CommandLine -or
            $live.CreationDate -ne $w.CreationDate -or
            $sid.ReturnValue -ne 0 -or $sid.Sid -cne $ownerSid) {
            Hold 'RESIDUAL_CHANGED'
        }
        Stop-Process -Id ([int]$w.ProcessId) -Force -ErrorAction Stop
    }
    for ($n = 0; $n -lt 10; $n++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    Hold 'RESIDUAL_NOT_STOPPED'
}
function StartOwner([long]$oldPid) {
    $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 1
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($n = 0; $n -lt 30; $n++) {
        Start-Sleep -Seconds 1
        if ([string](CheckTask).State -cne 'Running') { continue }
        if (VerifiedHeartbeat $oldPid $since) { return $true }
    }
    return $false
}

# Select an active private LAN address, preferentially the route to the verified TV.
$p4 = Join-Path (Split-Path -Parent $root) 'P4'
$identityDir = Join-Path $root 'p4-identity'
$pkg = 'com.spacesarmat.omp.test'
$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
$tvSerial = ''
$tvReady = $false
$newPair = $false
$pairCommitted = $false
$tvStage = 'NOT_NEEDED'
$pairBackup = $null
$pairTargets = @()
$pairChanged = [System.Collections.Generic.List[object]]::new()
function PrivateIPv4([string]$value) {
    if ($value -notmatch '^(\d{1,3}\.){3}\d{1,3}$') { return $false }
    $parts = @($value.Split('.') | ForEach-Object { [int]$_ })
    if (@($parts | Where-Object { $_ -gt 255 }).Count -ne 0) { return $false }
    return ($parts[0] -eq 10 -or ($parts[0] -eq 172 -and $parts[1] -ge 16 -and $parts[1] -le 31) -or ($parts[0] -eq 192 -and $parts[1] -eq 168))
}
function ProbeTV {
    if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) { return }
    try {
        $devices = @(& $adb devices 2>$null)
        if ($LASTEXITCODE -ne 0) { return }
        $auth = @($devices | Where-Object { $_ -match '^\S+\s+device(?:\s|$)' })
        $denied = @($devices | Where-Object { $_ -match '^\S+\s+(offline|unauthorized)(?:\s|$)' })
        if ($auth.Count -ne 1 -or $denied.Count -ne 0) { return }
        $serial = ([string]$auth[0]).Trim().Split([char[]]@(' ',[char]9),[StringSplitOptions]::RemoveEmptyEntries)[0]
        foreach ($check in @(@('ro.product.model','MiTV-ASTR0'),@('ro.build.version.sdk','30'),@('ro.product.cpu.abi','armeabi-v7a'))) {
            $v = @(& $adb -s $serial shell getprop $check[0] 2>$null)
            if ($LASTEXITCODE -ne 0 -or $v.Count -ne 1 -or ([string]$v[0]).Trim() -cne $check[1]) { return }
        }
        $v = @(& $adb -s $serial shell run-as $pkg pwd 2>$null)
        if ($LASTEXITCODE -ne 0 -or $v.Count -ne 1) { return }
        $script:tvSerial = $serial
        $script:tvReady = $true
    } catch { return }
}
function PlanPair {
    RegularDirectory $p4
    RegularDirectory $identityDir
    foreach ($n in @('gateway-bind.txt','pairing-token.txt','pairing-key.hex','pc-cert.pem','pc-key.pem','adb-staged-v1.receipt')) { RegularFile (Join-Path $p4 $n) }
    foreach ($n in @('pc-cert.pem','pc-key.pem')) { RegularFile (Join-Path $identityDir $n) }
    $bind = [IO.File]::ReadAllText((Join-Path $p4 'gateway-bind.txt')).Trim()
    if ($bind -notmatch '^(\d{1,3}(?:\.\d{1,3}){3}):(\d{4,5})$') { Hold 'LAN_BIND_INVALID' }
    $oldIP = $Matches[1]; $port = [int]$Matches[2]
    if (-not (PrivateIPv4 $oldIP) -or $port -lt 1024 -or $port -gt 65535) { Hold 'LAN_BIND_INVALID' }
    $keyHex = [IO.File]::ReadAllText((Join-Path $p4 'pairing-key.hex')).Trim()
    $oldToken = [IO.File]::ReadAllText((Join-Path $p4 'pairing-token.txt')).Trim().Split('|')
    $oldCert = [Security.Cryptography.X509Certificates.X509Certificate2]::new((Join-Path $p4 'pc-cert.pem'))
    $oldPin = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($oldCert.RawData)).ToLowerInvariant()
    if ($keyHex -cnotmatch '^[a-f0-9]{64}$' -or $oldToken.Count -ne 3 -or $oldToken[0] -cne $bind -or $oldToken[1] -cne $keyHex -or $oldToken[2] -cne $oldPin) { Hold 'LAN_EXISTING_PAIR_INCONSISTENT' }
    foreach ($n in @('pc-cert.pem','pc-key.pem')) {
        if ((Hash (Join-Path $p4 $n)) -cne (Hash (Join-Path $identityDir $n))) { Hold 'LAN_EXISTING_IDENTITY_DRIFT' }
    }
    $preferred = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.AddressState -eq 'Preferred' -and (PrivateIPv4 $_.IPAddress) })
    if ($oldIP -in @($preferred.IPAddress) -and $oldCert.NotAfter -gt (Get-Date).AddDays(1)) {
        Write-Output 'OWNER_LAN=EXISTING_ENDPOINT_AVAILABLE'
        return
    }
    $chosen = @()
    if ($tvReady -and $tvSerial -match '^(\d{1,3}(?:\.\d{1,3}){3}):\d+$' -and (PrivateIPv4 $Matches[1])) {
        $remoteIP = $Matches[1]
        $route = @(Find-NetRoute -RemoteIPAddress $remoteIP -ErrorAction Stop)
        $local = @($route | Where-Object { $null -ne $_.PSObject.Properties['IPAddress'] } | ForEach-Object { [string]$_.IPAddress })
        $chosen = @($preferred | Where-Object { $_.IPAddress -in $local })
    }
    if ($chosen.Count -eq 0) {
        $nics = @(Get-NetIPConfiguration | Where-Object { $null -ne $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } | ForEach-Object { $_.InterfaceIndex })
        $chosen = @($preferred | Where-Object { $_.InterfaceIndex -in $nics -and -not $_.SkipAsSource })
    }
    if ($chosen.Count -ne 1) { Hold 'LAN_ADDRESS_AMBIGUOUS' }
    $newIP = [string]$chosen[0].IPAddress
    # No wildcard bind, network adapter or firewall change.
    $listeners = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object { $_.LocalPort -eq $port -and $_.LocalAddress -in @($newIP,'0.0.0.0','::') })
    if ($listeners.Count -ne 0) { Hold 'LAN_NEW_ENDPOINT_ALREADY_LISTENING' }
    $script:pairBackup = Join-Path $p4 ('rebind-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($pairBackup) | Out-Null
    $opensslCmd = Get-Command openssl.exe -ErrorAction SilentlyContinue
    $openssl = if ($null -ne $opensslCmd) { $opensslCmd.Source } else { 'C:\Program Files\Git\usr\bin\openssl.exe' }
    RegularFile $openssl
    $cert = Join-Path $pairBackup 'new-cert.pem'
    $key = Join-Path $pairBackup 'new-key.pem'
    $argsList = @('req','-x509','-newkey','rsa:3072','-sha256','-nodes','-days','30','-subj','/CN=TorrentTV-P4-DEV','-addext',('subjectAltName=IP:' + $newIP),'-keyout',$key,'-out',$cert)
    & $openssl @argsList 2> (Join-Path $pairBackup 'openssl-private.log') | Out-Null
    if ($LASTEXITCODE -ne 0) { Hold 'LAN_CERT_GENERATION_FAILED' }
    RegularFile $cert; RegularFile $key
    $san = @(& $openssl x509 -in $cert -noout -ext subjectAltName 2>$null) -join ' '
    if ($LASTEXITCODE -ne 0 -or $san -notmatch ('(?i)IP Address:\s*' + [regex]::Escape($newIP) + '(?=[,\s]|$)')) { Hold 'LAN_CERT_SAN_INVALID' }
    $certObj = [Security.Cryptography.X509Certificates.X509Certificate2]::new($cert)
    if ($certObj.NotBefore -gt (Get-Date) -or $certObj.NotAfter -le (Get-Date).AddDays(1)) { Hold 'LAN_CERT_VALIDITY_INVALID' }
    $pin = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($certObj.RawData)).ToLowerInvariant()
    $newBind = $newIP + ':' + $port
    $enc = [Text.UTF8Encoding]::new($false)
    $newBindPath = Join-Path $pairBackup 'new-bind.txt'
    $newTokenPath = Join-Path $pairBackup 'new-token.txt'
    [IO.File]::WriteAllText($newBindPath,$newBind,$enc)
    [IO.File]::WriteAllText($newTokenPath,($newBind + '|' + $keyHex + '|' + $pin),$enc)
    $script:pairTargets = @(
        @{name='p4-cert';dest=(Join-Path $p4 'pc-cert.pem');src=$cert},
        @{name='p4-key';dest=(Join-Path $p4 'pc-key.pem');src=$key},
        @{name='owner-cert';dest=(Join-Path $identityDir 'pc-cert.pem');src=$cert},
        @{name='owner-key';dest=(Join-Path $identityDir 'pc-key.pem');src=$key},
        @{name='bind';dest=(Join-Path $p4 'gateway-bind.txt');src=$newBindPath},
        @{name='token';dest=(Join-Path $p4 'pairing-token.txt');src=$newTokenPath}
    )
    foreach ($row in $pairTargets) {
        $row.old = Hash $row.dest
        $row.new = Hash $row.src
        $row.saved = Join-Path $pairBackup ('old-' + $row.name)
        [IO.File]::Copy($row.dest,$row.saved,$false)
        if ((Hash $row.saved) -cne $row.old) { Hold 'LAN_BACKUP_HASH_INVALID' }
    }
    $script:newPair = $true
    Write-Output 'OWNER_LAN=NEW_PRIVATE_ADDRESS_AND_CERT_PREPARED'
}
function RestorePairPartial {
    foreach ($row in $pairChanged) {
        if ((Hash $row.dest) -cne $row.new -or (Hash $row.saved) -cne $row.old) { Hold 'LAN_ROLLBACK_HASH_DRIFT' }
        $tmp = Join-Path (Split-Path -Parent $row.dest) ('.lan-rollback-' + [Guid]::NewGuid().ToString('N'))
        [IO.File]::Copy($row.saved,$tmp,$false)
        [IO.File]::Replace($tmp,$row.dest,(Join-Path $pairBackup ('failed-' + $row.name)))
        if ((Hash $row.dest) -cne $row.old) { Hold 'LAN_ROLLBACK_FAILED' }
    }
}
function ApplyPair {
    if (-not $newPair) { return }
    try {
        foreach ($row in $pairTargets) {
            NoOpenWork
            if ([string](CheckTask).State -cne 'Disabled' -or @(Workers).Count -ne 0) { Hold 'LAN_OWNER_NOT_STOPPED' }
            if ((Hash $row.dest) -cne $row.old -or (Hash $row.src) -cne $row.new) { Hold 'LAN_SOURCE_DRIFT' }
            $tmp = Join-Path (Split-Path -Parent $row.dest) ('.lan-new-' + [Guid]::NewGuid().ToString('N'))
            [IO.File]::Copy($row.src,$tmp,$false)
            [IO.File]::Replace($tmp,$row.dest,(Join-Path $pairBackup ('displaced-' + $row.name)))
            $pairChanged.Add($row)
            if ((Hash $row.dest) -cne $row.new) { Hold 'LAN_INSTALL_HASH_FAILED' }
        }
        $script:pairCommitted = $true
        Write-Output 'OWNER_LAN=PC_ENDPOINT_REBOUND'
    } catch {
        RestorePairPartial
        throw
    }
}
function StageTV {
    if (-not $newPair) { $script:tvStage = 'NOT_NEEDED'; return }
    if (-not $tvReady) { $script:tvStage = 'ADB_NOT_READY'; return }
    # Recheck the same authorized device immediately before its app-only change.
    $original = $tvSerial
    $script:tvReady = $false
    ProbeTV
    if (-not $tvReady -or $tvSerial -cne $original) { $script:tvStage = 'ADB_NOT_READY'; return }
    $nonce = [Guid]::NewGuid().ToString('N')
    $bootstrap = 'files/p4-owner-bootstrap-v1.txt'
    $prefs = 'shared_prefs/p4-tv-paired-pc-v2-tls.xml'
    $oldNames = @($prefs,($prefs + '.bak'),$bootstrap)
    $moved = [System.Collections.Generic.List[object]]::new()
    $wrote = $false
    try {
        & $adb -s $tvSerial shell am force-stop $pkg 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'LAN_TV_APP_STOP_FAILED' }
        foreach ($old in $oldNames) {
            & $adb -s $tvSerial shell run-as $pkg ls $old 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { continue }
            $saved = $old + '.pre-rebind-' + $nonce
            & $adb -s $tvSerial shell run-as $pkg mv $old $saved 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'LAN_TV_PAIR_BACKUP_FAILED' }
            $moved.Add(@{old=$old;saved=$saved})
        }
        $token = Join-Path $p4 'pairing-token.txt'
        $wrote = $true
        $proc = Start-Process -FilePath $adb -ArgumentList @('-s',$tvSerial,'shell','-T','run-as',$pkg,'dd',('of=' + $bootstrap)) -NoNewWindow -Wait -PassThru -RedirectStandardInput $token -RedirectStandardOutput (Join-Path $pairBackup 'adb-private-out.log') -RedirectStandardError (Join-Path $pairBackup 'adb-private-err.log') -ErrorAction Stop
        if ($proc.ExitCode -ne 0) { throw 'LAN_TV_TOKEN_STAGE_FAILED' }
        $hash = @(& $adb -s $tvSerial shell run-as $pkg sha256sum $bootstrap 2>$null)
        if ($LASTEXITCODE -ne 0 -or $hash.Count -ne 1 -or ([string]$hash[0]).Split(' ')[0] -cne (Hash $token)) { throw 'LAN_TV_TOKEN_VERIFY_FAILED' }
        $script:tvStage = 'STAGED_PENDING_PLAYER_IMPORT'
    } catch {
        $rollback = $true
        if ($wrote) {
            & $adb -s $tvSerial shell run-as $pkg mv $bootstrap ($bootstrap + '.failed-' + $nonce) 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { $rollback = $false }
        }
        foreach ($row in $moved) {
            & $adb -s $tvSerial shell run-as $pkg mv $row.saved $row.old 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { $rollback = $false }
        }
        $script:tvStage = if ($rollback) { 'STAGE_FAILED_ROLLED_BACK' } else { 'STAGE_FAILED_RECONCILE' }
    }
}
function PublishRepair {
    $spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
    $request = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
    if ($request.nonce -cnotmatch '^[0-9a-f]{32}$') { Hold 'LAN_RECEIPT_NONCE_INVALID' }
    $state = if ($pairCommitted) { 'REBIND_APPLIED' } else { 'EXISTING_ENDPOINT' }
    $record = @{schema='TTV-LAN-REBIND-RECEIPT-V1';nonce=$request.nonce;pc=$state;owner='READY_FRESH';modules='TWO_NEW_VERIFIED';tv=$tvStage}
    $dest = Join-Path $spool ('Receipts\lan-rebind-' + $request.nonce + '.json')
    [IO.File]::WriteAllText($dest,($record | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $ownerSid -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) {
    Hold 'INTERACTIVE_OWNER_REQUIRED'
}
foreach ($dir in @($root,$app,$p2App)) { RegularDirectory $dir }
$taskState = [string](CheckTask).State
if ($taskState -notin @('Running','Ready')) { Hold 'OWNER_TASK_NOT_RUNNING_OR_READY' }
NoOpenWork
$oldPid = 0L
if ($taskState -ceq 'Running') {
    if (-not (VerifiedHeartbeat -1 0)) { Hold 'OWNER_HEARTBEAT_NOT_VERIFIED' }
    $oldPid = [long](Get-Content -LiteralPath $healthPath -Raw | ConvertFrom-Json).pid
} else {
    # Ready can coexist with orphaned Python children. Validate their exact
    # Owner SID, app script path and creation identity before touching the task.
    $residual = @(Workers)
    if ($residual.Count -gt 4) { Hold 'RESIDUAL_WORKER_SET_UNEXPECTED' }
    $allowed = @((Join-Path $app 'owner_p3_p4_entrypoint.py'),
                 (Join-Path $app 'owner_session_bridge.py'))
    foreach ($w in $residual) {
        $hits = @($allowed | Where-Object {
            [string]$w.CommandLine -and
            $w.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        $sid = Invoke-CimMethod -InputObject $w -MethodName GetOwnerSid
        if ($hits.Count -ne 1 -or -not $w.CreationDate -or
            $sid.ReturnValue -ne 0 -or $sid.Sid -cne $ownerSid) {
            Hold 'RESIDUAL_IDENTITY_UNVERIFIED'
        }
    }
    if ($residual.Count -gt 0) {
        Write-Output 'OWNER_BRAIN_R3_READY_RESIDUAL=VERIFIED_CLEANUP_PLANNED'
    }
    # The existing StopOwner transaction rechecks idle state, disables the
    # task and revalidates each PID before stopping only these app workers.
}
# All 16 old R3 hashes must match, except the two files may already be the new target.
foreach ($name in $baseline.Keys) {
    $file = InstalledFile $name
    RegularFile $file
    $actual = Hash $file
    if ($actual -cne $baseline[$name] -and
        (-not $expected.Contains($name) -or $actual -cne $expected[$name])) {
        Hold 'INSTALLED_R3_BASELINE_DRIFT'
    }
}
$stageParent = Split-Path -Parent $stage
RegularDirectory $stageParent
[IO.Directory]::CreateDirectory((Join-Path $stage 'poc\p2-sub-discovery')) | Out-Null
RegularDirectory $stage
# Source-only transfer, pinned to the exact successful CI candidate.
foreach ($name in $expected.Keys) {
    $uri = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/31abfb233e0a3a84b7283c54dd1a7feb699fc8fd/poc/p2-sub-discovery/' + $name
    $target = StageFile $name
    Invoke-WebRequest -Uri $uri -OutFile $target -TimeoutSec 30 -ErrorAction Stop
    RegularFile $target
    if ((Hash $target) -cne $expected[$name]) { Hold 'PINNED_DOWNLOAD_HASH_DRIFT' }
}
Write-Output 'OWNER_BRAIN_SOURCE_NEUTRAL_STAGE=2_FILES_VERIFIED'

# Entrypoint is intentionally NOT part of the 16-file patch; the exact
# installed version is already the reviewed candidate and must stay so.
$entry = Join-Path $app 'owner_p3_p4_entrypoint.py'
RegularFile $entry
if ((Hash $entry) -cne 'acaa545be25d397b4ab85276516e92fdc99316f58063f69fcd620b8af0198c2c') {
    Hold 'INSTALLED_ENTRYPOINT_SHA_DRIFT'
}
foreach ($name in $expected.Keys) {
    $src = StageFile $name
    RegularFile $src
    if ((Hash $src) -cne $expected[$name]) { Hold 'STAGED_SOURCE_SHA_DRIFT' }
}
# Fail before touching the running Owner if staged modules cannot import
# against existing Owner dependencies. This is a smoke, not real provider/TV.
$overlay = @'
import importlib, pathlib, sys
stage, app = (pathlib.Path(p) for p in sys.argv[1:3])
sys.path[:0] = [str(stage / "poc/p2-sub-discovery"),
                str(app / "poc/p2-sub-discovery"),
                str(app / "poc/p2-aisub"),
                str(app / "poc/p3-vietsub-trigger")]
for name in ("brain_english_inbox", "agy_opensubtitles_acquisition",
             "automatic_vietsub_flow", "owner_p3_p4_entrypoint"):
    module = importlib.import_module(name)
    expected_root = stage if name in ("brain_english_inbox", "agy_opensubtitles_acquisition") else app
    assert pathlib.Path(module.__file__).resolve().is_relative_to(expected_root.resolve()), name
from agy_opensubtitles_acquisition import _validate_source, AgyEnglishUnavailable
from matcher import Media
media = Media("personal", "a" * 40, 2, "Example.Film.2017.1080p.BluRay.x265-GRP.mkv")
for source in ("https://subdl.com/s/example", "local SRT", ""):
    _validate_source(media, {"release_name": "Example.Film.2017.1080p.BluRay.x265-GRP_eng.srt",
                             "source_page": source})
try:
    _validate_source(media, {"release_name": "Another.Film.2017.1080p.BluRay.x265-GRP.srt",
                             "source_page": "https://subdl.com/s/example"})
except AgyEnglishUnavailable as exc:
    assert str(exc) == "AGY_EN_MEDIA_RELEASE_MISMATCH"
else:
    raise AssertionError("wrong release accepted")
print("OWNER_BRAIN_R3_STAGED_OVERLAY=PASS")
'@
$import = @(& py -3 -I -B -c $overlay $stage (Join-Path $root 'app') $cache $p2 2>&1)
if ($LASTEXITCODE -ne 0 -or
    @($import | Where-Object { [string]$_ -ceq 'OWNER_BRAIN_R3_STAGED_OVERLAY=PASS' }).Count -ne 1) {
    Hold 'STAGED_OVERLAY_IMPORT_FAILED_OWNER_UNCHANGED'
}
Write-Output 'OWNER_BRAIN_R3_PREFLIGHT=PASS_OWNER_IDLE_STAGED_IMPORT'

if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
    [IO.Directory]::CreateDirectory($backupRoot) | Out-Null
}
RegularDirectory $backupRoot
$backup = Join-Path $backupRoot ('owner-brain-source-neutral-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($backup) | Out-Null
$previous = [ordered]@{}
foreach ($name in $expected.Keys) {
    $file = InstalledFile $name
    if (Test-Path -LiteralPath $file) {
        RegularFile $file
        $previous[$name] = Hash $file
        $saved = Join-Path $backup $name
        [IO.File]::Copy($file,$saved,$false)
        if ((Hash $saved) -cne $previous[$name]) { Hold 'BACKUP_HASH_INVALID' }
    } else { $previous[$name] = 'MISSING' }
}
$ledger = [ordered]@{
    schema = 'TTV-OWNER-BRAIN-R3-BACKUP-V1'
    candidate_sha = '31abfb233e0a3a84b7283c54dd1a7feb699fc8fd'
    stage_sha = '31abfb233e0a3a84b7283c54dd1a7feb699fc8fd'
    previous = $previous
    target = $expected
}
[IO.File]::WriteAllText((Join-Path $backup 'ledger.json'),
    ($ledger | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
Write-Output 'OWNER_BRAIN_R3_BACKUP=2_ORIGINALS_RECORDED'
ProbeTV
PlanPair
$stopped = $false
try {
    NoOpenWork
    StopOwner
    $stopped = $true
    NoOpenWork
    ApplyPair
    foreach ($name in $expected.Keys) {
        if ([string](CheckTask).State -cne 'Disabled' -or @(Workers).Count -ne 0) {
            Hold 'OWNER_NOT_STOPPED_DURING_APPLY'
        }
        $src = StageFile $name
        $file = InstalledFile $name
        if ((Hash $src) -cne $expected[$name]) { Hold 'SOURCE_CHANGED_DURING_APPLY' }
        if ($previous[$name] -ceq 'MISSING') {
            if (Test-Path -LiteralPath $file) { Hold 'NEW_MODULE_PATH_CONFLICT' }
        } elseif ((Hash $file) -cne $previous[$name]) {
            Hold 'INSTALLED_BASELINE_CHANGED'
        }
        if ($previous[$name] -ceq $expected[$name]) { continue }
        $temp = Join-Path (Split-Path -Parent $file) ('.brain-r3-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::Copy($src,$temp,$false)
        if ((Hash $temp) -cne $expected[$name]) { Hold 'TEMP_COPY_DRIFT' }
        if ($previous[$name] -ceq 'MISSING') {
            [IO.File]::Move($temp,$file)
        } else {
            $displaced = Join-Path $backup ('displaced-' + $name)
            [IO.File]::Replace($temp,$file,$displaced)
        }
        if ((Hash $file) -cne $expected[$name]) { Hold 'POST_REPLACE_HASH_CHANGED' }
    }
    Push-Location -LiteralPath $app
    try {
        $installedCheck = 'import sys;sys.path.insert(0,sys.argv[1]);import owner_p3_p4_entrypoint,brain_english_inbox,agy_opensubtitles_acquisition;print("OWNER_BRAIN_R3_IMPORT_PASS")'
        $verify = @(& py -3 -I -B -c $installedCheck $app 2>&1)
        if ($LASTEXITCODE -ne 0 -or
            @($verify | Where-Object { [string]$_ -ceq 'OWNER_BRAIN_R3_IMPORT_PASS' }).Count -ne 1) {
            Hold 'OFFLINE_IMPORT_FAILED'
        }
    } finally { Pop-Location }
    NoOpenWork
    if (-not (StartOwner $oldPid)) { Hold 'FRESH_OWNER_NOT_VERIFIED' }
    Write-Output 'OWNER_BRAIN_SOURCE_NEUTRAL_INSTALL=2_FILES_HASH_VERIFIED_FRESH_OWNER_RUNNING'
    Write-Output 'OWNER_BRAIN_R3_PROVIDER=NOT_RUN'
    Write-Output 'OWNER_BRAIN_R3_CACHE_CHECKPOINTS=UNCHANGED'
} catch {
    $failure = $_
    Write-Output 'OWNER_BRAIN_R3_RECOVERY=ATTEMPTING_PRIVATE_ROLLBACK'
    if (-not $stopped) {
        # No source files were changed. Restore availability only if the
        # previous owner worker has exited and the queue remains untouched.
        if (@(Workers).Count -eq 0 -and
            [string](CheckTask).State -ceq 'Disabled') {
            NoOpenWork
            if (StartOwner $oldPid) {
                Write-Output 'OWNER_BRAIN_R3_RECOVERY=NO_FILES_CHANGED_OLD_OWNER_RUNNING'
            }
        }
        throw
    }
    StopOwner
    foreach ($name in $expected.Keys) {
        $file = InstalledFile $name
        $old = [string]$previous[$name]
        $new = [string]$expected[$name]
        if ($old -ceq $new) { continue }
        if ($old -ceq 'MISSING') {
            if (Test-Path -LiteralPath $file) {
                if ((Hash $file) -cne $new) { Hold 'ROLLBACK_NEW_FILE_DRIFT' }
                [IO.File]::Delete($file)
            }
        } else {
            $saved = Join-Path $backup $name
            if ((Hash $saved) -cne $old) { Hold 'ROLLBACK_BACKUP_DRIFT' }
            if ((Hash $file) -cne $old) {
                if ((Hash $file) -cne $new) { Hold 'ROLLBACK_INSTALLED_DRIFT' }
                $temp = Join-Path (Split-Path -Parent $file) ('.brain-rollback-' + [Guid]::NewGuid().ToString('N') + '.tmp')
                [IO.File]::Copy($saved,$temp,$false)
                $displaced = Join-Path $backup ('failed-' + $name)
                [IO.File]::Replace($temp,$file,$displaced)
            }
            if ((Hash $file) -cne $old) { Hold 'ROLLBACK_ORIGINAL_HASH_CHANGED' }
        }
    }
    if (-not (StartOwner $oldPid)) { Hold 'ROLLBACK_OWNER_HEARTBEAT_FAILED_TASK_HOLD' }
    Write-Output 'OWNER_BRAIN_R3_RECOVERY=ORIGINAL_OWNER_RESTORED'
    throw 'OWNER_BRAIN_R3_INSTALL_FAILED_ROLLED_BACK'
}

# Owner has a verified fresh PID and both module hashes before the TV-only handoff.
StageTV
PublishRepair
