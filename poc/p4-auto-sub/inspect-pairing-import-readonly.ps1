# One owner Redmi: read-only existence/name checks. No secret/file body output.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_EVENT_NAME -cne 'pull_request' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:GITHUB_HEAD_REF -cne 'feature/p4-native-auto-sub-g2-20261111' -or
    $env:GITHUB_BASE_REF -cne 'feature/g2-refresh-vietsub-inplace-20261111' -or
    $env:GITHUB_REF -cne 'refs/pull/120/merge') {
    throw 'P4_PAIR_READONLY_STOP_OWNER_CONTEXT'
}
$event=Get-Content -LiteralPath $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json
if ([int]$event.number -ne 120 -or
    $event.pull_request.head.repo.full_name -cne $env:GITHUB_REPOSITORY -or
    $event.pull_request.user.login -cne 'trung-via') {
    throw 'P4_PAIR_READONLY_STOP_OWNER_PR'
}
$adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf) -or
    @(Get-Process -Name adb -ErrorAction SilentlyContinue).Count -ne 1) {
    throw 'P4_PAIR_READONLY_STOP_PINNED_RUNNING_ADB_REQUIRED'
}
if (-not $env:RUNNER_TEMP) {throw 'P4_PAIR_READONLY_STOP_NO_RUNNER_TEMP'}
$script:callIndex=0
function Invoke-QuietAdb([string[]]$argsList) {
    $script:callIndex++
    $base=Join-Path $env:RUNNER_TEMP ('p4-pair-read-'+$env:GITHUB_RUN_ID+'-'+$script:callIndex)
    $stdout=$base+'-out.txt'
    $stderr=$base+'-err.txt'
    if ((Test-Path -LiteralPath $stdout) -or (Test-Path -LiteralPath $stderr)) {
        throw 'P4_PAIR_READONLY_STOP_TEMP_COLLISION'
    }
    try {
        $p=Start-Process -FilePath $adb -ArgumentList $argsList -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
        $output=if (Test-Path -LiteralPath $stdout) { Get-Content -LiteralPath $stdout -Raw } else { '' }
        return @{exit=[int]$p.ExitCode; output=[string]$output}
    } finally {
        Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
    }
}
$r=Invoke-QuietAdb @('devices')
if ($r.exit -ne 0) {throw 'P4_PAIR_READONLY_STOP_ADB_DEVICES_FAILED'}
$auth=@($r.output -split "\r?\n" | Where-Object {$_ -match '^[^\s]+\s+device(\s|$)'})
$denied=@($r.output -split "\r?\n" | Where-Object {$_ -match '^[^\s]+\s+(unauthorized|offline)(\s|$)'})
if ($auth.Count -ne 1 -or $denied.Count -ne 0) {
    throw 'P4_PAIR_READONLY_STOP_SINGLE_AUTHORIZED_DEVICE_REQUIRED'
}
$serial=(([string]$auth[0]).Trim() -split '\s+')[0]
foreach($check in @(
    @('ro.product.model','MiTV-ASTR0'),
    @('ro.build.version.sdk','30'),
    @('ro.product.cpu.abi','armeabi-v7a')
)) {
    $p=Invoke-QuietAdb @('-s',$serial,'shell','getprop',$check[0])
    if ($p.exit -ne 0 -or $p.output.Trim() -cne $check[1]) {
        throw 'P4_PAIR_READONLY_STOP_TV_IDENTITY_MISMATCH'
    }
}
$pkg='com.spacesarmat.omp.test'
$pm=Invoke-QuietAdb @('-s',$serial,'shell','pm','path',$pkg)
if ($pm.exit -ne 0 -or $pm.output -notmatch 'package:/') {
    throw 'P4_PAIR_READONLY_STOP_DEBUG_APP_NOT_FOUND'
}
$runas=Invoke-QuietAdb @('-s',$serial,'shell','run-as',$pkg,'pwd')
if ($runas.exit -ne 0) {throw 'P4_PAIR_READONLY_STOP_RUN_AS_UNAVAILABLE'}
function Exists-PrivateFile([string]$path) {
    $r=Invoke-QuietAdb @('-s',$serial,'shell','run-as',$pkg,'ls',$path)
    return $r.exit -eq 0
}
$staged=Exists-PrivateFile 'files/p4-owner-bootstrap-v1.txt'
$xml='shared_prefs/p4-tv-paired-pc-v2-tls.xml'
$prefs=Exists-PrivateFile $xml
$namesPresent=$false
if ($prefs) {
    # grep -q stays inside the app UID. Only its exit status is collected.
    $count=0
    foreach($name in @('host','port','iv','sealed')) {
        $result=Invoke-QuietAdb @('-s',$serial,'shell','run-as',$pkg,'grep','-q',$name,$xml)
        if($result.exit -eq 0){$count++}
    }
    $namesPresent=($count -eq 4)
}
Write-Host ('P4_PAIR_STAGED_PLAINTEXT_EXISTS='+$staged.ToString().ToLowerInvariant())
Write-Host ('P4_PAIR_ENCRYPTED_PREFS_EXISTS='+$prefs.ToString().ToLowerInvariant())
Write-Host ('P4_PAIR_REQUIRED_FIELDS_EXIST='+$namesPresent.ToString().ToLowerInvariant())
if (-not $staged -and $prefs -and $namesPresent) {
    Write-Host 'P4_PAIR_LOCAL_IMPORT_PERSISTENCE_INDICATORS_PASS=true'
} else {
    Write-Host 'P4_PAIR_LOCAL_IMPORT_PERSISTENCE_INDICATORS_PASS=false'
}
Write-Host 'P4_PAIR_KEYSTORE_DECRYPT_AND_HTTPS_NOT_VERIFIED=true'
Write-Host 'P4_PAIR_READONLY_NO_APP_OR_NETWORK_MUTATION=true'
$global:LASTEXITCODE=0
