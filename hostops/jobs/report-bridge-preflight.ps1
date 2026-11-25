Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win'){throw 'RUNNER_REQUIRED'}
$install=@()
foreach($base in @($env:ProgramFiles,[Environment]::GetEnvironmentVariable('ProgramFiles(x86)'))){
 if($base){$p=Join-Path $base 'Google\Drive File Stream';if(Test-Path -LiteralPath $p -PathType Container){$install+=Get-ChildItem -LiteralPath $p -Directory -ErrorAction SilentlyContinue|Where-Object{Test-Path -LiteralPath (Join-Path $_.FullName 'GoogleDriveFS.exe') -PathType Leaf}}}
}
$proc=@(Get-Process -Name 'GoogleDriveFS' -ErrorAction SilentlyContinue)
Write-Output ('RB_DRIVE_DESKTOP_SYSTEM_INSTALL='+$(if($install.Count -gt 0){'YES'}else{'NOT_FOUND'}))
Write-Output ('RB_DRIVE_DESKTOP_PROCESS_COUNT='+$proc.Count)
Write-Output 'RB_PREFLIGHT_SCOPE=SYSTEM_INSTALL_AND_PROCESS_ONLY'
