# Torrent TV — owner-session only auto-Vietsub agent launcher.
# Called by a fixed interactive-token scheduled task, never GitHub runner.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$session = [Diagnostics.Process]::GetCurrentProcess().SessionId
if (-not [Environment]::UserInteractive -or $session -le 0 -or
    $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    $env:GITHUB_ACTIONS -ceq 'true') {
    throw 'OWNER_BRIDGE_INTERACTIVE_OWNER_SESSION_REQUIRED'
}

$homeRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$root = Join-Path $homeRoot 'OwnerBridge'
$app = Join-Path $root 'app'
$secrets = Join-Path $root 'secrets'
$agent = Join-Path $app 'poc\p2-sub-discovery\owner_session_bridge.py'
$cache = Join-Path $homeRoot 'subtitle-trials'
$state = Join-Path $homeRoot 'P2\auto-lean120-state'

foreach ($file in @(
    (Join-Path $secrets 'opensub.dpapi'),
    (Join-Path $secrets 'gemini.dpapi'),
    $agent
)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw 'OWNER_BRIDGE_INSTALLATION_INCOMPLETE'
    }
}

function Get-OwnerSecret([string] $file) {
    # Owner's current-user DPAPI encryption, stored at enrollment.
    $cipher = Get-Content -LiteralPath $file -Raw -ErrorAction Stop
    $secret = ConvertTo-SecureString -String $cipher -ErrorAction Stop
    $ptr = [IntPtr]::Zero
    try {
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        if ($ptr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }
    }
}

try {
    $env:OPENSUBTITLES_API_KEY = Get-OwnerSecret (Join-Path $secrets 'opensub.dpapi')
    $env:GEMINI_API_KEY = Get-OwnerSecret (Join-Path $secrets 'gemini.dpapi')
    $env:PYTHONUTF8 = '1'
    # Owner-only Python; no keys or film data in GitHub runner context.
    & py -3 $agent --owner-root $root --cache-root $cache --state-root $state
    if ($LASTEXITCODE -ne 0) {
        throw 'OWNER_BRIDGE_AGENT_EXITED_WITH_ERROR'
    }
}
finally {
    Remove-Item Env:\OPENSUBTITLES_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\GEMINI_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\PYTHONUTF8 -ErrorAction SilentlyContinue
}
