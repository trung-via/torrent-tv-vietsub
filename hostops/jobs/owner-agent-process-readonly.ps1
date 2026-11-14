# Read-only process visibility; never prints user profile, args or secrets.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows') {
    throw 'OWNER_AGENT_PROCESS_PROBE_UNTRUSTED'
}
Write-Host 'OWNER_AGENT_PROCESS_PROBE_V1'
try {
    $processes = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe' OR Name='py.exe'" -ErrorAction Stop)
    $readable = @($processes | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.CommandLine)
    })
    $matching = @($readable | Where-Object {
        $_.CommandLine -match 'owner_session_bridge[.]py'
    })
    if ($matching.Count -gt 0) {
        Write-Host 'OWNER_AGENT_PROCESS_DISCOVERY=VISIBLE'
        $interactive = @($matching | Where-Object { $_.SessionId -gt 0 }).Count -gt 0
        Write-Host ('OWNER_AGENT_INTERACTIVE_SESSION=' + $interactive.ToString().ToUpperInvariant())
    }
    else {
        # Lack of service-account WMI access is NOT proof of absent agent.
        Write-Host 'OWNER_AGENT_PROCESS_DISCOVERY=NOT_VISIBLE_OR_ACCESS_RESTRICTED'
        $someReadable = $readable.Count -gt 0
        Write-Host ('OWNER_AGENT_PYTHON_CMD_READABLE=' + $someReadable.ToString().ToUpperInvariant())
    }
}
catch {
    Write-Host 'OWNER_AGENT_PROCESS_DISCOVERY=UNAVAILABLE'
}
Write-Host 'OWNER_AGENT_OWNER_PROFILE_FILES_READ=NO'
Write-Host 'OWNER_AGENT_API_KEY_OR_FILM_NAMES_PRINTED=NO'
Write-Host 'OWNER_AGENT_WINDOWS_PERMISSIONS_CHANGED=NO'
