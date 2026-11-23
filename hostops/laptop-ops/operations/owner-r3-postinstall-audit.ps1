# One-shot, Owner-context, read-only audit of the 16 modules installed by R3.
# No Owner restart, provider call, TorrServer request, media disclosure, or cache mutation.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $ownerSid -in @('S-1-5-18','S-1-5-19','S-1-5-20')) {
    throw 'OWNER_R3_AUDIT_INTERACTIVE_OWNER_REQUIRED'
}
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$base = Join-Path $root 'app\poc'
$sub = Join-Path $base 'p2-sub-discovery'
$aisub = Join-Path $base 'p2-aisub'
$expected = [ordered]@{
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
$p2Names = @('automatic_lean120_worker.py','progressive_handoff.py')
$matched = 0
foreach ($name in $expected.Keys) {
    $dir = if ($name -in $p2Names) { $aisub } else { $sub }
    $file = Join-Path $dir $name
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'OWNER_R3_AUDIT_MODULE_MISSING' }
    $item = Get-Item -LiteralPath $file -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'OWNER_R3_AUDIT_REPARSE_BLOCKED' }
    $digest = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($digest -cne [string]$expected[$name]) { throw 'OWNER_R3_AUDIT_MODULE_HASH_DRIFT' }
    $matched++
}
if ($matched -ne 16) { throw 'OWNER_R3_AUDIT_MODULE_COUNT_INVALID' }
$task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\' -ErrorAction Stop
if ([string]$task.State -cne 'Running') { throw 'OWNER_R3_AUDIT_TASK_NOT_RUNNING' }
$healthPath = Join-Path $root 'agent-health.json'
if (-not (Test-Path -LiteralPath $healthPath -PathType Leaf)) { throw 'OWNER_R3_AUDIT_HEALTH_MISSING' }
$health = Get-Content -LiteralPath $healthPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($health.schema -cne 'TTV-OWNER-AGENT-HEALTH-V1' -or $health.state -cne 'READY') {
    throw 'OWNER_R3_AUDIT_HEALTH_INVALID'
}
$age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$health.observed_utc_epoch
if ($age -lt 0 -or $age -gt 20 -or [long]$health.pid -le 0) {
    throw 'OWNER_R3_AUDIT_HEALTH_STALE'
}
$proc = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$health.pid) -ErrorAction Stop
if (-not $proc -or [string]$proc.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') {
    throw 'OWNER_R3_AUDIT_PID_NOT_BOUND'
}
$procOwner = Invoke-CimMethod -InputObject $proc -MethodName GetOwnerSid
if ($procOwner.ReturnValue -ne 0 -or $procOwner.Sid -cne $ownerSid) {
    throw 'OWNER_R3_AUDIT_OWNER_IDENTITY_MISMATCH'
}
Write-Output 'OWNER_R3_POSTINSTALL_AUDIT=PASS'
Write-Output 'OWNER_R3_MODULE_HASH_MATCH=16_OF_16'
Write-Output 'OWNER_R3_TASK=RUNNING'
Write-Output 'OWNER_R3_HEARTBEAT=FRESH_PID_BOUND'
Write-Output 'OWNER_R3_PROVIDER_OR_TV=NOT_RUN'
