"""A real TLS handshake on CI loopback with entirely synthetic content.

No RFC1918 LAN listener, TV, Gemini API or user media is involved. This
verifies encryption + matched IP-SAN cert and existing HMAC request gates.
"""
from __future__ import annotations

import hashlib
import hmac
import http.client
from http.server import HTTPServer
import json
from pathlib import Path
import shutil
import socket
import ssl
import subprocess
import tempfile
import threading
import unittest

from assumed_source_handoff import AssumedEnglishSubtitle
from paired_activation import (
    PairedActivation,activation_request_mac,derive_session_secret,
    make_paired_handler,
)
from p4_tls import certificate_fingerprint_sha256,create_tls_context
from synthetic_mock_feed import publish_synthetic_revisions,synthetic_source_srt

MEDIA="media."+"a"*64
MASTER=b"synthetic-pairing-device-key-32x"


class LoopbackTLSTests(unittest.TestCase):
    def test_real_https_handshake_activation_and_hmac_reader(self):
        if shutil.which("openssl") is None:
            self.skipTest("OPENSSL_EXECUTABLE_UNAVAILABLE_FOR_EPHEMERAL_TEST")
        with tempfile.TemporaryDirectory() as tmp:
            cert,key=Path(tmp)/"ephemeral.pem",Path(tmp)/"ephemeral.key"
            subprocess.run([
                "openssl","req","-x509","-newkey","rsa:2048",
                "-sha256","-nodes","-days","1",
                "-keyout",str(key),"-out",str(cert),
                "-subj","/CN=127.0.0.1",
                "-addext","subjectAltName=IP:127.0.0.1",
            ],check=True,capture_output=True,timeout=25)
            host_cert_hash=certificate_fingerprint_sha256(cert)
            source=AssumedEnglishSubtitle.from_supplied(
                media_key=MEDIA,fmt="srt",source_bytes=synthetic_source_srt())
            def publish(feed,_):
                publish_synthetic_revisions(
                    MEDIA,feed,hold_seconds=0,wait=lambda _:None)
            gateway=PairedActivation(
                device_secret=MASTER,supplied={MEDIA:source},on_activate=publish)
            server=HTTPServer(("127.0.0.1",0),make_paired_handler(gateway))
            try:
                server.socket=create_tls_context(cert,key).wrap_socket(
                    server.socket,server_side=True)
                port=server.server_address[1]
                worker=threading.Thread(target=server.serve_forever,
                                        daemon=True)
                worker.start()
                # A trusted temporary certificate must match literal IP SAN.
                trusted=ssl.create_default_context(cafile=str(cert))
                with socket.create_connection(("127.0.0.1",port),timeout=3) as raw:
                    with trusted.wrap_socket(raw,server_hostname="127.0.0.1") as tls:
                        self.assertEqual(
                            hashlib.sha256(tls.getpeercert(binary_form=True)).hexdigest(),
                            host_cert_hash,
                        )
                # Default roots do NOT trust this private PC cert.
                unpaired=ssl.create_default_context()
                with self.assertRaises((ssl.SSLError, OSError)):
                    with socket.create_connection(("127.0.0.1",port),timeout=3) as raw:
                        with unpaired.wrap_socket(raw,server_hostname="127.0.0.1"):
                            pass
                nonce="1"*32
                body=json.dumps({
                    "schema":"TTV-P4-ACTIVATE-V1",
                    "media_key":MEDIA,"nonce":nonce,
                    "auth":activation_request_mac(MASTER,MEDIA,nonce)
                }).encode("ascii")
                conn=http.client.HTTPSConnection(
                    "127.0.0.1",port,context=trusted,timeout=4)
                conn.request("POST","/p4/activate",body=body,headers={
                    "Content-Type":"application/json"})
                response=conn.getresponse()
                self.assertEqual(response.status,200)
                activated=json.loads(response.read())
                conn.close()
                sid=activated["session_id"]
                path="/p4/revision/"+sid
                unauth=http.client.HTTPSConnection(
                    "127.0.0.1",port,context=trusted,timeout=4)
                unauth.request("GET",path)
                res=unauth.getresponse()
                self.assertEqual(res.status,401)
                res.read()
                unauth.close()
                secret=derive_session_secret(
                    MASTER,sid,MEDIA,source.source_sha256)
                read_nonce="2"*32
                auth=hmac.new(secret,
                    ("TTV-P4-LAN-READ-V1\n"+sid+"\n"+read_nonce).encode("ascii"),
                    hashlib.sha256).hexdigest()
                headers={"X-P4-Nonce":read_nonce,"X-P4-Authorization":auth}
                get=http.client.HTTPSConnection(
                    "127.0.0.1",port,context=trusted,timeout=4)
                get.request("GET",path,headers=headers)
                res=get.getresponse()
                self.assertEqual(res.status,200)
                revision=json.loads(res.read())
                get.close()
                self.assertEqual((revision["version"],revision["translated_count"]),(2,240))
                self.assertEqual(revision["media_key"],MEDIA)
                replay=http.client.HTTPSConnection(
                    "127.0.0.1",port,context=trusted,timeout=4)
                replay.request("GET",path,headers=headers)
                res=replay.getresponse()
                self.assertEqual(res.status,401)
                res.read()
                replay.close()
            finally:
                server.shutdown()
                server.server_close()


if __name__ == "__main__":
    unittest.main()
