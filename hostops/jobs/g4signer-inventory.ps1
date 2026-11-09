# G4 signer and private APK handoff readiness — READ-ONLY, owner-only HostOps job.
# Does not create/read keystore bytes, enumerate private directories, print paths,
# invoke signing/Gradle/ADB, create/delete files or inspect other services.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:GITHUB_EVENT_NAME -cne 'issue_comment' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows') {
    throw 'G4_SIGNER_PROBE_STOP_BAD_RUNNER_OR_EVENT'
}
$workRoot = [IO.Path]::GetFullPath('C:\TOOL\TorrentTV-Runner\_work').TrimEnd('\') + '\'
foreach ($name in @('GITHUB_WORKSPACE','RUNNER_TEMP','RUNNER_WORKSPACE','GITHUB_RUN_ID')) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) { throw 'G4_SIGNER_PROBE_STOP_MISSING_METADATA' }
    if ($name -in @('GITHUB_WORKSPACE','RUNNER_TEMP','RUNNER_WORKSPACE')) {
        $path = [IO.Path]::GetFullPath($value).TrimEnd('\') + '\'
        if (-not $path.StartsWith($workRoot,[StringComparison]::OrdinalIgnoreCase)) {
            throw 'G4_SIGNER_PROBE_STOP_WRONG_WORKSPACE'
        }
    }
}
$repoRoot = (Resolve-Path -LiteralPath $env:GITHUB_WORKSPACE).Path
$head = (& git -C $repoRoot rev-parse HEAD | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $head -notmatch '^[0-9a-f]{40}$') {
    throw 'G4_SIGNER_PROBE_STOP_UNPINNED_GIT_SOURCE'
}
$dirty = @(& git -C $repoRoot status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) {
    throw 'G4_SIGNER_PROBE_STOP_DIRTY_SOURCE'
}
Write-Host 'G4_SIGNER_PROBE_DEDICATED_RUNNER_AND_SOURCE_PASS'

function EnvPresent([string]$name) {
    return -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))
}
function SafeConfiguredPath([string]$name,[bool]$wantFile) {
    $path = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($path)) { return 'NO_CONFIG_IN_THIS_JOB' }
    try {
        if (-not [IO.Path]::IsPathRooted($path)) { return 'UNSAFE_OR_UNRESOLVED' }
        $full = [IO.Path]::GetFullPath($path)
        if ($full.StartsWith($workRoot,[StringComparison]::OrdinalIgnoreCase)) {
            return 'REJECTED_RUNNER_WORKSPACE'
        }
        if ($wantFile) {
            if (Test-Path -LiteralPath $full -PathType Leaf -ErrorAction SilentlyContinue) {
                return 'EXISTING_FILE_NOT_IDENTITY_VERIFIED'
            }
        } else {
            if (Test-Path -LiteralPath $full -PathType Container -ErrorAction SilentlyContinue) {
                return 'EXISTING_DIR_ACL_NOT_VERIFIED'
            }
        }
        return 'CONFIGURED_PATH_NOT_FOUND'
    } catch {
        return 'UNSAFE_OR_UNRESOLVED'
    }
}

# These checks intentionally apply to this Issue #82 HostOps process only.
# GitHub workflow_dispatch secrets are NOT supplied to unrelated issue_comment jobs.
$signingNames = @('G4_RELEASE_KEYSTORE_FILE','G4_RELEASE_KEYSTORE_PASSWORD',
                  'G4_RELEASE_KEY_ALIAS','G4_RELEASE_KEY_PASSWORD',
                  'G4_RELEASE_CERT_SHA256')
$configuredCount = 0
foreach ($name in $signingNames) { if (EnvPresent $name) { $configuredCount++ } }
if ($configuredCount -eq $signingNames.Count) {
    Write-Host 'G4_SIGNER_ENV_IN_HOSTOPS=FIVE_NAMES_PRESENT_NOT_IDENTITY_VERIFIED'
} elseif ($configuredCount -eq 0) {
    Write-Host 'G4_SIGNER_ENV_IN_HOSTOPS=NONE_PRESENT_NOT_PROOF_OF_ABSENCE'
} else {
    Write-Host 'G4_SIGNER_ENV_IN_HOSTOPS=PARTIAL_NOT_READY'
}
Write-Host ('G4_SIGNER_FILE_IN_HOSTOPS=' + (SafeConfiguredPath 'G4_RELEASE_KEYSTORE_FILE' $true))
Write-Host ('G4_PRIVATE_APK_DIR_IN_HOSTOPS=' + (SafeConfiguredPath 'G4_RELEASE_PRIVATE_OUTPUT_DIR' $false))

$javaRoot = 'C:\Program Files\Eclipse Adoptium'
$jdk = @(Get-ChildItem -LiteralPath $javaRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'jdk-21*' -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'bin\keytool.exe') -PathType Leaf) })
if ($jdk.Count -gt 0) { Write-Host 'G4_KEYTOOL_JDK21=AVAILABLE' }
else { Write-Host 'G4_KEYTOOL_JDK21=UNAVAILABLE' }
$toolsRoot = 'C:\TOOL\Android-SDK\build-tools'
$signerTools = @(Get-ChildItem -LiteralPath $toolsRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object {
        (Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'aapt2.exe') -PathType Leaf)
    })
if ($signerTools.Count -gt 0) { Write-Host 'G4_ANDROID_RELEASE_AUDIT_TOOLS=AVAILABLE' }
else { Write-Host 'G4_ANDROID_RELEASE_AUDIT_TOOLS=UNAVAILABLE' }

# No credential contents or files are opened. The source workflow needs a separate
# approved, secure secret-provisioning process before an actual signed build.
Write-Host 'G4_SIGNER_CERT_FINGERPRINT=NOT_VERIFIED_BY_THIS_READONLY_PROBE'
Write-Host 'G4_GITHUB_ACTIONS_RELEASE_SECRETS=NOT_INSPECTED_BY_ISSUE_COMMENT'
Write-Host 'G4_PRIVATE_APK_VAULT_ACL=NOT_VERIFIED_BY_THIS_READONLY_PROBE'
Write-Host 'G4_SIGNED_RELEASE_BUILD=NOT_RUN'
Write-Host 'G4_REDMITV_RELEASE_INSTALL=NOT_RUN'
Write-Host 'G4_SIGNER_READONLY_INVENTORY_COMPLETED_NOT_RELEASE_PASS'
