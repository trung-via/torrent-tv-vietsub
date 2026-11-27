# Pure synthetic fixtures. No ADB, private APK, device identifier or network.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'cert-parser.ps1')
$a='a'*64
$b='b'*64
$pass=0
function Assert-Pass([string]$label,[string[]]$lines,[string]$expected) {
    $actual=Get-P4SingleSignerDigest -Lines $lines
    if ($actual -cne $expected) {throw ('P4_SIGNER_TEST_FAIL_'+$label)}
    $script:pass++
    Write-Host ('P4_SIGNER_TEST_PASS_'+$label)
}
function Assert-Reject([string]$label,[string[]]$lines) {
    try {
        $null=Get-P4SingleSignerDigest -Lines $lines
        throw ('P4_SIGNER_TEST_UNSAFE_ACCEPT_'+$label)
    } catch {
        if ([string]$_.Exception.Message -like 'P4_SIGNER_TEST_UNSAFE_ACCEPT_*') {throw}
        if ([string]$_.Exception.Message -notlike 'P4_SIGNER_PARSER_STOP_*') {throw}
    }
    $script:pass++
    Write-Host ('P4_SIGNER_TEST_REJECT_'+$label)
}
$base=@('Verifies','Number of signers: 1')
$legacy=$base+@("Signer #1 certificate SHA-256 digest: $a")
$v2=$base+@("V2 Signer: certificate SHA-256 digest: $a")
$v3=$base+@("V3.0 Signer: certificate SHA-256 digest: $a")
Assert-Pass 'LEGACY' $legacy $a
Assert-Pass 'V2_BUILD37' $v2 $a
Assert-Pass 'V3_BUILD37' $v3 $a
Assert-Pass 'SAME_CERT_MULTISCHEME' ($base+@("V2 Signer: certificate SHA-256 digest: $a","V3.0 Signer: certificate SHA-256 digest: $a")) $a
Assert-Reject 'NO_VERIFIES' @('Number of signers: 1',"V2 Signer: certificate SHA-256 digest: $a")
Assert-Reject 'MULTIPLE_SIGNERS' @('Verifies','Number of signers: 2',"V2 Signer: certificate SHA-256 digest: $a")
Assert-Reject 'NO_COUNT' @('Verifies',"V2 Signer: certificate SHA-256 digest: $a")
Assert-Reject 'COUNT_DUPLICATED' @('Verifies','Number of signers: 1','Number of signers: 1',"V2 Signer: certificate SHA-256 digest: $a")
Assert-Reject 'NO_DIGEST' $base
Assert-Reject 'UNKNOWN_CERT_FORMAT' ($base+@("X2 Signer: certificate SHA-256 digest: $a"))
Assert-Reject 'NON_HEX' ($base+@('V2 Signer: certificate SHA-256 digest: '+('z'*64)))
Assert-Reject 'SHORT_DIGEST' ($base+@('V2 Signer: certificate SHA-256 digest: '+('a'*63)))
Assert-Reject 'SCHEME_DIVERGENCE' ($base+@("V2 Signer: certificate SHA-256 digest: $a","V3.0 Signer: certificate SHA-256 digest: $b"))
Assert-Reject 'SECOND_LEGACY_SIGNER' ($base+@("Signer #1 certificate SHA-256 digest: $a","Signer #2 certificate SHA-256 digest: $b"))
Write-Host ('P4_SIGNER_TEST_MATRIX_PASS='+$pass)
