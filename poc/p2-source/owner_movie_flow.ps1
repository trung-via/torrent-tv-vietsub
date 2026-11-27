# Existing paired Windows runner after the private G2 request was submitted.
param([Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{32}$')][string]$RequestId)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win'){throw 'G2_WRONG_RUNNER'}
$receipt=Join-Path $env:ProgramData ('TorrentTVVietsub\LaptopHostOps\Receipts\g2-'+$RequestId+'.library.json')
$deadline=[DateTimeOffset]::UtcNow.AddMinutes(5)
while(-not (Test-Path -LiteralPath $receipt -PathType Leaf)){
 if([DateTimeOffset]::UtcNow -ge $deadline){Write-Host 'G2_LIBRARY=NOT_READY_NO_REPLAY';exit 1}
 Start-Sleep -Seconds 2
}
& pwsh -NoLogo -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'owner_movie_play.ps1') -RequestId $RequestId -EnableVietsub
exit $LASTEXITCODE
