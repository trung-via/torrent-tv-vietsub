"""Fail-closed TLS preflight tests. No network bind or private key in repo."""
from __future__ import annotations

import hashlib
from pathlib import Path
import ssl
import tempfile
import unittest
from unittest import mock

from p4_tls import certificate_fingerprint_sha256, create_tls_context


class P4TLSPreflightTests(unittest.TestCase):
    def test_leaf_pin_is_exact_der_sha256(self):
        with tempfile.TemporaryDirectory() as tmp:
            cert = Path(tmp) / "pc-cert.pem"
            cert.write_text(
                "-----BEGIN CERTIFICATE-----\nZmFrZQ==\n-----END CERTIFICATE-----\n",
                encoding="ascii",
            )
            with mock.patch("p4_tls.ssl.PEM_cert_to_DER_cert",return_value=b"synthetic-DER") as convert:
                self.assertEqual(
                    certificate_fingerprint_sha256(cert),
                    hashlib.sha256(b"synthetic-DER").hexdigest(),
                )
                convert.assert_called_once()
            cert.write_text("not a certificate",encoding="ascii")
            with self.assertRaisesRegex(ValueError,"PEM_REQUIRED"):
                certificate_fingerprint_sha256(cert)

    def test_context_requires_files_and_tls12(self):
        with tempfile.TemporaryDirectory() as tmp:
            cert,key=Path(tmp)/"cert.pem",Path(tmp)/"key.pem"
            with self.assertRaisesRegex(ValueError,"CERT_AND_KEY_REQUIRED"):
                create_tls_context(cert,key)
            cert.write_text("CERT",encoding="ascii")
            key.write_text("KEY",encoding="ascii")
            with mock.patch("p4_tls.ssl.SSLContext") as ssl_context, mock.patch(
                "p4_tls.certificate_fingerprint_sha256",return_value="a"*64
            ):
                ctx=create_tls_context(cert,key)
                self.assertIs(ctx,ssl_context.return_value)
                ssl_context.assert_called_once_with(ssl.PROTOCOL_TLS_SERVER)
                self.assertEqual(ctx.minimum_version,ssl.TLSVersion.TLSv1_2)
                ctx.load_cert_chain.assert_called_once_with(
                    certfile=str(cert),keyfile=str(key))

    def test_cli_does_not_bind_without_certificate(self):
        from run_assumed_source_gateway import main
        with mock.patch("sys.argv", [
            "run_assumed_source_gateway.py","--bind","192.168.1.15",
            "--port","19009","--media-key","media."+"a"*64,
            "--mock-revisions","--start-lan",
        ]), mock.patch("run_assumed_source_gateway.create_paired_server") as bind:
            with self.assertRaises(SystemExit) as stop:
                main()
            self.assertEqual(stop.exception.code,2)
            bind.assert_not_called()


if __name__ == "__main__":
    unittest.main()
