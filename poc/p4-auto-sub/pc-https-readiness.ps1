# Read-only owner-scoped P4 HTTPS host readiness; no local IP, path or secret printed.
# NO cert generation, file writes, listener bind, firewall/router/service changes or ADB mutations.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_EVENT_NAME -cne 'pull_request' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:GITHUB_HEAD_REF -cne 'feature/p4-native-auto-sub-g2-20261111' -or
    $env:GITHUB_BASE_REF -cne 'feature/g2-refresh-vietsub-inplace-20261111' -or
    $env:GITHUB_REF -cne 'refs/pull/120/merge') {
    throw 'P4_PC_PREFLIGHT_STOP_UNTRUSTED_CONTEXT'
}
$event=Get-Content -LiteralPath $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json
if ([int]$event.number -ne 120 -or
    $event.pull_request.user.login -cne 'trung-via' -or
    $event.pull_request.head.repo.full_name -cne $env:GITHUB_REPOSITORY) {
    throw 'P4_PC_PREFLIGHT_STOP_WRONG_PR'
}
function Is-PrivateIPv4([string]$ip) {
    if (-not $ip -or $ip -notmatch '^([0-9]{1,3}\.){3}[0-9]{1,3}$') {return $false}
    $parts=@($ip.Split('.'))
    foreach($p in $parts) {
        $v=0
        if (-not [int]::TryParse($p,[ref]$v) -or $v -gt 255 -or $v -lt 0 -or
            ($p.Length -gt 1 -and $p.StartsWith('0'))) {return $false}
    }
    $a=[int]$parts[0]
    $b=[int]$parts[1]
    return ($a -eq 10 -or ($a -eq 172 -and $b -ge 16 -and $b -le 31) -or
      ($a -eq 192 -and $b -eq 168))
}
$adapters=@()
try {
    $adapters=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
       Where-Object { $_.AddressState -eq 'Preferred' -and (Is-PrivateIPv4 ([string]$_.IPAddress)) })
} catch {
    Write-Host 'P4_PC_READONLY_NET_IP_QUERY_UNAVAILABLE=true'
}
Write-Host ('P4_PC_PRIVATE_LAN_IPV4_EXISTS=' + [string]($adapters.Count -ge 1).ToString().ToLowerInvariant())
# Do not print interfaces, IPv4 values, MACs, gateway, hosts or DNS names.

$openssl=Get-Command 'openssl.exe' -ErrorAction SilentlyContinue
$pin='C:\Program Files\Git\usr\bin\openssl.exe'
$hasOpenssl=($null -ne $openssl) -or (Test-Path -LiteralPath $pin -PathType Leaf)
Write-Host ('P4_PC_OPENSSL_AVAILABLE='+ $hasOpenssl.ToString().ToLowerInvariant())
$python=(Get-Command 'python.exe' -ErrorAction SilentlyContinue)
Write-Host ('P4_PC_PYTHON_ON_PATH='+($null -ne $python).ToString().ToLowerInvariant())

$port=19009 # candidate only, does not commit to a configured port
$listener=@()
try {
    $listener=@(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
} catch { }
Write-Host ('P4_PC_CANDIDATE_PORT_19009_LISTENER_PRESENT='+($listener.Count -gt 0).ToString().ToLowerInvariant())
# Absence of listener does NOT prove firewall / network allowlisted reachability.
$cert=[Environment]::GetEnvironmentVariable('TTV_P4_TLS_CERT_FILE','Process')
$key=[Environment]::GetEnvironmentVariable('TTV_P4_TLS_KEY_FILE','Process')
$master=[Environment]::GetEnvironmentVariable('P4_PAIRING_MASTER_HEX','Process')
$certPresent=([string]::IsNullOrWhiteSpace($cert) -eq $false) -and
    (Test-Path -LiteralPath $cert -PathType Leaf)
$keyPresent=([string]::IsNullOrWhiteSpace($key) -eq $false) -and
    (Test-Path -LiteralPath $key -PathType Leaf)
$masterReady=($null -ne $master) -and ($master -cmatch '^[a-fA-F0-9]{64}$')
Write-Host ('P4_PC_CERT_PATH_EXPLICIT_ENV_READY='+$certPresent.ToString().ToLowerInvariant())
Write-Host ('P4_PC_KEY_PATH_EXPLICIT_ENV_READY='+$keyPresent.ToString().ToLowerInvariant())
Write-Host ('P4_PC_GATEWAY_EXPECTED_PAIRING_ENV_READY='+$masterReady.ToString().ToLowerInvariant())
# These are process-env hints ONLY. Owner-managed files elsewhere are not audited.
Write-Host 'P4_PC_HTTPS_LAN_AND_TV_PAIRING=NOT_TESTED'
Write-Host 'P4_PC_PREFLIGHT_READONLY_NO_HOST_MUTATION=true'
$global:LASTEXITCODE=0
