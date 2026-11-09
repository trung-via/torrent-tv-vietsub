# Owner-approved one-time Debug font A/B install to the one authorized Redmi.
# Backup exact installed base.apk in private Windows vault BEFORE an in-place adb install -r.
# On post-install mismatch: rollback the backed-up APK with adb install -r.
# Never uninstall, clear app data, write TV file storage, touch TorrServer or alter Release.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo='trung-via/torrent-tv-vietsub'
$expectedCandidate='1ede7c2d346512af08ef8c5933416ac4e7e60b62a4588d29f03b251b2af38a59'
$expectedBuildSource='ac4da5f4e2a0a11a73885db5d61f1f821e3e2c24'
$pkg='com.spacesarmat.omp.test'
Write-Host 'VI_FONT_OWNER_APPROVED_INSTALL_BEGIN'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REPOSITORY -cne $repo -or
   $env:GITHUB_EVENT_NAME -cne 'issue_comment' -or
   $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or $env:RUNNER_OS -cne 'Windows') {
  throw 'VI_FONT_INSTALL_WRONG_TRUST_CONTEXT'
}
if($env:GITHUB_RUN_ID -notmatch '^[0-9]+$' -or
   $env:GITHUB_RUN_ATTEMPT -notmatch '^[0-9]+$'){
   throw 'VI_FONT_INSTALL_RUN_NOT_PINNED'
}
$root='C:\TOOL\TorrentTV-Runner\private-artifacts\G1P2'
$fontDir=Join-Path $root 'FONT-CANDIDATE-42649389062-1'
$candidate=Join-Path $fontDir 'app-armeabi-v7a-debug.apk'
$manifest=Join-Path $fontDir 'VI-FONT-EVIDENCE.txt'
$adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
foreach($file in @($candidate,$manifest,$adb)){
  if(-not (Test-Path -LiteralPath $file -PathType Leaf)){
    throw 'VI_FONT_INSTALL_REQUIRED_FILE_ABSENT'
  }
}
$realCandidate=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
if($realCandidate -cne $expectedCandidate){throw 'VI_FONT_INSTALL_CANDIDATE_SHA_MISMATCH'}
$lines=@(Get-Content -LiteralPath $manifest)
if(@($lines | Where-Object {$_ -ceq ('apk_sha256='+$expectedCandidate)}).Count -ne 1 -or
   @($lines | Where-Object {$_ -ceq ('source_commit='+$expectedBuildSource)}).Count -ne 1){
  throw 'VI_FONT_INSTALL_CANDIDATE_PROVENANCE_MISMATCH'
}
Write-Host 'VI_FONT_CANDIDATE_SOURCE_AND_SHA_PASS'
$vault=New-Object IO.DirectoryInfo($root)
if(-not $vault.Exists -or
  ($vault.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
  throw 'VI_FONT_INSTALL_PRIVATE_VAULT_UNSAFE'
}
$acl=$vault.GetAccessControl([Security.AccessControl.AccessControlSections]::Access)
if(-not $acl.AreAccessRulesProtected){throw 'VI_FONT_INSTALL_PRIVATE_VAULT_NOT_EXCLUSIVE'}
$ownerSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$allowed=@($ownerSid,'S-1-5-18','S-1-5-32-544') | Select-Object -Unique
foreach($ace in @($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))){
 if($ace.IsInherited -or $ace.IdentityReference.Value -notin $allowed -or
    $ace.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow){
   throw 'VI_FONT_INSTALL_PRIVATE_VAULT_ACCESS_RULE_MISMATCH'
 }
}
$backupDir=Join-Path $root ('FONT-ROLLBACK-'+$env:GITHUB_RUN_ID+'-'+$env:GITHUB_RUN_ATTEMPT)
if(Test-Path -LiteralPath $backupDir){throw 'VI_FONT_INSTALL_BACKUP_COLLISION'}
$backup=Join-Path $backupDir 'baseline-installed.apk'
$after=Join-Path $backupDir 'candidate-installed-verified.apk'
# The rollback directory inherits owner/SYSTEM/admin-only DACL from the trusted vault.
$null=New-Item -Path $backupDir -ItemType Directory -ErrorAction Stop

