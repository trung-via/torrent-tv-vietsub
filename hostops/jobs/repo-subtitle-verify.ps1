# Source-only pre-merge verifier for PUBLIC same-repo subtitle handoff.
# Does not modify TV, ADB, APK, media or source SRT.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($env:RUNNER_NAME -cne 'torrent-tv-vietsub-win'){throw 'INVALID_RUNNER'}
$scriptPath=Join-Path $env:GITHUB_WORKSPACE 'hostops\jobs\repo-subtitle-handoff.ps1'
$filePath=Join-Path $env:GITHUB_WORKSPACE 'subtitle-artifacts\thor-v035.srt'
$workflow=Join-Path $env:GITHUB_WORKSPACE '.github\workflows\torrent-tv-repo-subtitle-handoff.yml'
if(-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)){throw 'HANDOFF_SCRIPT_MISSING'}
if(-not (Test-Path -LiteralPath $filePath -PathType Leaf)){throw 'PUBLISHED_SRT_MISSING'}
if(-not (Test-Path -LiteralPath $workflow -PathType Leaf)){throw 'WORKFLOW_MISSING'}
$parseTokens=$null
$parseErrors=$null
$null=[System.Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$parseTokens,[ref]$parseErrors)
if(@($parseErrors).Count -ne 0){throw 'HANDOFF_POWERSHELL_PARSE_FAIL'}
Write-Host 'TTV_PUBLIC_HANDOFF_POWERSHELL_PARSE=PASS'
$bytes=(Get-Item -LiteralPath $filePath).Length
if($bytes -ne 123768){throw 'SRT_SIZE_MISMATCH'}
$sha=(Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant()
if($sha -cne '3d9d4bf37fe31eb5de8a7af32d68c21fb5a342b87778f6f7925a7b43ad26c15b'){throw 'SRT_SHA_MISMATCH'}
Write-Host 'TTV_PUBLIC_SRT_BYTES=123768'
Write-Host 'TTV_PUBLIC_SRT_SHA256=PASS'
$scriptText=[IO.File]::ReadAllText($scriptPath)
$yaml=[IO.File]::ReadAllText($workflow)
if($scriptText.Contains('TTV_PRIVATE_SUBTITLE_READ_TOKEN') -or $yaml.Contains('secrets.TTV_SUBTITLE_INBOX_READ')){throw 'PRIVATE_DEPENDENCY_REMAINS'}
if(-not $yaml.Contains('repo-subtitle-handoff.ps1')){throw 'HANDOFF_ENTRYPOINT_MISMATCH'}
if(-not $scriptText.Contains('TTV_HANDOFF_REPO_TO_REDMITV_SHA_PASS')){throw 'EXPECTED_DELIVERY_MARKER_MISSING'}
Write-Host 'TTV_PUBLIC_HANDOFF_STATIC_GATES=PASS'
Write-Host 'TTV_PUBLIC_HANDOFF_TV_TRANSFER=NOT_RUN'
