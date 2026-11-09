# Read-only source validation for the private-subtitle handoff script.
# Does not need private repo, tokens, files, ADB or TV.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($env:RUNNER_NAME -cne 'torrent-tv-vietsub-win'){throw 'INVALID_RUNNER'}
$target=Join-Path $env:GITHUB_WORKSPACE 'hostops\jobs\private-subtitle-handoff.ps1'
if(-not (Test-Path -LiteralPath $target -PathType Leaf)){throw 'SOURCE_MISSING'}
$tokens=$null
$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($target,[ref]$tokens,[ref]$errors)
if($null -eq $ast -or @($errors).Count -ne 0){throw 'POWERSHELL_PARSER_FAIL'}
$s=[IO.File]::ReadAllText($target)
$required=@('TTV_HANDOFF_PRIVATE_GITHUB_TO_REDMITV_SHA_PASS','TTV_HANDOFF_SOURCE_SHA_MISMATCH',
 'TTV_HANDOFF_REMOTE_SHA_MISMATCH','TTV_HANDOFF_WRONG_TV','TTV_HANDOFF_ADB_PUSH_FAILED')
foreach($marker in $required){if(-not $s.Contains($marker)){throw 'REQUIRED_MARKER_MISSING'}}
if($s.Contains('Invoke-AdbSafe @(')){throw 'ARRAY_ARGUMENTS_UNSAFE'}
if($s.Contains('adb install') -or $s.Contains('adb shell am start')){throw 'OUT_OF_SCOPE_ACTION'}
$good='/tv-subtitle deliver thor-v035 ' + ('a'*64)
if($good -cnotmatch '^/tv-subtitle deliver ([a-z0-9][a-z0-9-]{0,39}) ([a-f0-9]{64})$'){throw 'REQUEST_PATTERN_MISMATCH'}
$bad='/tv-subtitle deliver ../thor ' + ('a'*64)
if($bad -cmatch '^/tv-subtitle deliver ([a-z0-9][a-z0-9-]{0,39}) ([a-f0-9]{64})$'){throw 'PATH_ESCAPE_ACCEPTED'}
Write-Host 'TTV_PRIVATE_HANDOFF_POWERSHELL_PARSE=PASS'
Write-Host 'TTV_PRIVATE_HANDOFF_STATIC_GATES=PASS'
Write-Host 'TTV_PRIVATE_HANDOFF_REAL_TRANSFER=NOT_RUN'
