# Pure Windows PowerShell 5.1-compatible parser for a verified apksigner report.
# Supports legacy "Signer #1" and Android Build Tools 37 "V2 Signer" / "V3.0 Signer".
# Fail closed on ambiguous/malformed/multiple signers, different scheme digests.
function Get-P4SingleSignerDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string[]]$Lines)

    if (@($Lines | Where-Object { ([string]$_).Trim() -ceq 'Verifies' }).Count -ne 1) {
        throw 'P4_SIGNER_PARSER_STOP_NO_VERIFIED_RECEIPT'
    }
    $countMatches=@($Lines | ForEach-Object {
        [regex]::Match([string]$_,'^\s*Number of signers:\s*([0-9]+)\s*$',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    } | Where-Object { $_.Success })
    if ($countMatches.Count -ne 1 -or [string]$countMatches[0].Groups[1].Value -cne '1') {
        throw 'P4_SIGNER_PARSER_STOP_SIGNER_COUNT_NOT_ONE'
    }

    $digestMatches=@()
    $digestLines=0
    foreach ($line in $Lines) {
        $s=[string]$line
        if ($s -notmatch '(?i)\bcertificate\s+SHA-256\s+digest\s*:') { continue }
        $digestLines++
        $old=[regex]::Match($s,
            '^\s*Signer\s*#\s*1\s+certificate\s+SHA-256\s+digest:\s*([a-f0-9]{64})\s*$',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $new=[regex]::Match($s,
            '^\s*V[1-9][0-9]*(?:\.[0-9]+)?\s+Signer:\s*certificate\s+SHA-256\s+digest:\s*([a-f0-9]{64})\s*$',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($old.Success) { $digestMatches+=($old.Groups[1].Value.ToLowerInvariant()) }
        elseif ($new.Success) { $digestMatches+=($new.Groups[1].Value.ToLowerInvariant()) }
        else {throw 'P4_SIGNER_PARSER_STOP_UNRECOGNIZED_CERT_LINE'}
    }
    if ($digestLines -lt 1 -or $digestMatches.Count -ne $digestLines) {
        throw 'P4_SIGNER_PARSER_STOP_NO_CERT_DIGEST'
    }
    $unique=@($digestMatches | Sort-Object -Unique)
    if ($unique.Count -ne 1) {throw 'P4_SIGNER_PARSER_STOP_SCHEME_CERT_DIVERGENCE'}
    return [string]$unique[0]
}
