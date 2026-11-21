"""P4 PC TLS-only transport bootstrap. Never opens a socket on import.

Certificate and private key are owner-managed OUTSIDE the PUBLIC GitHub repo.
The Android peer pins the SHA256 of the *leaf* certificate and retains default
HTTPS IP-SAN hostname checks. A new certificate requires deliberate re-pairing.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import re
import ssl

PEM_LEAF = re.compile(
    r"-----BEGIN CERTIFICATE-----\s*.*?\s*-----END CERTIFICATE-----",
    re.DOTALL,
)


def certificate_fingerprint_sha256(certfile: Path) -> str:
    path = Path(certfile)
    data = path.read_text(encoding="ascii")
    match = PEM_LEAF.search(data)
    if match is None:
        raise ValueError("P4_TLS_CERTIFICATE_PEM_REQUIRED")
    try:
        der = ssl.PEM_cert_to_DER_cert(match.group(0))
    except (ValueError, ssl.SSLError) as exc:
        raise ValueError("P4_TLS_CERTIFICATE_PEM_INVALID") from exc
    return hashlib.sha256(der).hexdigest()


def create_tls_context(certfile: Path, keyfile: Path) -> ssl.SSLContext:
    """TLS >=1.2, real on-disk private key, fail-closed if unavailable."""
    cert, key = Path(certfile), Path(keyfile)
    if not cert.is_file() or not key.is_file():
        raise ValueError("P4_TLS_CERT_AND_KEY_REQUIRED")
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    # Reject mismatching or unusable key before binding any network listener.
    ctx.load_cert_chain(certfile=str(cert), keyfile=str(key))
    certificate_fingerprint_sha256(cert)
    return ctx
