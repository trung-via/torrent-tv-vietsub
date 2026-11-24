# Prepare one native AGY browser test, requiring Chrome's own user approval.
# No change to existing Chrome/WakeHub, no auto approval, no forced debug ports.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$chrome=Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'
$pwsh=(Get-Command pwsh -ErrorAction Stop).Source
$agy=Get-Command agy -ErrorAction Stop
$help=(& agy --help 2>&1 | Out-String)
if($help -notmatch '--prompt-interactive' -or $help -notmatch '--model'){throw 'AGY_INTERACTIVE_OPTION_UNVERIFIED'}
if(-not (Test-Path -LiteralPath $chrome -PathType Leaf)){throw 'CHROME_MISSING'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$profile=Join-Path $root 'ChromeProfile'
$run=Join-Path $root ('spiderman-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -Force | Out-Null
$prompt='/browser Use Gemini 4 Hydrogen Low for this browser task if supported; do not silently switch models. Use only the dedicated TorrentTV Chrome window/profile with explicit owner permission, not other tabs or profiles. Open https://www.opensubtitles.org/ using normal permitted browsing. Search for Spider-Man: Brand New Day (2026), English subtitle, WEB-DL 1080p; compare the actual release metadata with selezen and MovieDalen audio label (not necessarily release group). If access is challenged, login required, denied, or rate-limited, stop and report; do not circumvent restrictions. Do not use API, guess IDs, reuse cache, or download from unrelated websites. If allowed, use the genuine subtitle download control; report actual release name, detail URL, legitimate download URL, and actual result. Never inspect cookies, credentials, other tabs, or user files. Report whether native browser and requested subagent model were actually used. This is a diagnostic only, no translation or TV changes.'
$launcher=@'
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Set-Location -LiteralPath $PSScriptRoot
$Host.UI.RawUI.WindowTitle='TorrentTV - AGY Native Browser Test'
Write-Host 'TorrentTV isolated Chrome: enable Allow remote debugging on chrome://inspect/#remote-debugging. Do not enable it on WakeHub or other profiles.'
Write-Host 'The next command starts a single Hydrogen Low browser test. Approve only the dedicated Chrome instance if Chrome asks.'
Read-Host 'After enabling debugging on the dedicated Chrome window, press Enter' | Out-Null
$prompt=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'prompt.txt') -Raw -Encoding UTF8
& agy --model gemini-4-hydrogen-low --sandbox -i $prompt
'@
[IO.File]::WriteAllText((Join-Path $run 'prompt.txt'),$prompt,[Text.UTF8Encoding]::new($false))
$launch=Join-Path $run 'start-test.ps1'
[IO.File]::WriteAllText($launch,$launcher,[Text.UTF8Encoding]::new($false))
Start-Process -FilePath $chrome -ArgumentList @('--user-data-dir="'+$profile+'"','--new-window','chrome://inspect/#remote-debugging')
Start-Process -FilePath $pwsh -ArgumentList @('-NoProfile','-NoExit','-File',('"'+$launch+'"')) -WorkingDirectory $run
$code='NATIVE_BROWSER_SETUP_LAUNCHED_AWAIT_OWNER_CONSENT'
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
