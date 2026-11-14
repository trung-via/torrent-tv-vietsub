# Owner-local foreground P4 synthetic HTTPS gateway. Never used by CI.
# Requires prior prepare_p4_owner_pc.ps1; never asks for a media key,
# and explicit approval to open only the selected trusted LAN interface.
# NO firewall/router/service changes, no Gemini API or real subtitles.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -eq 'true' -or $env:CI -eq 'true' -or $env:TF_BUILD) {
  throw 'P4_MOCK_GATEWAY_STOP_CI_NOT_ALLOWED'
}
if (-not $env:LOCALAPPDATA) {throw 'P4_MOCK_GATEWAY_STOP_NO_LOCALAPPDATA'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P4'
$keyFile=Join-Path $root 'pairing-key.hex'
$bindFile=Join-Path $root 'gateway-bind.txt'
$cert=Join-Path $root 'pc-cert.pem'
$private=Join-Path $root 'pc-key.pem'
foreach ($f in @($keyFile,$bindFile,$cert,$private)) {
  if (-not (Test-Path -LiteralPath $f -PathType Leaf)) {
    throw 'P4_MOCK_GATEWAY_STOP_OWNER_PAIRING_NOT_READY'
  }
}
$key=(Get-Content -LiteralPath $keyFile -Raw).Trim()
if ($key -notmatch '^[a-f0-9]{64}$') {throw 'P4_MOCK_GATEWAY_STOP_INVALID_KEY'}
$binding=(Get-Content -LiteralPath $bindFile -Raw).Trim()
if ($binding -notmatch '^(10\.(?:[0-9]{1,3}\.){2}[0-9]{1,3}|172\.(?:1[6-9]|2[0-9]|3[01])\.(?:[0-9]{1,3}\.)[0-9]{1,3}|192\.168\.(?:[0-9]{1,3}\.)[0-9]{1,3}):([0-9]{4,5})$') {
  throw 'P4_MOCK_GATEWAY_STOP_INVALID_BIND'
}
$ip=$Matches[1]
$port=[int]$Matches[2]
if ($port -lt 1024 -or $port -gt 65535) {throw 'P4_MOCK_GATEWAY_STOP_INVALID_PORT'}
$ifs=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
  Where-Object { $_.IPAddress -ceq $ip -and $_.AddressState -eq 'Preferred' })
if ($ifs.Count -ne 1) {throw 'P4_MOCK_GATEWAY_STOP_PC_LAN_INTERFACE_NOT_READY'}
$gateway=Join-Path $PSScriptRoot 'run_assumed_source_gateway.py'
if (-not (Test-Path -LiteralPath $gateway -PathType Leaf)) {
  throw 'P4_MOCK_GATEWAY_STOP_P2_GATEWAY_SOURCE_NOT_FOUND'
}
$python=Get-Command 'python.exe' -ErrorAction SilentlyContinue
$pythonArgs=@()
if ($null -eq $python) {
  $python=Get-Command 'py.exe' -ErrorAction SilentlyContinue
  $pythonArgs=@('-3')
}
if ($null -eq $python) {throw 'P4_MOCK_GATEWAY_STOP_PYTHON_NOT_AVAILABLE'}
# No separate pairing step: the only trusted laptop silently stages its
# existing private key to the one authorized Debug TV over ADB ONCE.
$bootstrap=Join-Path $PSScriptRoot 'auto_pair_owner_redmi_adb.ps1'
if (-not (Test-Path -LiteralPath $bootstrap -PathType Leaf)) {
  throw 'P4_MOCK_GATEWAY_STOP_ADB_BOOTSTRAP_SCRIPT_MISSING'
}
& $bootstrap
if ($LASTEXITCODE -ne 0 -or -not $?) {
  throw 'P4_MOCK_GATEWAY_STOP_OWNER_PC_BOOTSTRAP_FAILED'
}
Write-Host 'P4_MOCK_GATEWAY_OWNER_FOREGROUND_ONLY=true'
Write-Host 'P4_MOCK_GATEWAY_SYNTHETIC_ONLY_NO_PROVIDER_OR_TORRSERVER=true'
Write-Host 'P4_MOCK_GATEWAY_NO_WINDOWS_FIREWALL_CHANGES=true'
$prior=[Environment]::GetEnvironmentVariable('P4_PAIRING_MASTER_HEX','Process')
try {
  $env:P4_PAIRING_MASTER_HEX=$key
  # This command owns the foreground process until Ctrl+C. No background service.
  & $python.Source @pythonArgs $gateway --bind $ip --port $port --mock-revisions --mock-single-paired-media --start-lan --tls-cert $cert --tls-key $private
  if ($LASTEXITCODE -ne 0) {throw 'P4_MOCK_GATEWAY_STOP_P2_PROCESS_ERROR'}
} finally {
  if ($null -eq $prior) {Remove-Item -LiteralPath 'Env:P4_PAIRING_MASTER_HEX' -ErrorAction SilentlyContinue}
  else {$env:P4_PAIRING_MASTER_HEX=$prior}
  $key=$null
}
