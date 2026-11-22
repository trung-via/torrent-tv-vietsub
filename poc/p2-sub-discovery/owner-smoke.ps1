# Read-only OpenSubtitles key smoke for owner's Windows PowerShell.
# Interactive secret entry; only this process environment receives the key.
# No Windows service, firewall, ADB, torrent, media or subtitle download.
$ErrorActionPreference = "Stop"
$secure = Read-Host "OpenSubtitles API key (input hidden)" -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $env:OPENSUBTITLES_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    $file = Join-Path $PSScriptRoot "smoke_api.py"
    if (Get-Command py -ErrorAction SilentlyContinue) {
        & py -3 $file
    } elseif (Get-Command python -ErrorAction SilentlyContinue) {
        & python $file
    } else {
        Write-Output "PYTHON_NOT_AVAILABLE"
        return
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Output "OpenSubtitles read-only smoke did not pass; inspect the sanitized code above."
    }
} finally {
    Remove-Item Env:\OPENSUBTITLES_API_KEY -ErrorAction SilentlyContinue
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
}
