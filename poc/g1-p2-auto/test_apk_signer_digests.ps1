$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'apk-signer-digests.ps1')
$expected = '8bf6937801524fd7c264b55855bb35a2133c242114fb66b5fa9f1907e334fd84'
$observed = @(
  'V2 Signer: certificate DN: CN=Android Debug, OU=Android, O=Android, L=Mountain View',
  'V2 Signer: certificate SHA-256 digest: ' + $expected,
  'V2 Signer: certificate SHA-1 digest: 33c166e6b88a046350c902471888897deb0326d8',
  'V2 Signer: certificate MD5 digest: 4c805c9dcf3e96257371f6326c5a5aa3'
)
$cases = @(
    @{name='real V2 Signer'; lines=$observed; expected=@($expected)},
    @{name='legacy numbered signer'; lines=@('Signer #1 certificate SHA-256 digest: ' + $expected); expected=@($expected)},
    @{name='V3 signer'; lines=@('V3 Signer: certificate SHA-256 digest: ' + $expected); expected=@($expected)},
    @{name='V3.1 signer'; lines=@('V3.1 Signer: certificate SHA-256 digest: ' + $expected); expected=@($expected)},
    @{name='scheme duplicate'; lines=@("V2 Signer: certificate SHA-256 digest: $expected","V3 Signer: certificate SHA-256 digest: $expected");expected=@($expected)},
    @{name='no digest';lines=@('V2 Signer: certificate SHA-1 digest: 33c166e6b88a046350c902471888897deb0326d8');expected=@()},
    @{name='truncated digest';lines=@('V2 Signer: certificate SHA-256 digest: abcd');expected=@()},
    @{name='untrusted free text';lines=@('WARNING: V2 Signer: certificate SHA-256 digest: ' + $expected);expected=@()}
)
foreach ($case in $cases) {
    $got = @(Get-ApkSignerSha256Digests -OutputLines $case.lines)
    if (($got -join ',') -cne ($case.expected -join ',')) {
        throw ('APK_CERT_PARSER_FAIL: ' + $case.name + ' expected_count=' +
            @($case.expected).Count + ' actual_count=' + $got.Count +
            ' actual=' + ($got -join '|') + ' input=' + ($case.lines -join '|'))
    }
    Write-Host ('APK_CERT_PARSER_PASS: ' + $case.name)
}
Write-Host 'APK_SIGNER_REAL_V2_FIXTURE_PASS no_apk_or_network'
