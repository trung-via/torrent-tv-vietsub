# ONE trusted owner laptop -> ONE preapproved Redmi via authenticated ADB.
# Local owner invocation only; no token on TV, no log of key or serial.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -eq 'true' -or $env:CI -eq 'true' -or $env:TF_BUILD) {
  throw 'P4_ADB_BOOTSTRAP_STOP_CI_FORBIDDEN'
}
if (-not $env:LOCALAPPDATA) {throw 'P4_ADB_BOOTSTRAP_STOP_OWNER_PROFILE'}
$folder=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P4'
$pair=Join-Path $folder 'pairing-token.txt'
$receipt=Join-Path $folder 'adb-staged-v1.receipt'
if (Test-Path -LiteralPath $receipt -PathType Leaf) {
  Write-Host 'P4_ONE_OWNER_PC_ALREADY_STAGED=true'
  $global:LASTEXITCODE=0
  return
}
if (-not (Test-Path -LiteralPath $pair -PathType Leaf) -or
    (Get-Item -LiteralPath $pair).Length -notin 130..240) {
  throw 'P4_ADB_BOOTSTRAP_STOP_OWNER_TOKEN_NOT_READY'
}
$adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
  throw 'P4_ADB_BOOTSTRAP_STOP_PINNED_ADB_MISSING'
}
$devices=@(& $adb devices)
if ($LASTEXITCODE -ne 0) {throw 'P4_ADB_BOOTSTRAP_STOP_LIST_FAILED'}
$auth=@($devices | Where-Object { $_ -match '^[^\s]+\s+device(\s|$)' })
$unauth=@($devices | Where-Object { $_ -match '^[^\s]+\s+(unauthorized|offline)(\s|$)' })
if ($auth.Count -ne 1 -or $unauth.Count -gt 0) {
  throw 'P4_ADB_BOOTSTRAP_STOP_SINGLE_AUTHORIZED_REDMi_REQUIRED'
}
$serial=(([string]$auth[0]).Trim() -split '\s+')[0]
$props=@{}
foreach ($name in @('ro.product.model','ro.build.version.sdk','ro.product.cpu.abi')) {
  $lines=@(& $adb -s $serial shell getprop $name)
  if ($LASTEXITCODE -ne 0 -or $lines.Count -ne 1) {
    throw 'P4_ADB_BOOTSTRAP_STOP_TV_IDENTITY_UNAVAILABLE'
  }
  $props[$name]=([string]$lines[0]).Trim()
}
if ($props['ro.product.model'] -cne 'MiTV-ASTR0' -or
    $props['ro.build.version.sdk'] -cne '30' -or
    $props['ro.product.cpu.abi'] -cne 'armeabi-v7a') {
  throw 'P4_ADB_BOOTSTRAP_STOP_WRONG_TV'
}
$pkg='com.spacesarmat.omp.test'
$pm=@(& $adb -s $serial shell pm path $pkg)
if ($LASTEXITCODE -ne 0 -or
    @($pm | Where-Object { ([string]$_).Trim() -match '^package:/[^\s]+/base\.apk$' }).Count -ne 1) {
  throw 'P4_ADB_BOOTSTRAP_STOP_DEBUG_APP_NOT_INSTALLED'
}
$proof=@(& $adb -s $serial shell run-as $pkg pwd 2>$null)
if ($LASTEXITCODE -ne 0 -or $proof.Count -ne 1) {
  throw 'P4_ADB_BOOTSTRAP_STOP_DEBUG_RUN_AS_REQUIRED'
}
$stdout=Join-Path $folder 'adb-stdout.tmp'
$stderr=Join-Path $folder 'adb-stderr.tmp'
foreach ($f in @($stdout,$stderr)) {
  if (Test-Path -LiteralPath $f) {throw 'P4_ADB_BOOTSTRAP_STOP_TEMP_COLLISION'}
}
try {
  # dd receives bytes on stdin; no secret in CLI arguments or stdout.
  $proc=Start-Process -FilePath $adb -ArgumentList @(
    '-s',$serial,'shell','-T','run-as',$pkg,'dd',
    'of=files/p4-owner-bootstrap-v1.txt'
  ) -NoNewWindow -Wait -PassThru -RedirectStandardInput $pair -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
  if ($proc.ExitCode -ne 0) {throw 'P4_ADB_BOOTSTRAP_STOP_PRIVATE_STREAM_FAILED'}
  [IO.File]::WriteAllText($receipt,'staged',(
    New-Object System.Text.UTF8Encoding($false)))
  Write-Host 'P4_SINGLE_OWNER_LAPTOP_PRIVATE_BOOTSTRAP_STAGED=true'
  Write-Host 'P4_NO_TV_TOKEN_INPUT_NO_SECRET_LOGGING=true'
  Write-Host 'P4_KEYSTORE_IMPORT_PENDING_NEXT_PLAYER_LOAD=true'
} finally {
  foreach ($f in @($stdout,$stderr)) {
    Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
  }
}
$global:LASTEXITCODE=0
