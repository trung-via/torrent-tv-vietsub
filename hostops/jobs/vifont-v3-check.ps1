# Source-only PowerShell syntax + bounded install/rollback static contract check.
# Does not touch the TV or run the installer.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
   $env:RUNNER_OS -cne 'Windows') {throw 'VI_FONT_INSTALL_CHECK_WRONG_RUNNER'}
$target=Join-Path $env:GITHUB_WORKSPACE 'hostops\jobs\vifont-v3-install.ps1'
if(-not (Test-Path -LiteralPath $target -PathType Leaf)){
 throw 'VI_FONT_INSTALL_CHECK_SCRIPT_MISSING'
}
$tokens=$null
$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($target,[ref]$tokens,[ref]$errors)
if($null -eq $ast -or @($errors).Count -ne 0){
 foreach($problem in @($errors) | Select-Object -First 6){
  Write-Host ('VI_FONT_PARSE_ERROR_LINE='+$problem.Extent.StartLineNumber)
  Write-Host ('VI_FONT_PARSE_ERROR_ID='+$problem.ErrorId)
  Write-Host ('VI_FONT_PARSE_ERROR_DESC='+$problem.Message)
 }
 throw 'VI_FONT_INSTALL_POWERSHELL_PARSE_FAILED'
}
$src=[IO.File]::ReadAllText($target)
$required=@(
 'VI_FONT_CANDIDATE_SOURCE_AND_SHA_PASS',
 'VI_FONT_BASELINE_PRIVATE_ROLLBACK_READY=TRUE',
 'VI_FONT_VERSION_AND_SIGNER_COMPATIBLE=TRUE',
 'VI_FONT_ADB_INSTALL_REPLACE_BEGIN',
 'VI_FONT_INSTALLED_DEBUG_APK_VERIFIED_PASS',
 'VI_FONT_AUTOMATIC_ROLLBACK_BEGIN',
 'VI_FONT_ROLLBACK_BASELINE_SHA_PASS',
 'VI_FONT_V3_GLYPH_VISUAL_ACCEPTANCE=PENDING_HUMAN',
 'VI_FONT_V3_STOP_INSTALLED_V2_SHA_DRIFT',
 'VI_FONT_V2_INSTALLED_BASELINE_SHA_VERIFIED=TRUE',
 '845e25444e1ed9fc3092a1274c6f93e2dce19854b588eae9b9085139c85b74ac',
 'aaab104e41b89888c5cbf9dd0b87907962211f17fdb3d8194bb075adde6afa42',
 '1f67f9da09148196c73a7028cc7ed733a6410fc7',
 'VI_FONT_INSTALL_EXISTING_APK_NOT_SINGLE_BASE',
 'FONT-CANDIDATE-42665236868-1',
 'VI_FONT_V3_OWNER_APPROVED_INSTALL_BEGIN',
 'VI_FONT_V3_OWNER_APPROVED_INSTALL_END'
)
foreach($term in $required){
 if(-not $src.Contains($term)){throw 'VI_FONT_INSTALL_CHECK_GUARD_MISSING'}
}
if($src.Contains('New-Item -LiteralPath') -or $src.Contains('$matches=@') -or
   $src.Contains("'uninstall'") -or $src.Contains("'pm','clear'") -or
   $src.Contains("'install','-d'") -or $src.Contains("'shell','rm'")){
 throw 'VI_FONT_INSTALL_CHECK_UNSAFE_PATH_OR_COMMAND'
}
if(([regex]::Matches($src, "'install','-r'")).Count -ne 2){
 throw 'VI_FONT_INSTALL_CHECK_UNEXPECTED_INSTALL_COUNT'
}
$backupIndex=$src.IndexOf('VI_FONT_V2_INSTALLED_BASELINE_SHA_VERIFIED=TRUE')
$installIndex=$src.IndexOf('VI_FONT_ADB_INSTALL_REPLACE_BEGIN')
if($backupIndex -lt 0 -or $installIndex -le $backupIndex){
 throw 'VI_FONT_INSTALL_CHECK_V2_BASELINE_GUARD_NOT_BEFORE_INSTALL'
}
$shaFields=@(
  '845e25444e1ed9fc3092a1274c6f93e2dce19854b588eae9b9085139c85b74ac',
  'aaab104e41b89888c5cbf9dd0b87907962211f17fdb3d8194bb075adde6afa42'
)
foreach($item in $shaFields){if(-not $src.Contains($item)){throw 'VI_FONT_INSTALL_CHECK_PIN_DRIFT'}}
Write-Host 'VI_FONT_INSTALL_POWERSHELL_PARSE=PASS'
Write-Host 'VI_FONT_V3_INSTALL_STATIC_OWNER_GATES=PASS'
Write-Host 'VI_FONT_INSTALL_REAL_REDMITV_ACTION=NOT_RUN'
