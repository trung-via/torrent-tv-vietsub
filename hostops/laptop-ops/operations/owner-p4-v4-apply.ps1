# Single-use Owner-interactive maintenance operation, explicitly authorized for
# the P4 PR #178 rollout. No provider calls, P2 clear/retry or TV APK install.
# The owner maintenance helper independently backs up 23 modules and restores
# the old Owner if its fresh heartbeat cannot be verified.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pkg = 'com.spacesarmat.omp.test'
$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
$installerCommit = '6d575817fbd8896b23bad68d639eab054489b625'
$installerSha256 = '7bde90d1cc6d1118e5c65beece13db4df00ea6992761845817e9fb5cd7f0f478'
$snapshotPath = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\Diagnostics\owner-snapshot.json'
$ownerTask = 'TorrentTV-Vietsub-OwnerAgent'

function Hold([string]$reason) {
    Write-Output ('OWNER_P4_V4_OPERATION=HOLD_' + $reason)
    throw 'OWNER_P4_V4_OPERATION_STOPPED_NO_RETRY'
}
function VerifiedSnapshot {
    if (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) { Hold 'SNAPSHOT_MISSING' }
    $item = Get-Item -LiteralPath $snapshotPath -Force
    if ($item.Length -le 0 -or $item.Length -gt 4096 -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { Hold 'SNAPSHOT_UNTRUSTED' }
    $r = Get-Content -LiteralPath $snapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$r.snapshot_utc_epoch
    if ($r.schema -cnotin @('TTV-HOSTOPS-OWNER-SNAPSHOT-V3','TTV-HOSTOPS-OWNER-SNAPSHOT-V4') -or
        $r.status -cne 'READY_FRESH' -or $r.mode -cne 'INTEGRATED_P3_P4' -or
        $age -lt 0 -or $age -gt 10 -or
        $r.p3_state -cnotin @('FRESH_OFF','STALE') -or
        [string]$r.p2.status -cne 'CLEAR' -or
        [long]$r.p2.pending_events -ne 0 -or [long]$r.p2.inflight_count -ne 0) {
        Hold 'OWNER_P2_OR_TV_NOT_IDLE'
    }
    $task = Get-ScheduledTask -TaskName $ownerTask -TaskPath '\' -ErrorAction Stop
    if ([string]$task.State -cne 'Running' -or
        [string]$task.Principal.LogonType -ine 'Interactive' -or
        @($task.Actions).Count -ne 1 -or
        [string]$task.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
        Hold 'OWNER_TASK_NOT_RUNNING_OR_DRIFT'
    }
}
function Tv([string[]]$argv) {
    $lines = @(& $adb @argv 2>$null)
    if ($LASTEXITCODE -ne 0) { Hold 'ADB_COMMAND_FAILED' }
    return @($lines)
}
function TvProperty([string]$serial,[string]$property) {
    $lines = @(Tv -argv @('-s',$serial,'shell','getprop',$property))
    if ($lines.Count -ne 1) { Hold 'DEVICE_PROPERTY_UNKNOWN' }
    return ([string]$lines[0]).Trim()
}
function TvRunning([string]$serial) {
    # Android pidof returns exit 1 when the package has no process.
    $lines = @(& $adb -s $serial shell pidof $pkg 2>$null)
    if ($LASTEXITCODE -notin @(0,1) -or $lines.Count -gt 1) { Hold 'TV_PROCESS_UNVERIFIABLE' }
    if ($LASTEXITCODE -eq 1 -and $lines.Count -ne 0) { Hold 'TV_PROCESS_RESPONSE_INVALID' }
    return ($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and
            ([string]$lines[0]).Trim() -match '^\d+( \d+)*$')
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ($PSVersionTable.PSVersion.Major -lt 7 -or $env:GITHUB_ACTIONS -ceq 'true' -or
    -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) {
    Hold 'INTERACTIVE_OWNER_PWSH7_REQUIRED'
}
VerifiedSnapshot
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) { Hold 'ADB_NOT_INSTALLED' }
if (@(Get-Process -Name adb -ErrorAction SilentlyContinue).Count -eq 0) { Hold 'ADB_NOT_RUNNING' }
$devices = @(Tv -argv @('devices'))
$authorized = @($devices | Where-Object { $_ -match '^[^\s]+\s+device(\s|$)' })
$unexpected = @($devices | Where-Object { $_ -match '^[^\s]+\s+(offline|unauthorized)(\s|$)' })
if ($authorized.Count -ne 1 -or $unexpected.Count -ne 0) { Hold 'EXACTLY_ONE_ADB_TV_REQUIRED' }
$serial = ([string]$authorized[0]).Trim() -split '\s+' | Select-Object -First 1
if ((TvProperty $serial 'ro.product.model') -cne 'MiTV-ASTR0' -or
    (TvProperty $serial 'ro.product.cpu.abi') -cne 'armeabi-v7a' -or
    (TvProperty $serial 'ro.build.version.sdk') -cne '30') { Hold 'TV_IDENTITY_MISMATCH' }
$paths = @(Tv -argv @('-s',$serial,'shell','pm','path',$pkg))
if (@($paths | Where-Object { $_ -match '^package:/[^\s]+/base\.apk$' }).Count -ne 1) {
    Hold 'OMP_PACKAGE_NOT_VERIFIED'
}

# Acquire the audited offline Owner installer before touching the TV.
$download = Join-Path $env:TEMP ('ttv-owner-p4-v4-' + [Guid]::NewGuid().ToString('N') + '.ps1')
try {
    $uri = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' +
        $installerCommit + '/hostops/setup/owner-p4-v4-maintenance-once.ps1'
    Invoke-WebRequest -Uri $uri -OutFile $download -ErrorAction Stop
    $item = Get-Item -LiteralPath $download -Force
    if ($item.Length -le 0 -or $item.Length -gt 65536 -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        (Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant() -cne
            $installerSha256) { Hold 'INSTALLER_HASH_DRIFT' }
    VerifiedSnapshot
    # User authorized stopping OMP for the install; nothing else is stopped.
    [void](Tv -argv @('-s',$serial,'shell','am','force-stop',$pkg))
    if (TvRunning $serial) { Hold 'TV_OMP_STILL_RUNNING' }
    Write-Output 'OWNER_P4_V4_OPERATION=REDMI_OMP_STOPPED_VERIFIED'
    $inspect = @(& pwsh -NoLogo -NoProfile -NonInteractive -File $download -ViewerOffConfirmed)
    if ($LASTEXITCODE -ne 0 -or
        @($inspect | Where-Object { $_ -ceq 'OWNER_P4_V4=READ_ONLY_INSPECT_PASS' }).Count -ne 1) {
        Hold 'INSTALLER_PREFLIGHT_FAILED'
    }
    VerifiedSnapshot
    if (TvRunning $serial) { Hold 'TV_OMP_RESTARTED' }
    $apply = @(& pwsh -NoLogo -NoProfile -NonInteractive -File $download -Apply -ViewerOffConfirmed)
    if ($LASTEXITCODE -ne 0 -or
        @($apply | Where-Object { $_ -ceq 'OWNER_P4_V4=APPLIED_23_NEW_OWNER_HEALTH_VERIFIED' }).Count -ne 1 -or
        @($apply | Where-Object { $_ -ceq 'OWNER_P4_V4_P2_CHECKPOINTS=UNCHANGED' }).Count -ne 1) {
        Hold 'OWNER_APPLY_OR_HEALTH_FAILED_NO_RETRY'
    }
    Write-Output 'OWNER_P4_V4_OPERATION=APPLIED_OWNER_NEW_HEALTH_VERIFIED'
    Write-Output 'OWNER_P4_V4_OPERATION=TV_APK_NOT_YET_INSTALLED'
} finally {
    if (Test-Path -LiteralPath $download -PathType Leaf) {
        Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue
    }
}
