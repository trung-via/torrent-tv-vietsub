# Owner PC, explicit foreground EN -> LEAN120 Gemini -> VI -> signed P4 LAN.
# NO automatic boot, CI/provider invocation, secret output or firewall changes.
# The already-paired Debug TV supplies media identity in signed activation.
[CmdletBinding()]
param(
  [switch]$AuthorizeCloudTranslation,
  [string]$ManifestPath = '',
  [string]$ProfilePath = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $AuthorizeCloudTranslation) {
  throw 'P2_AUTO_STOP_EXPLICIT_CLOUD_TRANSLATION_CONSENT_REQUIRED'
}
if ($env:GITHUB_ACTIONS -eq 'true' -or $env:CI -eq 'true' -or $env:TF_BUILD) {
  throw 'P2_AUTO_STOP_CI_PROVIDER_FORBIDDEN'
}
if (-not $env:LOCALAPPDATA -or -not $env:GEMINI_API_KEY) {
  throw 'P2_AUTO_STOP_OWNER_PROFILE_OR_GEMINI_KEY_REQUIRED'
}
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$pair=Join-Path $owner 'P4'
$p2=Join-Path $owner 'P2'
if (-not $ManifestPath) { $ManifestPath=Join-Path $p2 'verified-en-manifest.json' }
if (-not $ProfilePath) { $ProfilePath=Join-Path $p2 'translator-profile.json' }
if (-not [System.IO.Path]::IsPathRooted($ManifestPath) -or
    -not [System.IO.Path]::IsPathRooted($ProfilePath)) {
  throw 'P2_AUTO_STOP_PRIVATE_ABSOLUTE_PATH_REQUIRED'
}
foreach ($path in @($ManifestPath,$ProfilePath)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw 'P2_AUTO_STOP_VERIFIED_SOURCE_MANIFEST_OR_PROFILE_NOT_READY'
  }
}
$keyFile=Join-Path $pair 'pairing-key.hex'
$bindFile=Join-Path $pair 'gateway-bind.txt'
$cert=Join-Path $pair 'pc-cert.pem'
$private=Join-Path $pair 'pc-key.pem'
foreach($path in @($keyFile,$bindFile,$cert,$private)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw 'P2_AUTO_STOP_OWNER_TLS_PAIRING_NOT_READY'
  }
}
$key=(Get-Content -LiteralPath $keyFile -Raw).Trim()
if ($key -notmatch '^[a-fA-F0-9]{64}$') {throw 'P2_AUTO_STOP_OWNER_PAIRING_KEY_INVALID'}
$binding=(Get-Content -LiteralPath $bindFile -Raw).Trim()
if ($binding -notmatch '^(10\.(?:[0-9]{1,3}\.){2}[0-9]{1,3}|172\.(?:1[6-9]|2[0-9]|3[01])\.(?:[0-9]{1,3}\.)[0-9]{1,3}|192\.168\.(?:[0-9]{1,3}\.)[0-9]{1,3}):([0-9]{4,5})$') {
  throw 'P2_AUTO_STOP_LAN_BIND_INVALID'
}
$ip=$Matches[1]
$port=[int]$Matches[2]
if ($port -lt 1024 -or $port -gt 65535) {throw 'P2_AUTO_STOP_PORT_INVALID'}
$ifaces=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
  Where-Object { $_.IPAddress -ceq $ip -and $_.AddressState -eq 'Preferred' })
if ($ifaces.Count -ne 1) {throw 'P2_AUTO_STOP_LAN_NIC_MISMATCH'}
$gateway=Join-Path $PSScriptRoot 'run_assumed_source_gateway.py'
if (-not (Test-Path -LiteralPath $gateway -PathType Leaf)) {
  throw 'P2_AUTO_STOP_GATEWAY_NOT_FOUND'
}
$python=Get-Command 'python.exe' -ErrorAction SilentlyContinue
$pythonArgs=@()
if ($null -eq $python) {
  $python=Get-Command 'py.exe' -ErrorAction SilentlyContinue
  $pythonArgs=@('-3')
}
if ($null -eq $python) {throw 'P2_AUTO_STOP_PYTHON_NOT_AVAILABLE'}
# No automatic ADB re-pairing. The owner Redmi has a persisted pinned PC.
# State and source bytes MUST stay in the Windows user's private profile.
$state=Join-Path $p2 'auto-lean120-state'
$prior=[Environment]::GetEnvironmentVariable('P4_PAIRING_MASTER_HEX','Process')
try {
  $env:P4_PAIRING_MASTER_HEX=$key
  Write-Host 'P2_AUTO_EN_SOURCE_FROM_OWNER_MANIFEST=true'
  Write-Host 'P2_AUTO_GEMINI_LEAN120_ON_AUTHENTICATED_TV_ACTIVATION=true'
  Write-Host 'P2_AUTO_PRIVATE_CUMULATIVE_VI_SRT=true'
  Write-Host 'P2_AUTO_PROVIDER_AND_LAN_REQUIRE_EXPLICIT_OWNER_START=true'
  Write-Host 'P2_AUTO_NO_FIREWALL_ROUTER_OR_TORRSERVER_CHANGES=true'
  # Foreground PC process. No film IDs or subtitles are echoed in output.
  $launchArgs=@('--bind',$ip,'--port',"$port",'--source-manifest',
    $ManifestPath,'--profile',$ProfilePath,'--auto-state-dir',$state,
    '--execute-api','--start-lan','--tls-cert',$cert,'--tls-key',$private)
  & $python.Source @pythonArgs $gateway @launchArgs
  if ($LASTEXITCODE -ne 0) {throw 'P2_AUTO_STOP_TRANSLATION_GATEWAY_FAILED'}
} finally {
  if ($null -eq $prior) {
    Remove-Item -LiteralPath 'Env:P4_PAIRING_MASTER_HEX' -ErrorAction SilentlyContinue
  } else {
    $env:P4_PAIRING_MASTER_HEX=$prior
  }
  $key=$null
}
