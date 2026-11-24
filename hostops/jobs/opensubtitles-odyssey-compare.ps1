# Read-only comparison: yesterday's known Odyssey download URI versus today's Spider-Man detail page.
# No API, credentials, AGY, browser automation, media stream, or persistent subtitle writing.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne 'S-1-5-20') {
    throw 'OPENSUB_COMPARE_TRUSTED_RUNNER_REQUIRED'
}
Add-Type -AssemblyName System.Net.Http
$handler = [Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $false
$handler.UseCookies = $false
$handler.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
$client = [Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds(12)
function Probe([string]$name,[string]$url,[bool]$browser) {
    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,$url)
    $request.Headers.UserAgent.ParseAdd($(if ($browser) {
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36'
    } else {
        'TorrentTV-Brain-Compare/1.0'
    }))
    $request.Headers.Accept.ParseAdd('*/*')
    $response = $null
    $stream = $null
    $memory = $null
    $result='ERROR'
    $length=0
    $cues=0
    $digest='NOT_CHECKED'
    try {
        $response = $client.SendAsync($request,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $status = [int]$response.StatusCode
        if ($status -ne 200) {
            $result = 'HTTP_' + $status
            if ($status -ge 300 -and $status -lt 400) {
                $dest = $response.Headers.Location
                if ($null -ne $dest) {
                    $hostName = if ($dest.IsAbsoluteUri) { $dest.Host } else { [Uri]$url | ForEach-Object { $_.Host } }
                    if ($hostName -match '(^|\.)opensubtitles\.org$') { $result += '_OPEN_SUBTITLES_REDIRECT' }
                    else { $result += '_OTHER_REDIRECT' }
                }
            }
        } else {
            $contentLength = $response.Content.Headers.ContentLength
            if ($null -ne $contentLength -and $contentLength -gt 524288) {
                $result='HTTP_200_OVERSIZE'
            } else {
                $stream=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                $memory=[IO.MemoryStream]::new()
                $buffer=New-Object byte[] 8192
                while ($true) {
                    $read=$stream.Read($buffer,0,$buffer.Length)
                    if ($read -le 0) { break }
                    if ($memory.Length + $read -gt 524288) { $result='HTTP_200_OVERSIZE'; break }
                    $memory.Write($buffer,0,$read)
                }
                if ($result -ne 'HTTP_200_OVERSIZE') {
                    $data=$memory.ToArray()
                    $length=$data.Length
                    $head=[Text.Encoding]::UTF8.GetString($data,0,[Math]::Min(512,$data.Length))
                    if ($head -match '(?i)<!doctype html|<html') { $result='HTTP_200_HTML' }
                    elseif ($data.Length -gt 4 -and $data[0] -eq 80 -and $data[1] -eq 75) { $result='HTTP_200_ZIP' }
                    else {
                        $body=[Text.Encoding]::UTF8.GetString($data)
                        $cues=[regex]::Matches($body,'(?m)^\d{2}:\d{2}:\d{2},\d{3}\s+-->\s+\d{2}:\d{2}:\d{2},\d{3}').Count
                        $result=if ($cues -ge 50) { 'HTTP_200_SRT' } else { 'HTTP_200_OTHER' }
                    }
                    if ($result -eq 'HTTP_200_SRT') {
                        $sha=[Security.Cryptography.SHA256]::HashData($data)
                        $hex=[Convert]::ToHexString($sha).ToLowerInvariant()
                        $digest=if ($hex -ceq 'fe793b7267170a016c01dcd597604afd9ce99414af374a95748f245acc0e7159') { 'ODYSSEY_EXACT_KNOWN' } else { 'DIFFERENT_BYTES' }
                    }
                }
            }
        }
    } catch [System.Threading.Tasks.TaskCanceledException] { $result='TIMEOUT' }
      catch [System.Net.Http.HttpRequestException] { $result='NETWORK_FAILURE' }
      catch { $result='LOCAL_PROBE_ERROR' }
    finally {
        if ($null -ne $memory) { $memory.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
        $request.Dispose()
    }
    Write-Output ("OS_COMPARE_" + $name + "=" + $result)
    Write-Output ("OS_COMPARE_" + $name + "_BYTES=" + $length)
    Write-Output ("OS_COMPARE_" + $name + "_CUES=" + $cues)
    Write-Output ("OS_COMPARE_" + $name + "_DIGEST=" + $digest)
}
try {
# Explicit Owner request: persist one verified English Odyssey subtitle on the
# dedicated runner; no TV, OwnerAgent, provider or other film's cache mutation.
$targetRoot = Join-Path $env:RUNNER_WORKSPACE '_omp-fast-cache\odyssey-english-2026'
if (-not (Test-Path -LiteralPath $targetRoot)) {
    New-Item -ItemType Directory -Path $targetRoot -ErrorAction Stop | Out-Null
}
$dest = Join-Path $targetRoot 'The.Odyssey.2026.1080p.AMZN.WEB-DL.DDP5.1.H.264-KyoGo.en.srt'
$expectedCues = 2009
if (Test-Path -LiteralPath $dest -PathType Leaf) {
    $existing = [IO.File]::ReadAllBytes($dest)
    $existingCues = [regex]::Matches([Text.Encoding]::UTF8.GetString($existing),'(?m)^\d{2}:\d{2}:\d{2},\d{3}\s+-->\s+\d{2}:\d{2}:\d{2},\d{3}').Count
    if ($existingCues -ne $expectedCues) { throw 'ODYSSEY_EXISTING_EN_INVALID_NO_OVERWRITE' }
    Write-Output 'ODYSSEY_EN=ALREADY_STAGED_VALID'
    Write-Output ('ODYSSEY_EN_SHA256=' + (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant())
} else {
    $url = 'https://dl.opensubtitles.org/en/download/file/1962752152'
    $temp = Join-Path $targetRoot ('odyssey-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        Invoke-WebRequest -Uri $url -OutFile $temp -UseBasicParsing -TimeoutSec 45 -ErrorAction Stop
        $raw = [IO.File]::ReadAllBytes($temp)
        if ($raw.Length -lt 100000 -or $raw.Length -gt 500000) { throw 'ODYSSEY_EN_SIZE_INVALID' }
        $head = [Text.Encoding]::UTF8.GetString($raw,0,[Math]::Min($raw.Length,256))
        if ($head -match '(?i)<!doctype|<html') { throw 'ODYSSEY_EN_HTML_NOT_SUBTITLE' }
        $count = [regex]::Matches([Text.Encoding]::UTF8.GetString($raw),'(?m)^\d{2}:\d{2}:\d{2},\d{3}\s+-->\s+\d{2}:\d{2}:\d{2},\d{3}').Count
        if ($count -ne $expectedCues) { throw 'ODYSSEY_EN_CUES_INVALID' }
        Move-Item -LiteralPath $temp -Destination $dest -ErrorAction Stop
        Write-Output 'ODYSSEY_EN=DOWNLOADED_VALID'
        Write-Output ('ODYSSEY_EN_CUES=' + $count)
        Write-Output ('ODYSSEY_EN_SHA256=' + (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant())
    } finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}
Write-Output 'ODYSSEY_EN_SCOPE=RUNNER_PRIVATE_STAGE_NO_OWNER_OR_TV_CHANGE'
} finally {
    $client.Dispose()
    $handler.Dispose()
}
