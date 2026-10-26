# P0 Windows TorrServer -> Redmi OMP one-pass Human test.
# No ADB, server mutation, torrent add/delete, firewall, service, installer or secrets.
# Source-only until Human runs locally. Do not paste raw LAN URL in public logs.
[CmdletBinding()]
param([ValidateSet('Preflight','RunOnce')][string]$Phase = 'RunOnce')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Check-BaseUrl([string]$text,[bool]$mustBeLoopback) {
    [uri]$u = $null
    if (-not [uri]::TryCreate($text,[UriKind]::Absolute,[ref]$u)) {
        throw 'BLOCKED: server URL invalid'
    }
    if (($u.Scheme -cne 'http' -and $u.Scheme -cne 'https') -or
        $u.UserInfo.Length -ne 0 -or $u.Query.Length -ne 0 -or
        $u.Fragment.Length -ne 0 -or $u.AbsolutePath -cne '/' -or
        $u.Port -lt 1 -or $u.Port -gt 65535) {
        throw 'BLOCKED: URL must be clean http(s) host:port without user/pass/path/query'
    }
    [Net.IPAddress]$ip = $null
    if (-not [Net.IPAddress]::TryParse($u.Host,[ref]$ip) -or
        $ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        throw 'BLOCKED: use numeric IPv4, not hostname or IPv6, for this bounded test'
    }
    [byte[]]$b = $ip.GetAddressBytes()
    $loop = $b[0] -eq 127
    $privateLan = ($b[0] -eq 10) -or
        ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or
        ($b[0] -eq 192 -and $b[1] -eq 168)
    if ($mustBeLoopback -and -not $loop) {
        throw 'BLOCKED: local Windows server URL must be 127.x.x.x'
    }
    if (-not $mustBeLoopback -and -not $privateLan) {
        throw 'BLOCKED: TV-facing server URL must use private LAN IPv4, not localhost/WAN'
    }
    return $u
}
function Probe-Echo([uri]$base,[string]$stage) {
    # Read-only GET; do not inspect or print server metadata or configuration.
    $target = $base.AbsoluteUri.TrimEnd('/') + '/echo'
    try {
        $response = Invoke-WebRequest -Uri $target -UseBasicParsing -Method GET -TimeoutSec 8 -MaximumRedirection 0 -ErrorAction Stop
        if ([int]$response.StatusCode -ne 200) {
            throw 'Non-200 status'
        }
    } catch {
        # Avoid echoing exception objects: they may include the private URL.
        throw ('BLOCKED: ' + $stage + ' /echo failed (offline, auth, TLS, port, or routing)')
    }
    Write-Host ('P0_TS_' + $stage + '_ECHO_PASS')
}
function Human-Check([string]$tag,[string]$prompt) {
    Write-Host ''
    Write-Host $prompt
    $answer = (Read-Host ('Type PASS, FAIL or BLOCKED for ' + $tag)).Trim().ToUpperInvariant()
    if ($answer -notin @('PASS','FAIL','BLOCKED')) {
        throw ('STOP: ' + $tag + ' requires PASS/FAIL/BLOCKED')
    }
    if ($answer -cne 'PASS') {
        Write-Host ('P0_TS_' + $tag + '_HUMAN_' + $answer)
        throw ('STOP: ' + $tag + ' not passed; do not continue this test')
    }
    Write-Host ('P0_TS_' + $tag + '_HUMAN_PASS')
}

Write-Host 'P0_TS_ONEPASS_NO_SERVER_OR_TV_AUTOMATION'
Write-Host 'Only private LAN; no URL/password/torrent/media IDs will be printed.'
$localhost = Read-Host 'Windows TorrServer base URL (Enter = http://127.0.0.1:8090)'
if ([string]::IsNullOrWhiteSpace($localhost)) { $localhost = 'http://127.0.0.1:8090' }
$local = Check-BaseUrl -text $localhost.Trim() -mustBeLoopback $true
Probe-Echo -base $local -stage 'WINDOWS_LOOPBACK'
$lanText = Read-Host 'Windows PC private-LAN base URL for TV (e.g. http://192.168.x.x:8090)'
if ([string]::IsNullOrWhiteSpace($lanText)) {
    throw 'BLOCKED: no TV-reachable private-LAN Windows IP entered'
}
$lan = Check-BaseUrl -text $lanText.Trim() -mustBeLoopback $false
Probe-Echo -base $lan -stage 'WINDOWS_LAN_FROM_PC'
Write-Host 'P0_TS_WINDOWS_PREFLIGHT_PASS_NOT_TV_CONNECTIVITY_PROOF'

if ($Phase -ceq 'Preflight') {
    Write-Host 'P0_TS_PREFLIGHT_READ_ONLY_DONE'
    return
}

Write-Host ''
Write-Host 'Human TV test (the script NEVER configures or touches TV/server):'
Write-Host 'Use the SAME private LAN URL entered above in the installed OMP TV server settings.'
Write-Host 'Do not use localhost on TV. No credentials in chat or public logs.'
Write-Host 'Note original player/server settings if you will change them.'
Human-Check 'TV_CONNECTION' 'On Redmi OMP: server connection works; library loads (may be empty).'
Human-Check 'LEGAL_FIXTURE' 'A video/torrent you are authorized to access is ALREADY available in the library; do not add/delete torrents just for this script.'
Human-Check 'PLAYBACK' 'Open that legal video on TV. Confirm moving video and audible sound for at least one short sequence.'
Human-Check 'REMOTE_SEEK' 'Using the actual TV remote: pause/resume, seek forward and backward; playback remains responsive with audio.'
Human-Check 'REOPEN' 'Stop then reopen the SAME item, confirm playback resumes/reopens successfully; inspect saved point if available.'
Human-Check 'CONFIG_CHOICE' 'If server/player settings were changed for the test, either restore the prior value or explicitly decide to keep the new value yourself.'

Write-Host ''
Write-Host 'P0_TS_WINDOWS_TORRSERVER_REDMI_HUMAN_E2E_PASS'
Write-Host 'Evidence: /echo probes were automated from WINDOWS; TV outcomes are HUMAN-ENTERED, not ADB/network telemetry.'
Write-Host 'Share PASS/FAIL/BLOCKED marker lines only. Redact LAN IP, magnet, infohash, media title and credentials.'
