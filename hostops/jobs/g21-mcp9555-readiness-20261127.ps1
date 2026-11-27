$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$client = [System.Net.Sockets.TcpClient]::new()
try {
  $connection = $client.ConnectAsync('127.0.0.1',9555)
  if (-not $connection.Wait(3000) -or -not $client.Connected) { throw 'CDP9555_TCP_NOT_READY' }
  Write-Host 'G21_CDP9555_TCP=PASS'
} catch {
  Write-Host 'G21_CDP9555_TCP=NOT_READY'
  exit 1
} finally { $client.Dispose() }
try {
  $v = Invoke-RestMethod -Uri 'http://127.0.0.1:9555/json/version' -Method Get -TimeoutSec 5 -NoProxy
  if (-not $v.Browser -or -not $v.'Protocol-Version' -or -not $v.webSocketDebuggerUrl) { throw 'CDP_SCHEMA_INVALID' }
  $uri = [Uri]$v.webSocketDebuggerUrl
  if ($uri.Host -notin @('localhost','127.0.0.1','::1') -or $uri.Port -ne 9555) { throw 'CDP_ENDPOINT_SCOPE' }
  Write-Host 'G21_CDP9555_HTTP_SCHEMA=PASS'
} catch { Write-Host 'G21_CDP9555_HTTP_SCHEMA=NOT_READY'; exit 1 }
Write-Host ('G21_AGY_COMMAND_VISIBLE=' + [bool](Get-Command agy -ErrorAction SilentlyContinue))
Write-Host 'G21_SCOPE=READ_ONLY_CDP_READINESS'
Write-Host 'G21_MCP_TOOL_CALL=NOT_ATTEMPTED'
Write-Host 'G21_DISCOVERY_ADD=NOT_ATTEMPTED'
