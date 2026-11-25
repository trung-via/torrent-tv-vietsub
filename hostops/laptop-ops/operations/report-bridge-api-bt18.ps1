# RB02 live API validation of the original BT18 report; no provider/TV calls.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.nonce -cnotmatch '^[a-f0-9]{32}$' -or $rq.source_commit -cnotmatch '^[a-f0-9]{40}$'){throw 'REQUEST_INVALID'}
$source='ad010d992cd69cec1dc28185d538392efe8e04fe'
$nonce='25e73e80cfce49728e4f6c1402e6cefb'
$homeDir=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\ReportBridgeApi'
$code=Join-Path $homeDir 'source-ccb686eccac4b07bb527e9235e5b84247c21e5bc'
$python=Join-Path $homeDir 'venv\Scripts\python.exe'
$desktopBefore=@(Get-Process -Name 'GoogleDriveFS' -ErrorAction SilentlyContinue).Count
$v=[ordered]@{schema='TTV-RB02-API-OWNER-V1';nonce=$rq.nonce;source_commit=$rq.source_commit;original_source=$source;original_nonce=$nonce;state='HOLD';reason='LOCAL_SETUP_MISSING';tests='NOT_RUN';desktop_before=$desktopBefore;desktop_after=$desktopBefore;sha256='';bytes=0;file_count=0}
$dest=Join-Path $spool ('Receipts\report-bridge-api-'+$rq.nonce+'.json')
function Save-Receipt {
 $v.desktop_after=@(Get-Process -Name 'GoogleDriveFS' -ErrorAction SilentlyContinue).Count
 $tmp=$dest+'.tmp'
 [IO.File]::WriteAllText($tmp,($v|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
 [IO.File]::Move($tmp,$dest)
}
$files=@{
 'report_bridge.py'='b1e32d16339103f8bbca7fcf1b0fd36e40052754'
 'drive_api.py'='fca9a07e9f7b604fab5337577e99d78835ab67fc'
 'test_report_bridge.py'='fc782c23d91197eb69cef520b9c811c5807f9b4b'
 'test_drive_api.py'='c8bd65fa705e044d706221df31d841a3f0850992'
}
if(-not (Test-Path -LiteralPath $python -PathType Leaf)){Save-Receipt;return}
foreach($n in $files.Keys){
 $p=Join-Path $code $n
 if(-not (Test-Path -LiteralPath $p -PathType Leaf)){Save-Receipt;return}
 $h=(& git hash-object --no-filters $p 2>$null|Out-String).Trim()
 if($LASTEXITCODE -ne 0 -or $h -cne $files[$n]){$v.reason='SOURCE_HASH_MISMATCH';Save-Receipt;return}
}
& $python -B -m unittest discover -s $code -p 'test_*.py' *> $null
if($LASTEXITCODE -ne 0){$v.reason='SOURCE_TESTS_FAILED';$v.tests='FAIL';Save-Receipt;return}
$v.tests='PASS'
$raw=& $python -B (Join-Path $code 'drive_api.py') publish --source $source --nonce $nonce 2>$null
$exit=$LASTEXITCODE
try{$a=($raw|Out-String)|ConvertFrom-Json -AsHashtable}catch{$v.reason='PUBLISH_RECEIPT_INVALID';Save-Receipt;return}
if($exit -ne 0){
 $v.reason='PUBLISH_FAILED'
 if($a.state -ceq 'HOLD' -and $a.reason -cmatch '^[A-Z0-9_]{3,80}$'){$v.reason=$a.reason}
 Save-Receipt;return
}
if($a.state -cne 'API_UPLOAD_VERIFIED' -or $a.source -cne $source -or $a.nonce -cne $nonce -or $a.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $a.bytes -le 0 -or $a.bytes -gt 5242880 -or $a.file_count -lt 6 -or $a.file_count -gt 100){$v.reason='PUBLISH_RECEIPT_INVALID';Save-Receipt;return}
$v.state='API_UPLOAD_VERIFIED'
$v.reason='NONE'
$v.sha256=$a.sha256
$v.bytes=[long]$a.bytes
$v.file_count=[int]$a.file_count
Save-Receipt
