# Retain G1+P2 ARM32 Debug APK outside GitHub Actions RUNNER_TEMP.
# Authorized for existing Brain-gated build only; NEVER upload/install/publish.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SourceCommit)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Stop-Retention([string]$Reason) { throw ('G1P2_PRIVATE_RETENTION_HOLD: ' + $Reason) }
function Guard-NoReparse([string]$Path) {
    if ((Get-Item -LiteralPath $Path -Force -ErrorAction Stop).Attributes -band
        [IO.FileAttributes]::ReparsePoint) { Stop-Retention 'REPARSE_POINT_DENIED' }
}
function Restrict-Directory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -ErrorAction Stop | Out-Null
    }
    Guard-NoReparse $Path
    # NTFS owner, SYSTEM and local Administrators only. No PUBLIC/Users ACE.
    $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $safe = New-Object Security.AccessControl.DirectorySecurity
    $safe.SetAccessRuleProtection($true,$false)
    foreach ($sid in @($owner,
        (New-Object Security.Principal.SecurityIdentifier('S-1-5-18')),
        (New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new(
            $sid,
            [Security.AccessControl.FileSystemRights]::FullControl,
            ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
             [Security.AccessControl.InheritanceFlags]::ObjectInherit),
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow)
        $safe.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $safe -ErrorAction Stop
    # Verify explicit allow ACL only; do not proceed on shared-access folder.
    $actual = Get-Acl -LiteralPath $Path
    $allowedSids = @($owner.Value,'S-1-5-18','S-1-5-32-544')
    foreach ($ace in $actual.Access) {
        $sid = $ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        if ($ace.AccessControlType -ne 'Allow' -or $sid -notin $allowedSids) {
            Stop-Retention 'PRIVATE_DIRECTORY_ACL_NOT_EXCLUSIVE'
        }
    }
}
function Read-Tool([string]$Name) {
    $base = Join-Path 'C:\TOOL\Android-SDK' 'build-tools'
    $found = @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction Stop |
        Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName $Name } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if ($found.Count -lt 1) { Stop-Retention ('MISSING_' + $Name) }
    return $found[0]
}
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:GITHUB_REF -cne 'refs/heads/main' -or
    $env:GITHUB_EVENT_NAME -cne 'push' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_WORKFLOW_REF -cne 'trung-via/torrent-tv-vietsub/.github/workflows/tv-g1p2-auto-debug.yml@refs/heads/main' -or
    $env:G1P2_AUTO_BRAIN_APPROVED -cne 'true' -or
    $env:G1P2_AUTO_SOURCE_SHA -cne $SourceCommit -or
    $env:GITHUB_SHA -cne $SourceCommit) {
    Stop-Retention 'TRUSTED_AUTO_MAIN_BUILD_CONTEXT_REQUIRED'
}
if ($SourceCommit -cnotmatch '^[a-f0-9]{40}$' -or
    $env:GITHUB_RUN_ID -notmatch '^[0-9]+$' -or
    $env:GITHUB_RUN_ATTEMPT -notmatch '^[0-9]+$') {
    Stop-Retention 'INVALID_SHA_OR_RUN'
}
$run = $env:GITHUB_RUN_ID
$attempt = $env:GITHUB_RUN_ATTEMPT
$sourceDir = Join-Path $env:RUNNER_TEMP (
    'p1-g1-prod-' + $run + '-' + $attempt + '\android\app\build\outputs\apk\debug')
if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) { Stop-Retention 'BUILD_OUTPUT_MISSING' }
Guard-NoReparse $sourceDir
$apk = Join-Path $sourceDir 'app-armeabi-v7a-debug.apk'
$manifest = Join-Path $sourceDir 'SHA256SUMS-G1P2.txt'
$evidence = Join-Path $sourceDir 'G1P2-BUILD-EVIDENCE.txt'
foreach ($file in @($apk,$manifest,$evidence)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Stop-Retention 'BUILD_FILE_MISSING' }
    Guard-NoReparse $file
}
$apkHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
$lines = @(Get-Content -LiteralPath $manifest)
$matching = @($lines | Where-Object { $_ -match '^([a-fA-F0-9]{64})  app-armeabi-v7a-debug\.apk$' })
if ($matching.Count -ne 1 -or $matching[0].Substring(0,64).ToLowerInvariant() -cne $apkHash) {
    Stop-Retention 'SHA256_MANIFEST_MISMATCH'
}
$evidenceLines = @(Get-Content -LiteralPath $evidence -Encoding UTF8)
if (@($evidenceLines | Where-Object { $_ -ceq "app_commit=$SourceCommit" }).Count -ne 1 -or
    @($evidenceLines | Where-Object { $_ -ceq "run_id=$run" }).Count -ne 1) {
    Stop-Retention 'EVIDENCE_SOURCE_RUN_MISMATCH'
}
$aapt = Read-Tool 'aapt.exe'
$badging = @(& $aapt dump badging $apk 2>&1)
if ($LASTEXITCODE -ne 0 -or @($badging | Where-Object {
    "$_" -match "^package:\s+name='com\.spacesarmat\.omp\.test'"
}).Count -ne 1) { Stop-Retention 'APK_PACKAGE_NOT_PROVEN' }

