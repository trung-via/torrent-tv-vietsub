# V7-R: project a stored report; never invoke AGY or expose free text.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$source='6e28d723bf95611bb8a4541cd54ea0e1bcf74fdc'
$prefix='tr-ttv-16-kalki2898ad-subtitlecat-v4-profile-'
$stageExpected='TR16_T122F3B41L110D109P117K10J0M0A1C1672_W1B1O1S0'
function ReadBounded($p,[long]$max){
  $item=Get-Item -LiteralPath $p -Force -ErrorAction Stop
  if($item.PSIsContainer -or $item.Length -le 0 -or $item.Length -gt $max -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'V7_READ_BOUND'}
  Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
}
$foundReports=@(foreach($dir in Get-ChildItem -LiteralPath $root -Directory -Filter ($prefix+'*')){
  if(($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $dir.Name -cnotmatch ('^'+$prefix+'([a-f0-9]{32})$')){continue}
  $prior=$Matches[1]
  $stagePath=Join-Path $spool ('Receipts\odyssey-stage-'+$prior+'.json')
  if(-not(Test-Path -LiteralPath $stagePath -PathType Leaf)){continue}
  $stage=ReadBounded $stagePath 1024
  if($stage.schema -cne 'TTV-ODYSSEY-STAGE-V1' -or $stage.nonce -cne $prior -or $stage.reason -cne $stageExpected){continue}
  $r=ReadBounded (Join-Path $dir.FullName 'BRAIN_STUDENT_REPORT.json') 16777216
  if($r.source_commit -ceq $source -and $r.provider -ceq 'SubtitleCat' -and $r.model -ceq 'gemini-4-hydrogen-low' -and $r.recipe_version -ceq 'V4'){[pscustomobject]@{report=$r;dir=$dir.FullName}}
})
if($foundReports.Count -ne 1){throw 'V7_REPORT_NOT_UNIQUE'}
$r=$foundReports[0].report
$t=ReadBounded (Join-Path $foundReports[0].dir 'stream-timing.json') 4194304
if($t.schema -cne 'TTV-STREAM-ARRIVAL-V1' -or $r.elapsed_seconds -ne 122 -or $t.download_mtime_elapsed -ne 109 -or @($r.tool_names).Count -ne 10){throw 'V7_TELEMETRY_MISMATCH'}
$art=@($r.artifacts)
if($art.Count -ne 1 -or $art[0].cues -ne 1672){throw 'V7_ARTIFACT_MISMATCH'}
# Privacy by projection: no free text, URLs, names, tokens, paths or DOM output.
$answer=@($r.final_response | Where-Object {$_ -is [string] -and $_.Length -gt 0}) -join ' '
function EnumLabel([string]$label,[string[]]$allowed){
  $found=@(foreach($a in $allowed){if($answer -match ('(?i)\b'+[regex]::Escape($label)+'[\s*"'':=]+(?:"|'')?'+[regex]::Escape($a)+'\b')){$a}})
  if($found.Count -eq 1){return $found[0]}
  return 'NOT_REPORTED'
}
$summary=[ordered]@{
 schema='TTV-AGY-BRAIN-READOUT-V1';nonce=$rq.nonce;source=$source;provider='SubtitleCat';model='gemini-4-hydrogen-low';recipe='V4'
 elapsed=122;download_seconds=109;tools=10;cues=1672;artifacts=1
 final_present=[bool]($answer.Length -gt 0)
 final_status=(EnumLabel 'status' @('CANDIDATE_DOWNLOADED','NO_PLAUSIBLE_CANDIDATE','ACCESS_BLOCKED','AUTH_REQUIRED','DOWNLOAD_FAILED','TOOL_UNAVAILABLE','UNKNOWN'))
 final_release=(EnumLabel 'release_match' @('EXACT_METADATA','EVIDENCED_COMPATIBLE','UNKNOWN','CONFLICT'))
 title_language=[bool]$r.title_language_evidence;exact_release=[bool]$r.exact_release_line_evidence
 release_verified=[bool]$r.release_match_verified;sync_verified=[bool]$r.playback_sync_verified
 permission_denied=[bool]$r.permission_denied;config_drift=[bool]$r.shared_config_drift
 provider_access=$(if($r.provider_access -ceq 'ACCESS_BLOCKED'){'ACCESS_BLOCKED'}else{'SITE_TAB_OBSERVED'})
}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\agy-brain-readout-'+$rq.nonce+'.json')),($summary|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output 'V7_READOUT_PROJECTED'