$tools='C:\TOOL\Android-SDK\build-tools'
$dirs=@(Get-ChildItem -LiteralPath $tools -Directory -ErrorAction Stop | Sort-Object Name -Descending)
$signer=$null;$aapt=$null
foreach($d in $dirs){
 if(-not $signer -and (Test-Path -LiteralPath (Join-Path $d.FullName 'apksigner.bat'))){
   $signer=Join-Path $d.FullName 'apksigner.bat'
 }
 if(-not $aapt -and (Test-Path -LiteralPath (Join-Path $d.FullName 'aapt.exe'))){
   $aapt=Join-Path $d.FullName 'aapt.exe'
 }
}
if(-not $signer -or -not $aapt){throw 'VI_FONT_INSTALL_ANDROID_BUILD_TOOLS_MISSING'}

# adb process wrapper avoids PowerShell 5.1 treating benign native stderr as exceptions.
function Invoke-ADB([string[]]$Cmd,[int]$Timeout=60000){
 foreach($arg in $Cmd){
  if([string]::IsNullOrEmpty($arg) -or $arg -match '\s' -or $arg.Contains('"')){
   throw 'VI_FONT_INSTALL_ADB_ARG_UNSAFE'
  }
 }
 $p=New-Object System.Diagnostics.ProcessStartInfo
 $p.FileName=$adb
 $p.Arguments=($Cmd -join ' ')
 $p.UseShellExecute=$false
 $p.RedirectStandardOutput=$true
 $p.RedirectStandardError=$true
 $p.CreateNoWindow=$true
 $process=[System.Diagnostics.Process]::Start($p)
 try{
  $stdout=$process.StandardOutput.ReadToEnd()
  $null=$process.StandardError.ReadToEnd()
  if(-not $process.WaitForExit($Timeout)){
   $process.Kill()
   throw 'VI_FONT_INSTALL_ADB_TIMEOUT'
  }
  return [PSCustomObject]@{Code=$process.ExitCode;Out=$stdout}
 }finally{$process.Dispose()}
}
function Read-PackageInfo([string]$File){
 $output=@(& $aapt dump badging $File 2>&1)
 if($LASTEXITCODE -ne 0){throw 'VI_FONT_INSTALL_AAPT_BADGING_FAILED'}
 $packageLines=@($output | Where-Object {"$_" -match "^package:\s+name='"})
 if($packageLines.Count -ne 1){throw 'VI_FONT_INSTALL_BADGING_PACKAGE_AMBIGUOUS'}
 $rx=[regex]::Match([string]$packageLines[0],"^package:\s+name='([^']+)'\s+versionCode='([0-9]+)'")
 if(-not $rx.Success -or $rx.Groups[1].Value -cne $pkg){
  throw 'VI_FONT_INSTALL_BADGING_PACKAGE_MISMATCH'
 }
 return $rx.Groups[2].Value
}
. (Join-Path $env:GITHUB_WORKSPACE 'poc\g1-p2-auto\apk-signer-digests.ps1')
function Read-Cert([string]$File){
 $result=@(& $signer verify --print-certs $File 2>&1)
 if($LASTEXITCODE -ne 0){throw 'VI_FONT_INSTALL_APK_SIGNATURE_INVALID'}
 $certs=@(Get-ApkSignerSha256Digests -OutputLines $result)
 if($certs.Count -ne 1){throw 'VI_FONT_INSTALL_CERT_PARSE_INVALID'}
 return [string]$certs[0]
}
$version=Read-PackageInfo $candidate
$candidateCert=Read-Cert $candidate
Write-Host ('VI_FONT_CANDIDATE_VERSION_CODE='+$version)
Write-Host 'VI_FONT_CANDIDATE_SIGNATURE_VALID=TRUE'
$devices=Invoke-ADB -Cmd @('devices','-l')
if($devices.Code -ne 0){throw 'VI_FONT_INSTALL_DEVICE_LIST_FAILED'}
$ids=@()
foreach($line in ($devices.Out -split '\r?\n')){
 if($line -match '^\s*(\S+)\s+device(?:\s|$)'){$ids += [string]$Matches[1]}
}
if($ids.Count -ne 1){throw 'VI_FONT_INSTALL_EXPECT_ONE_DEVICE'}
$serial=[string]$ids[0]
$model=Invoke-ADB -Cmd @('-s',$serial,'shell','getprop','ro.product.model')
if($model.Code -ne 0 -or $model.Out.Trim() -cne 'MiTV-ASTR0'){
 throw 'VI_FONT_INSTALL_TARGET_MODEL_MISMATCH'
}
Write-Host 'VI_FONT_EXACT_REDMITV_MODEL_PASS'