# Runner installation root is stable. Do not put retained APK under _work/_temp.
$root = 'C:\TOOL\TorrentTV-Runner'
if (-not (Test-Path -LiteralPath $root -PathType Container)) { Stop-Retention 'RUNNER_INSTALL_ROOT_ABSENT' }
Guard-NoReparse $root
$private = Join-Path $root 'private-artifacts'
$vault = Join-Path $private 'G1P2'
Restrict-Directory $private
Restrict-Directory $vault
$name = 'run-' + $run + '-' + $attempt
$target = Join-Path $vault $name
$partial = Join-Path $vault ('.partial-' + $name)
if ((Test-Path -LiteralPath $target) -or (Test-Path -LiteralPath $partial)) {
    Stop-Retention 'RETAINED_APK_ALREADY_EXISTS_NO_OVERWRITE'
}
Restrict-Directory $partial
Copy-Item -LiteralPath $apk -Destination (Join-Path $partial 'app-armeabi-v7a-debug.apk') -ErrorAction Stop
Copy-Item -LiteralPath $manifest -Destination (Join-Path $partial 'SHA256SUMS-G1P2.txt') -ErrorAction Stop
Copy-Item -LiteralPath $evidence -Destination (Join-Path $partial 'G1P2-BUILD-EVIDENCE.txt') -ErrorAction Stop
$check = (Get-FileHash -LiteralPath (Join-Path $partial 'app-armeabi-v7a-debug.apk') -Algorithm SHA256).Hash.ToLowerInvariant()
if ($check -cne $apkHash) { Stop-Retention 'PRIVATE_COPY_HASH_MISMATCH' }
Move-Item -LiteralPath $partial -Destination $target -ErrorAction Stop
Guard-NoReparse $target
# Preserve the exact SHA-approved bytes FIRST; signer verification is a
# separate fail-closed acceptance gate. If the signer tool fails or its output
# changes, we retain a private QUARANTINED copy for offline diagnosis instead
# of losing the APK when RUNNER_TEMP is cleaned.
$statusPath = Join-Path $target 'SIGNATURE-STATUS.txt'
Set-Content -LiteralPath $statusPath -Value 'SIGNATURE_HOLD_PENDING_VERIFY' -Encoding ascii
Write-Host ('G1P2_PRIVATE_APK_QUARANTINED_LOCAL_ONLY run={0} attempt={1} sha256={2} path={3}' -f
    $run,$attempt,$apkHash,$target)
$signer = Read-Tool 'apksigner.bat'
$retainedApk = Join-Path $target 'app-armeabi-v7a-debug.apk'
$verify = @(& $signer verify --print-certs $retainedApk 2>&1)
$verifyExit = $LASTEXITCODE
$signerText = $verify -join [Environment]::NewLine
$certDigests = [regex]::Matches($signerText,
    '(?im)^\s*Signer\s+#\d+\s+certificate\s+SHA-256\s+digest:\s*([a-f0-9]{64})\s*$')
Write-Host ('G1P2_APKSIGNER_DIAGNOSTIC exit={0} matched_cert_lines={1} output_lines={2}' -f
    $verifyExit,$certDigests.Count,$verify.Count)
if ($verifyExit -ne 0 -or $certDigests.Count -lt 1) {
    Stop-Retention 'APK_SIGNATURE_NOT_VERIFIED_RETAINED_QUARANTINED'
}
Set-Content -LiteralPath $statusPath -Value 'SIGNATURE_VERIFIED' -Encoding ascii
Write-Host ('G1P2_PRIVATE_APK_RETAINED_LOCAL_ONLY run={0} attempt={1} sha256={2} path={3}' -f
    $run,$attempt,$apkHash,$target)
Write-Host 'G1P2_PRIVATE_STORE_NOT_PUBLIC_NO_ADB_INSTALL'
