# Read-only TorrServer loopback/LAN HTTP probe; no media, credentials or IP values in output.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win') { throw 'UNTRUSTED_RUNNER' }
function Probe([string]$ip) {
    try {
        $r = Invoke-WebRequest -Uri ("http://" + $ip + ":8090/torrents") -Method Post -Body '{"action":"list"}' -ContentType 'application/json' -TimeoutSec 5 -NoProxy -ErrorAction Stop
        $list = ConvertFrom-Json -InputObject $r.Content -NoEnumerate
        if ($r.StatusCode -eq 200 -and $list -is [array]) { return 'HTTP_200_LIST' }
        return 'HTTP_BAD_SCHEMA'
    } catch { return 'HTTP_UNREACHABLE_OR_ERROR' }
}
$ips = @(Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } | ForEach-Object { $_.IPv4Address.IPAddress } | Where-Object { $_ -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' } | Select-Object -Unique)
$listen = @(Get-NetTCPConnection -LocalPort 8090 -State Listen -ErrorAction SilentlyContinue)
$ts = @(Get-Process -Name 'TorrServer-windows-amd64' -ErrorAction SilentlyContinue)
Write-Output ('TS_PROCESS_COUNT=' + $ts.Count)
Write-Output ('TS_LAN_CANDIDATES=' + $ips.Count)
Write-Output ('TS_LISTENERS=' + $listen.Count)
Write-Output ('TS_LOOPBACK_HTTP=' + (Probe '127.0.0.1'))
$ok=0
foreach ($ip in $ips) {
    if ((Probe $ip) -ceq 'HTTP_200_LIST') { $ok++ }
}
Write-Output ('TS_LAN_HTTP_OK_COUNT=' + $ok)
$net = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue)
Write-Output ('TS_PRIVATE_NETWORK_COUNT=' + @($net | Where-Object { $_.NetworkCategory -eq 'Private' }).Count)
Write-Output ('TS_PUBLIC_NETWORK_COUNT=' + @($net | Where-Object { $_.NetworkCategory -eq 'Public' }).Count)
