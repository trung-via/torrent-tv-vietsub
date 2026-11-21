# READ-ONLY diagnosis: existing Torrent TV OwnerAgent scheduled task executable.
# Run as the logged-in Windows owner (ordinary PowerShell, no Administrator).
# NEVER prints account, SID, executable path, hash, token, movie name or key.
# NEVER starts/stops/changes a task, modifies ACL, opens LAN, calls provider.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Check([string]$Key, [object]$Value) {
    Write-Host ('P3_P4_TASK_EXE_' + $Key + '=' + [string]$Value)
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($env:CI -eq 'true' -or $env:GITHUB_ACTIONS -eq 'true' -or
    -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $null -eq $identity.User -or
    $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20')) {
    throw 'P3_P4_TASK_EXE_OWNER_INTERACTIVE_REQUIRED'
}
$task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -ErrorAction Stop
if ($null -eq $task -or @($task.Actions).Count -ne 1) {
    Write-Check 'ONE_ACTION' 'FALSE'
    return
}
Write-Check 'ONE_ACTION' 'TRUE'
$exeText = ([string](@($task.Actions)[0].Execute)).Trim().Trim('"')
$current = [string][Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$filename = [IO.Path]::GetFileName($exeText)
$currentName = [IO.Path]::GetFileName($current)
$kind = if ($filename -ieq 'pwsh.exe') { 'PWSH' }
    elseif ($filename -ieq 'powershell.exe') { 'WINDOWS_POWERSHELL' }
    else { 'OTHER_OR_UNRESOLVED' }
Write-Check 'TASK_KIND' $kind
Write-Check 'CURRENT_KIND' $(if($currentName -ieq 'pwsh.exe'){'PWSH'}elseif($currentName -ieq 'powershell.exe'){'WINDOWS_POWERSHELL'}else{'OTHER'})
$absolute = [IO.Path]::IsPathRooted($exeText)
Write-Check 'TASK_ABSOLUTE' $absolute.ToString().ToUpperInvariant()
Write-Check 'SAME_PATH' $(if ($absolute -and [IO.Path]::IsPathRooted($current)) {
 [IO.Path]::GetFullPath($exeText).Equals([IO.Path]::GetFullPath($current),
    [StringComparison]::OrdinalIgnoreCase).ToString().ToUpperInvariant()
} else { 'UNKNOWN' })
if (-not $absolute) {
    Write-Check 'TASK_EXISTS' 'UNKNOWN_NONABSOLUTE'
    Write-Check 'TASK_SIGNATURE' 'NOT_CHECKED'
    Write-Check 'TASK_INSTALL_SCOPE' 'NONABSOLUTE'
    Write-Check 'TASK_VERSION_MAJOR' 'UNKNOWN'
    return
}
$full = [IO.Path]::GetFullPath($exeText)
$exists = [IO.File]::Exists($full)
Write-Check 'TASK_EXISTS' $exists.ToString().ToUpperInvariant()
$programFiles = [Environment]::GetFolderPath('ProgramFiles')
$windows = [Environment]::GetFolderPath('Windows')
$scope = if ($full.StartsWith((Join-Path $programFiles 'PowerShell') + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase)) { 'PROGRAM_FILES_POWERSHELL' }
    elseif ($full.StartsWith((Join-Path $windows 'System32\WindowsPowerShell') + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase)) { 'WINDOWS_POWERSHELL' }
    else { 'OTHER' }
Write-Check 'TASK_INSTALL_SCOPE' $scope
if (-not $exists) {
    Write-Check 'TASK_SIGNATURE' 'NOT_CHECKED'
    Write-Check 'TASK_VERSION_MAJOR' 'UNKNOWN'
    return
}
try {
    $signature = Get-AuthenticodeSignature -LiteralPath $full -ErrorAction Stop
    $signatureStatus = if ($signature.Status -eq 'Valid' -and
        $signature.SignerCertificate.Subject -match '(^|,\s*)CN=Microsoft (Corporation|Code Signing PCA)') {
        'MICROSOFT_VALID'
    } elseif ($signature.Status -eq 'Valid') { 'OTHER_VALID' }
      else { 'INVALID_OR_UNSIGNED' }
} catch { $signatureStatus = 'ERROR' }
Write-Check 'TASK_SIGNATURE' $signatureStatus
try {
    $major = [int]([Diagnostics.FileVersionInfo]::GetVersionInfo($full).FileMajorPart)
    Write-Check 'TASK_VERSION_MAJOR' $major
} catch { Write-Check 'TASK_VERSION_MAJOR' 'UNKNOWN' }
Write-Check 'READ_ONLY' 'TRUE'
