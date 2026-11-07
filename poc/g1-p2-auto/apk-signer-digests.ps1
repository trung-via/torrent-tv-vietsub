# Shared, output-only parser for apksigner verify --print-certs.
# No shell, network, APK installation or file writes.
function Get-ApkSignerSha256Digests {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object[]]$OutputLines)
    # Observed: "V2 Signer: certificate SHA-256 digest: ..."
    # Also support older "Signer #1 certificate SHA-256 digest: ...",
    # V3/V3.1 and future numbered scheme spelling.
    $rx = '(?im)^\s*(?:(?:V[0-9]+(?:\.[0-9]+)?\s+)?Signer(?:\s+#\d+)?):?\s+certificate\s+SHA-256\s+digest:\s*([a-f0-9]{64})\s*$'
    $value = $OutputLines -join [Environment]::NewLine
    $found = [regex]::Matches($value, $rx)
    $unique = [System.Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($match in $found) {
        $digest = $match.Groups[1].Value.ToLowerInvariant()
        if ($unique.Add($digest)) {
            Write-Output $digest
        }
    }
}
