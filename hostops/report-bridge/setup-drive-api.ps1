# One-time interactive Windows Owner setup; no administrator required.
# Download OAuth Desktop client JSON yourself from Google Cloud, not from chat.
param([string]$ClientJson,[string]$Account)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
if(-not $ClientJson){$ClientJson=Read-Host 'Full path to downloaded OAuth Desktop client JSON'}
$ClientJson=$ClientJson.Trim().Trim('"')
if(-not (Test-Path -LiteralPath $ClientJson -PathType Leaf)){throw 'OAUTH_CLIENT_JSON_MISSING'}
if(-not $Account){$Account=Read-Host 'Google account owning the Brain Inbox'}
if($Account -notmatch '^[^@\s]+@[^@\s]+$'){throw 'GOOGLE_ACCOUNT_REQUIRED'}
$ref='ccb686eccac4b07bb527e9235e5b84247c21e5bc'
$homeDir=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\ReportBridgeApi'
$code=Join-Path $homeDir ('source-'+$ref)
$venv=Join-Path $homeDir 'venv'
New-Item -ItemType Directory -Path $code -Force|Out-Null
$files=@{
 'report_bridge.py'='b1e32d16339103f8bbca7fcf1b0fd36e40052754'
 'drive_api.py'='fca9a07e9f7b604fab5337577e99d78835ab67fc'
 'test_report_bridge.py'='fc782c23d91197eb69cef520b9c811c5807f9b4b'
 'test_drive_api.py'='c8bd65fa705e044d706221df31d841a3f0850992'
}
foreach($name in $files.Keys){
 $path=Join-Path $code $name
 $url="https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/$ref/hostops/report-bridge/$name"
 Invoke-WebRequest -Uri $url -OutFile $path
 $hash=(& git hash-object --no-filters $path).Trim()
 if($LASTEXITCODE -ne 0 -or $hash -cne $files[$name]){throw 'PINNED_SOURCE_HASH_MISMATCH'}
}
if(-not (Test-Path -LiteralPath (Join-Path $venv 'Scripts\python.exe'))){
 & py -3 -m venv $venv
 if($LASTEXITCODE -ne 0){throw 'VENV_SETUP_FAILED'}
}
$python=Join-Path $venv 'Scripts\python.exe'
& $python -m pip install google-auth-oauthlib requests
if($LASTEXITCODE -ne 0){throw 'DEPENDENCY_SETUP_FAILED'}
& $python -m unittest discover -s $code -p 'test_*.py'
if($LASTEXITCODE -ne 0){throw 'SOURCE_TESTS_FAILED'}
& $python (Join-Path $code 'drive_api.py') enroll --client $ClientJson --account $Account
if($LASTEXITCODE -ne 0){throw 'OAUTH_ENROLLMENT_HOLD'}
Write-Output 'REPORT_BRIDGE_API_ENROLLMENT_COMPLETE'
Write-Output 'No report uploaded yet; HostOps must run live validation.'
