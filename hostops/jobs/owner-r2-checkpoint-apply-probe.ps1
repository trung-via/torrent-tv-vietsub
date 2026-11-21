# Read-only Windows runner probe after the single Owner checkpoint apply task.
# No private profile access, process stop, task start, provider or TV actions.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) {
    & pwsh.exe -NoLogo -NoProfile -NonInteractive -File $PSCommandPath
    exit $LASTEXITCODE
}
Write-Output ('HOSTOPS_CHECKPOINT_PROBE_PWSH_MAJOR=' + $PSVersionTable.PSVersion.Major)
$installName = 'TorrentTV-Vietsub-Owner-R2-Checkpoint-Apply'
$ownerName = 'TorrentTV-Vietsub-OwnerAgent'
$receiptPath = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\ReleaseReceipts\checkpoint-apply.json'
function Hold([string]$code) { throw ('HOSTOPS_CHECKPOINT_PROBE_HOLD_' + $code) }
function ShowTask([string]$name,[string]$prefix) {
    $task = Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop
    $info = Get-ScheduledTaskInfo -TaskName $name -TaskPath '\' -ErrorAction Stop
    $state = [string]$task.State
    if ($state -notin @('Running','Ready','Disabled','Queued','Unknown')) {
        Hold 'UNEXPECTED_TASK_STATE'
    }
    Write-Output ($prefix + '_STATE=' + $state.ToUpperInvariant())
    $code = [long]$info.LastTaskResult
    Write-Output ($prefix + '_LAST_RESULT=' + $code)
    if ($info.LastRunTime -ge [datetime]'2000-01-01') {
        $utc = [DateTimeOffset]::new($info.LastRunTime.ToUniversalTime())
        Write-Output ($prefix + '_LAST_RUN_UTC_EPOCH=' + $utc.ToUnixTimeSeconds())
    } else {
        Write-Output ($prefix + '_LAST_RUN_UTC_EPOCH=NEVER')
    }
}
ShowTask $ownerName 'HOSTOPS_CHECKPOINT_PROBE_OWNER'
ShowTask $installName 'HOSTOPS_CHECKPOINT_PROBE_INSTALL_TASK'

if (-not (Test-Path -LiteralPath $receiptPath)) {
    Write-Output 'HOSTOPS_CHECKPOINT_PROBE_RECEIPT=ABSENT'
} else {
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf) -or
        ((Get-Item -LiteralPath $receiptPath -Force).Attributes -band
            [IO.FileAttributes]::ReparsePoint) -or
        (Get-Item -LiteralPath $receiptPath).Length -gt 1024) {
        Hold 'RECEIPT_NOT_REGULAR_SMALL_FILE'
    }
    $r = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@($r.PSObject.Properties.Name | Sort-Object) -join ',' -cne
        'observed_utc_epoch,release_id,result,schema,stage_commit' -or
        $r.schema -cne 'TTV-OWNER-CHECKPOINT-APPLY-V1' -or
        $r.release_id -cne 'r2-checkpoint-175' -or
        $r.stage_commit -cne '5ab8a2dd6e09c2eeef83b473e82b2ff4c758e961' -or
        $r.observed_utc_epoch -isnot [ValueType] -or
        [string]$r.result -notin @(
            'STARTED_OWNER_STOP_P2_STATE_PRESERVED',
            'INSTALLED_OWNER_FRESH_P2_STATE_PRESERVED',
            'ROLLED_BACK_OLD_OWNER_FRESH',
            'HOLD_OWNER_DISABLED_OR_RECOVERY_UNVERIFIED')) {
        Hold 'RECEIPT_SCHEMA_INVALID'
    }
    Write-Output ('HOSTOPS_CHECKPOINT_PROBE_RECEIPT=' + [string]$r.result)
    Write-Output ('HOSTOPS_CHECKPOINT_PROBE_RECEIPT_EPOCH=' + [long]$r.observed_utc_epoch)
}
Write-Output 'HOSTOPS_CHECKPOINT_PROBE_MODE=READ_ONLY'
Write-Output 'HOSTOPS_CHECKPOINT_PROBE_OWNER_PRIVATE_FILES=NOT_ACCESSED'
Write-Output 'HOSTOPS_CHECKPOINT_PROBE_PROVIDER_TV=NOT_RUN'
