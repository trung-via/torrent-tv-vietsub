# Owner-side OpenSubtitles VI->EN read-only search.
# File must be run from reviewed D2 branch: no API download, no TV,
# no Windows service, no external torrent, and no model invocation.
$ErrorActionPreference = "Stop"
& {
    $secureKey = Read-Host "OpenSubtitles API key (hidden)" -AsSecureString
    $ptr = [IntPtr]::Zero
    $exitCode = 1
    try {
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
        $env:OPENSUBTITLES_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        $script = Join-Path $PSScriptRoot "owner_search.py"
        if (Get-Command py -ErrorAction SilentlyContinue) {
            & py -3 $script
            $exitCode = $LASTEXITCODE
        } elseif (Get-Command python -ErrorAction SilentlyContinue) {
            & python $script
            $exitCode = $LASTEXITCODE
        } else {
            Write-Host "PYTHON_NOT_AVAILABLE"
        }
    } catch {
        Write-Host "D2_LOCAL_PROCESS_ERROR"
    } finally {
        Remove-Item Env:\OPENSUBTITLES_API_KEY -ErrorAction SilentlyContinue
        if ($ptr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }
        Remove-Variable secureKey,ptr -ErrorAction SilentlyContinue
    }
    if ($exitCode -ne 0) {
        Write-Host "D2_SEARCH_NOT_COMPLETE"
    }
}
