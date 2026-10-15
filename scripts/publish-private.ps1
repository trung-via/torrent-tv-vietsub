#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Owner = 'trung-via',
    [string]$RepoName = 'torrent-tv-vietsub'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$contract = Join-Path $root 'docs\PROJECT_CONTRACT.md'
if (-not (Test-Path -LiteralPath $contract)) { throw 'Project contract is missing. Extract the complete ZIP before publishing.' }
foreach ($command in @('git', 'gh')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Missing executable: $command. Install Git and GitHub CLI first." }
}
$ErrorActionPreference = 'Continue'
& gh auth status *> $null
$authStatus = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($authStatus -ne 0) { throw 'GitHub CLI not logged in. Run: gh auth login' }

$full = "$Owner/$RepoName"
Write-Host "Target GitHub repo: $full (PRIVATE)"
$ErrorActionPreference = 'Continue'
& gh repo view $full --json name *> $null
$repoViewStatus = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($repoViewStatus -eq 0) { throw "Repository $full already exists. Stopping to avoid changing an existing repo." }

if (Test-Path -LiteralPath (Join-Path $root '.git')) { throw 'This starter already has a .git directory. Stopping; inspect it manually.' }
$ancestor = (Get-Item -LiteralPath $root).Parent
while ($null -ne $ancestor) {
    if (Test-Path -LiteralPath (Join-Path $ancestor.FullName '.git')) {
        throw "Starter is nested under a Git worktree ($($ancestor.FullName)). Extract into an independent folder."
    }
    $ancestor = $ancestor.Parent
}

& git -C $root init -b main
if ($LASTEXITCODE -ne 0) { throw 'git init failed' }
& git -C $root add --all
if ($LASTEXITCODE -ne 0) { throw 'git add failed' }
& git -C $root commit -m 'docs: establish Torrent TV Vietsub project contract v1'
if ($LASTEXITCODE -ne 0) { throw 'git commit failed. Check your git user.name and user.email.' }
& gh repo create $full --private --source $root --remote origin --push --description 'Private Android TV client for authorized torrent streams with Vietnamese subtitles; Windows/NAS TorrServer backend'
if ($LASTEXITCODE -ne 0) { throw 'GitHub publish failed. Inspect local git state and GitHub repo status before retrying (do not rerun blindly).' }
Write-Host "CREATED_PRIVATE_REPO=https://github.com/$full"
Write-Host 'No AIOS task was dispatched; no application code or TV APK has been built.'
