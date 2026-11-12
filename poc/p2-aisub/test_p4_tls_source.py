"""Read-only security invariants for P4 TLS bridge, no PC/TV or credentials."""
from __future__ import annotations

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / "p4-auto-sub"


class P4TlsSourceContracts(unittest.TestCase):
    def read(self,name):
        return (ROOT/name).read_text(encoding="utf-8")

    def test_p4_urls_are_https_and_no_default_plaintext(self):
        lan=self.read("P4LanClient.kt")
        self.assertIn('return URL("https://$host:$port/p4/revision/$sessionId")',lan)
        self.assertIn('return URL("https://$host:$port/p4/activate")',lan)
        self.assertIn("P4PinnedTls.open(url, certPinSha256)",lan)
        self.assertNotIn('URL("http://',lan)
        self.assertIn("internal fun isPrivateIPv4",lan)
        activation=self.read("P4ActivationClient.kt")
        self.assertIn("P4PinnedTls.open(",activation)
        self.assertIn("certPinSha256",activation)

    def test_exact_pin_and_ip_san_required_without_hostname_bypass(self):
        tls=self.read("P4PinnedTls.kt")
        for snippet in (
            "HttpsURLConnection","X509TrustManager","TLSv1.2",
            "MessageDigest.isEqual(actual, expected)",
            "P4_TLS_CERT_PIN_MISMATCH",
            "P4_TLS_IP_SAN_MISMATCH",
            "cert.subjectAlternativeNames",
            "cert.checkValidity()",
            'url.protocol != "https"',
            "P4LanClient.isPrivateIPv4(url.host)",
        ):
            self.assertIn(snippet,tls)
        self.assertNotIn("setHostnameVerifier",tls.split("return conn")[0].replace(
            "// Do NOT call setHostnameVerifier:", ""))
        self.assertNotIn("hostnameVerifier =",tls)
        self.assertNotIn("X509TrustManager()",tls)
        self.assertNotIn("return true",tls)

    def test_pairing_does_not_migrate_http_secret_without_pin(self):
        store=self.read("P4PairingStore.kt")
        self.assertIn("p4-tv-paired-pc-v2-tls",store)
        self.assertIn("certPinSha256:String",store)
        self.assertIn("deviceSecret + pinBytes",store)
        self.assertIn("encrypted.size!=80",store)
        self.assertIn("AES/GCM/NoPadding",store)
        self.assertIn("deleteEntry(ALIAS)",store)
        bridge=self.read("activity_patch.py")
        self.assertIn("device.certPinSha256",bridge)
        self.assertIn("scope.certPinSha256",bridge)
        self.assertIn("match.groupValues[4]",bridge)
        self.assertIn("P4PinnedTls.normalizePin",bridge)

    def test_overlay_packs_tls_source_in_real_composed_build(self):
        overlay=self.read("apply.py")
        self.assertIn('TLS_CLIENT_FILE = "P4PinnedTls.kt"',overlay)
        self.assertIn("TLS_CLIENT_FILE)]",overlay)


if __name__ == "__main__":
    unittest.main()
