# Source-only PowerShell syntax + bounded install/rollback static contract check.
# Does not touch the TV or run the installer.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
   $env:RUNNER_OS -cne 'Windows') {throw 'VI_FONT_INSTALL_CHECK_WRONG_RUNNER'}
$target=Join-Path $env:GITHUB_WORKSPACE 'hostops\jobs\vifont-v2-install.ps1'
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
 'VI_FONT_V2_GLYPH_VISUAL_ACCEPTANCE=PENDING_HUMAN',
 'VI_FONT_V2_STOP_INSTALLED_V1_SHA_DRIFT',
 'VI_FONT_V1_INSTALLED_BASELINE_SHA_VERIFIED=TRUE',
 'aaab104e41b89888c5cbf9dd0b87907962211f17fdb3d8194bb075adde6afa42',
 '1ede7c2d346512af08ef8c5933416ac4e7e60b62a4588d29f03b251b2af38a59',
 '34b2c8cc559d48e17efc875308e1177c68e5189c',
 'VI_FONT_INSTALL_EXISTING_APK_NOT_SINGLE_BASE'
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
Write-Host 'VI_FONT_INSTALL_POWERSHELL_PARSE=PASS'
Write-Host 'VI_FONT_V2_INSTALL_STATIC_OWNER_GATES=PASS'
Write-Host 'VI_FONT_INSTALL_REAL_REDMITV_ACTION=NOT_RUN'
