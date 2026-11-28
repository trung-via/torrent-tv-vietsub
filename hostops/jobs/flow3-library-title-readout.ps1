# Read-only title lookup for the requested film, no source discovery or media transfer.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win'){throw 'WRONG_RUNNER'}
$r=Invoke-WebRequest -Uri 'http://127.0.0.1:8090/torrents' -Method POST -ContentType 'application/json' -Body '{"action":"list"}' -TimeoutSec 5 -NoProxy -MaximumRedirection 0
if($r.StatusCode -ne 200){throw 'LIBRARY_UNAVAILABLE'}
$rows=$r.Content|ConvertFrom-Json -Depth 50 -NoEnumerate
$m=@($rows|Where-Object{$_ -and $_.PSObject.Properties['title'] -and [string]$_.title -match '(?i)(?:^|[\s._-])Heart[\s._-]+of[\s._-]+the[\s._-]+Beast(?:[\s._-]+|\s*\()2026(?:$|[\s._\-)])'})
Write-Output ('FLOW3_LIBRARY_TITLE_MATCH_COUNT='+$m.Count)