function Read-InstalledBase {
 $paths=Invoke-ADB -Cmd @('-s',$serial,'shell','pm','path',$pkg)
 if($paths.Code -ne 0){throw 'VI_FONT_INSTALL_PM_PATH_FAILED'}
 $list=@(($paths.Out -split '\r?\n') | Where-Object {$_ -match '^package:/'})
 # Only one installed base.apk is safe to restore with one adb install -r.
 if($list.Count -ne 1){throw 'VI_FONT_INSTALL_EXISTING_APK_NOT_SINGLE_BASE'}
 $match=[regex]::Match([string]$list[0],'^package:(/[A-Za-z0-9._~+%=/@-]+/base\.apk)\s*$')
 if(-not $match.Success){throw 'VI_FONT_INSTALL_EXISTING_APK_PATH_UNEXPECTED'}
 return $match.Groups[1].Value
}
$oldRemote=Read-InstalledBase
$pull=Invoke-ADB -Cmd @('-s',$serial,'pull',$oldRemote,$backup) -Timeout 120000
if($pull.Code -ne 0 -or -not (Test-Path -LiteralPath $backup -PathType Leaf)){
 throw 'VI_FONT_INSTALL_BASELINE_BACKUP_FAILED'
}
$baselineVersion=Read-PackageInfo $backup
$baselineCert=Read-Cert $backup
if($baselineVersion -cne $version){
 throw 'VI_FONT_INSTALL_VERSION_MISMATCH_NO_DOWNGRADE'
}
if($baselineCert -cne $candidateCert){
 throw 'VI_FONT_INSTALL_SIGNER_MISMATCH'
}
$baselineSha=(Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToLowerInvariant()
if($baselineSha -ceq $expectedCandidate){
 Write-Host 'VI_FONT_ALREADY_INSTALLED_CANDIDATE_SHA_PASS'
 Write-Host 'VI_FONT_NO_REINSTALL_NEEDED=TRUE'
 exit 0
}
$backupLength=(Get-Item -LiteralPath $backup).Length
if($backupLength -lt 1000000){throw 'VI_FONT_INSTALL_BASELINE_BACKUP_TOO_SMALL'}
Write-Host 'VI_FONT_BASELINE_PRIVATE_ROLLBACK_READY=TRUE'
Write-Host ('VI_FONT_BASELINE_SHA256='+$baselineSha)
Write-Host 'VI_FONT_VERSION_AND_SIGNER_COMPATIBLE=TRUE'
# Installation is explicitly approved by owner. -r means data-preserving replace.
# Never use -d, -t, uninstall, clear or reset. Same versionCode required.
$attempted=$false
try{
 $attempted=$true
 Write-Host 'VI_FONT_ADB_INSTALL_REPLACE_BEGIN'
 $install=Invoke-ADB -Cmd @('-s',$serial,'install','-r',$candidate) -Timeout 180000
 if($install.Code -ne 0 -or $install.Out -notmatch '(?m)^Success\s*$'){
  throw 'VI_FONT_INSTALL_ADB_REPLACE_NOT_CONFIRMED'
 }
 $newRemote=Read-InstalledBase
 $installed=Invoke-ADB -Cmd @('-s',$serial,'pull',$newRemote,$after) -Timeout 120000
 if($installed.Code -ne 0 -or -not (Test-Path -LiteralPath $after -PathType Leaf)){
  throw 'VI_FONT_INSTALL_POST_APK_PULL_FAILED'
 }
 $postSha=(Get-FileHash -LiteralPath $after -Algorithm SHA256).Hash.ToLowerInvariant()
 if($postSha -cne $expectedCandidate){
  throw 'VI_FONT_INSTALL_POST_APK_SHA_MISMATCH'
 }
 if((Read-PackageInfo $after) -cne $version -or (Read-Cert $after) -cne $candidateCert){
  throw 'VI_FONT_INSTALL_POST_PACKAGE_OR_CERT_MISMATCH'
 }
 Write-Host ('VI_FONT_INSTALLED_APK_SHA256='+$postSha)
 Write-Host 'VI_FONT_INSTALLED_DEBUG_APK_VERIFIED_PASS'
 Write-Host 'VI_FONT_INSTALL_MODE=REPLACE_KEEP_DATA'
 Write-Host 'VI_FONT_OLD_APK_RETAINED_PRIVATE_FOR_ROLLBACK=TRUE'
 Write-Host 'VI_FONT_GLYPH_VISUAL_ACCEPTANCE=PENDING_HUMAN'
 Write-Host 'VI_FONT_G1_G3_RESUME_REGRESSION=PENDING_HUMAN'
}catch{
 $failure=$_.Exception.Message
 Write-Host ('VI_FONT_INSTALL_VERIFY_FAILED_TYPE='+$_.Exception.GetType().Name)
 if($attempted){
  Write-Host 'VI_FONT_AUTOMATIC_ROLLBACK_BEGIN'
  try{
   $rollback=Invoke-ADB -Cmd @('-s',$serial,'install','-r',$backup) -Timeout 180000
   if($rollback.Code -ne 0 -or $rollback.Out -notmatch '(?m)^Success\s*$'){
    throw 'VI_FONT_INSTALL_ROLLBACK_COMMAND_FAILED'
   }
   $restoreRemote=Read-InstalledBase
   $temp=Join-Path $backupDir 'baseline-restored-check.apk'
   $restored=Invoke-ADB -Cmd @('-s',$serial,'pull',$restoreRemote,$temp) -Timeout 120000
   if($restored.Code -ne 0 -or -not (Test-Path -LiteralPath $temp -PathType Leaf)){
    throw 'VI_FONT_INSTALL_ROLLBACK_VERIFY_FAILED'
   }
   $restoredSha=(Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLowerInvariant()
   if($restoredSha -cne $baselineSha){
    throw 'VI_FONT_INSTALL_ROLLBACK_SHA_MISMATCH'
   }
   Write-Host 'VI_FONT_ROLLBACK_BASELINE_SHA_PASS'
  }catch{
   Write-Host 'VI_FONT_ROLLBACK_NOT_VERIFIED_MANUAL_RECOVERY_REQUIRED'
   throw 'VI_FONT_INSTALL_AND_ROLLBACK_HOLD'
  }
 }
 throw ('VI_FONT_INSTALL_FAILED_ROLLBACK_DONE_OR_NOT_ATTEMPTED_'+$failure)
}finally{
 if(Test-Path -LiteralPath $after -PathType Leaf){
  Remove-Item -LiteralPath $after -Force -ErrorAction SilentlyContinue
 }
}
Write-Host 'VI_FONT_OWNER_APPROVED_INSTALL_END'
)
 if(-not $match.Success){throw 'VI_FONT_INSTALL_EXISTING_APK_PATH_UNEXPECTED'}
 return $match.Groups[1].Value
}
$oldRemote=Read-InstalledBase
$pull=Invoke-ADB -Cmd @('-s',$serial,'pull',$oldRemote,$backup) -Timeout 120000
if($pull.Code -ne 0 -or -not (Test-Path -LiteralPath $backup -PathType Leaf)){
 throw 'VI_FONT_INSTALL_BASELINE_BACKUP_FAILED'
}
$baselineVersion=Read-PackageInfo $backup
$baselineCert=Read-Cert $backup
if($baselineVersion -cne $version){
 throw 'VI_FONT_INSTALL_VERSION_MISMATCH_NO_DOWNGRADE'
}
if($baselineCert -cne $candidateCert){
 throw 'VI_FONT_INSTALL_SIGNER_MISMATCH'
}
$baselineSha=(Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToLowerInvariant()
if($baselineSha -ceq $expectedCandidate){
 Write-Host 'VI_FONT_ALREADY_INSTALLED_CANDIDATE_SHA_PASS'
 Write-Host 'VI_FONT_NO_REINSTALL_NEEDED=TRUE'
 exit 0
}
$backupLength=(Get-Item -LiteralPath $backup).Length
if($backupLength -lt 1000000){throw 'VI_FONT_INSTALL_BASELINE_BACKUP_TOO_SMALL'}
Write-Host 'VI_FONT_BASELINE_PRIVATE_ROLLBACK_READY=TRUE'
Write-Host ('VI_FONT_BASELINE_SHA256='+$baselineSha)
Write-Host 'VI_FONT_VERSION_AND_SIGNER_COMPATIBLE=TRUE'
# Installation is explicitly approved by owner. -r means data-preserving replace.
# Never use -d, -t, uninstall, clear or reset. Same versionCode required.
$attempted=$false
try{
 $attempted=$true
 Write-Host 'VI_FONT_ADB_INSTALL_REPLACE_BEGIN'
 $install=Invoke-ADB -Cmd @('-s',$serial,'install','-r',$candidate) -Timeout 180000
 if($install.Code -ne 0 -or $install.Out -notmatch '(?m)^Success\s*$'){
  throw 'VI_FONT_INSTALL_ADB_REPLACE_NOT_CONFIRMED'
 }
 $newRemote=Read-InstalledBase
 $installed=Invoke-ADB -Cmd @('-s',$serial,'pull',$newRemote,$after) -Timeout 120000
 if($installed.Code -ne 0 -or -not (Test-Path -LiteralPath $after -PathType Leaf)){
  throw 'VI_FONT_INSTALL_POST_APK_PULL_FAILED'
 }
 $postSha=(Get-FileHash -LiteralPath $after -Algorithm SHA256).Hash.ToLowerInvariant()
 if($postSha -cne $expectedCandidate){
  throw 'VI_FONT_INSTALL_POST_APK_SHA_MISMATCH'
 }
 if((Read-PackageInfo $after) -cne $version -or (Read-Cert $after) -cne $candidateCert){
  throw 'VI_FONT_INSTALL_POST_PACKAGE_OR_CERT_MISMATCH'
 }
 Write-Host ('VI_FONT_INSTALLED_APK_SHA256='+$postSha)
 Write-Host 'VI_FONT_INSTALLED_DEBUG_APK_VERIFIED_PASS'
 Write-Host 'VI_FONT_INSTALL_MODE=REPLACE_KEEP_DATA'
 Write-Host 'VI_FONT_OLD_APK_RETAINED_PRIVATE_FOR_ROLLBACK=TRUE'
 Write-Host 'VI_FONT_GLYPH_VISUAL_ACCEPTANCE=PENDING_HUMAN'
 Write-Host 'VI_FONT_G1_G3_RESUME_REGRESSION=PENDING_HUMAN'
}catch{
 $failure=$_.Exception.Message
 Write-Host ('VI_FONT_INSTALL_VERIFY_FAILED_TYPE='+$_.Exception.GetType().Name)
 if($attempted){
  Write-Host 'VI_FONT_AUTOMATIC_ROLLBACK_BEGIN'
  try{
   $rollback=Invoke-ADB -Cmd @('-s',$serial,'install','-r',$backup) -Timeout 180000
   if($rollback.Code -ne 0 -or $rollback.Out -notmatch '(?m)^Success\s*$'){
    throw 'VI_FONT_INSTALL_ROLLBACK_COMMAND_FAILED'
   }
   $restoreRemote=Read-InstalledBase
   $temp=Join-Path $backupDir 'baseline-restored-check.apk'
   $restored=Invoke-ADB -Cmd @('-s',$serial,'pull',$restoreRemote,$temp) -Timeout 120000
   if($restored.Code -ne 0 -or -not (Test-Path -LiteralPath $temp -PathType Leaf)){
    throw 'VI_FONT_INSTALL_ROLLBACK_VERIFY_FAILED'
   }
   $restoredSha=(Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLowerInvariant()
   if($restoredSha -cne $baselineSha){
    throw 'VI_FONT_INSTALL_ROLLBACK_SHA_MISMATCH'
   }
   Write-Host 'VI_FONT_ROLLBACK_BASELINE_SHA_PASS'
  }catch{
   Write-Host 'VI_FONT_ROLLBACK_NOT_VERIFIED_MANUAL_RECOVERY_REQUIRED'
   throw 'VI_FONT_INSTALL_AND_ROLLBACK_HOLD'
  }
 }
 throw ('VI_FONT_INSTALL_FAILED_ROLLBACK_DONE_OR_NOT_ATTEMPTED_'+$failure)
}finally{
 if(Test-Path -LiteralPath $after -PathType Leaf){
  Remove-Item -LiteralPath $after -Force -ErrorAction SilentlyContinue
 }
}
Write-Host 'VI_FONT_OWNER_APPROVED_INSTALL_END'
