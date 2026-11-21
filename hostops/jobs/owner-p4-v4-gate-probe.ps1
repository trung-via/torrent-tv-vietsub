# Read-only: explain the exact Owner V4 -> Redmi install gate.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSVersion.Major -lt 7 -or
    $env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne 'S-1-5-20') {
    throw 'P4_V4_GATE_PROBE_WRONG_RUNNER'
}
$task=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\' -ErrorAction Stop
Write-Output ('P4_GATE_OWNER_TASK=' + [string]$task.State)
$file=Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\Diagnostics\owner-snapshot.json'
$item=Get-Item -LiteralPath $file -Force -ErrorAction Stop
if ($item.Length -lt 1 -or $item.Length -gt 4096 -or
    ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'P4_GATE_SNAPSHOT_UNTRUSTED'
}
$s=Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
$age=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-[long]$s.snapshot_utc_epoch
$schema=if($s.schema -ceq 'TTV-HOSTOPS-OWNER-SNAPSHOT-V4'){'V4'}else{'OTHER'}
Write-Output ('P4_GATE_SCHEMA=' + $schema)
Write-Output ('P4_GATE_STATUS=' + [string]$s.status)
Write-Output ('P4_GATE_AGE_SECONDS=' + $age)
Write-Output ('P4_GATE_P3=' + [string]$s.p3_state)
Write-Output ('P4_GATE_P2=' + [string]$s.p2.status)
Write-Output ('P4_GATE_P2_PENDING=' + [long]$s.p2.pending_events)
Write-Output ('P4_GATE_P2_INFLIGHT=' + [long]$s.p2.inflight_count)
$adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    Write-Output 'P4_GATE_ADB=NOT_AVAILABLE'; return
}
$devices=@(& $adb devices 2>$null)
if ($LASTEXITCODE -ne 0) {throw 'P4_GATE_ADB_DEVICE_QUERY_FAILED'}
$found=@($devices|Where-Object {$_ -match '^[^\s]+\s+device(\s|$)'})
if ($found.Count -ne 1) {Write-Output 'P4_GATE_TV=NOT_EXACT_ONE';return}
$serial=($found[0].Trim() -split '\s+')[0]
$model=@(& $adb -s $serial shell getprop ro.product.model 2>$null)
if ($LASTEXITCODE -ne 0 -or $model.Count -ne 1 -or $model[0].Trim() -cne 'MiTV-ASTR0') {
    Write-Output 'P4_GATE_TV=NOT_VERIFIED_REDMi';return
}
$running=@(& $adb -s $serial shell pidof com.spacesarmat.omp.test 2>$null)
if ($LASTEXITCODE -eq 1 -and $running.Count -eq 0) {
    Write-Output 'P4_GATE_OMP_PROCESS=NOT_RUNNING'
} elseif($LASTEXITCODE -eq 0 -and $running.Count -eq 1) {
    Write-Output 'P4_GATE_OMP_PROCESS=RUNNING'
} else {
    Write-Output 'P4_GATE_OMP_PROCESS=UNKNOWN'
}
Write-Output 'P4_GATE_DEVICE_WRITE=NOT_RUN'
